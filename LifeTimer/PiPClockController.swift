import AVFoundation
import AVKit
import Combine
import OSLog
import UIKit

@MainActor
final class PiPClockController: NSObject, ObservableObject {
    @Published private(set) var isPiPActive = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    let displayLayer = AVSampleBufferDisplayLayer()

    var textProvider: (() -> String)?

    private var pipController: AVPictureInPictureController?
    private var displayLink: CADisplayLink?
    private var timebase: CMTimebase?
    private var pool: CVPixelBufferPool?
    private var formatDesc: CMVideoFormatDescription?
    private var audioEngine: AVAudioEngine?
    private var isPrepared = false
    private var cancellables = Set<AnyCancellable>()

    private let logger = Logger(subsystem: "LifeTimer", category: "PiP")

    private let frameRate: Int = 30
    private let renderSize = CGSize(width: 640, height: 360)

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    func prepare() {
        guard !isPrepared else { return }
        setupTimebase()
        setupPool()
        setupPiPController()
        isPrepared = true
    }

    func start() {
        prepare()
        startAudio()
        startDisplayLink()
        isRunning = true
        pipController?.invalidatePlaybackState()
        if pipController?.isPictureInPicturePossible == true {
            pipController?.startPictureInPicture()
        }
    }

    func stop() {
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        displayLink?.invalidate()
        displayLink = nil
        stopAudio()
        isRunning = false
    }

    private func setupTimebase() {
        var tb: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &tb
        )
        guard status == noErr, let tb else { return }
        CMTimebaseSetRate(tb, rate: 1.0)
        displayLayer.controlTimebase = tb
        timebase = tb
    }

    private func setupPool() {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(renderSize.width),
            kCVPixelBufferHeightKey as String: Int(renderSize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var newPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &newPool)
        guard let newPool else { return }
        pool = newPool

        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, newPool, &pb)
        guard let pb else { return }
        var desc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescriptionOut: &desc
        )
        formatDesc = desc
    }

    private func setupPiPController() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            lastError = "此设备或模拟器不支持画中画"
            logger.error("Picture in Picture not supported on this device")
            return
        }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        pipController = controller

        controller.publisher(for: \.isPictureInPicturePossible)
            .receive(on: RunLoop.main)
            .sink { [weak self] possible in
                guard let self else { return }
                self.logger.log("isPictureInPicturePossible: \(possible)")
                guard possible, self.isRunning,
                      self.pipController?.isPictureInPictureActive == false else { return }
                self.pipController?.startPictureInPicture()
            }
            .store(in: &cancellables)
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(renderTick))
        link.preferredFramesPerSecond = frameRate
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func renderTick() {
        guard let pool, let formatDesc, let timebase else { return }
        let text = textProvider?() ?? "--:--:--.---"
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        guard let pixelBuffer = pb else { return }
        draw(text: text, into: pixelBuffer)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            presentationTimeStamp: CMTimebaseGetTime(timebase),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return }
        CMSetAttachment(
            sampleBuffer,
            key: kCMSampleAttachmentKey_DisplayImmediately,
            value: kCFBooleanTrue,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        )
        displayLayer.enqueue(sampleBuffer)
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
    }

    private func draw(text: String, into pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()

            let maxWidth = CGFloat(width) * 0.92
            var fontSize = CGFloat(height) * 0.5
            var font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
            let measured = (text as NSString).size(withAttributes: [.font: font]).width
            if measured > maxWidth {
                fontSize *= maxWidth / measured
                font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: style
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                in: CGRect(
                    x: 0,
                    y: (CGFloat(height) - textSize.height) / 2,
                    width: CGFloat(width),
                    height: textSize.height
                ),
                withAttributes: attrs
            )
        }
        guard let cgImage = image.cgImage else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func startAudio() {
        guard audioEngine == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            lastError = "音频会话失败：\(error.localizedDescription)"
        }

        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        let source = AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in abl {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        do {
            try engine.start()
            audioEngine = engine
        } catch {
            lastError = "音频启动失败：\(error.localizedDescription)"
        }
    }

    private func stopAudio() {
        audioEngine?.stop()
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension PiPClockController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = false }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isPiPActive = false
            self.lastError = "画中画启动失败：\(error.localizedDescription)"
        }
    }
}

extension PiPClockController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}
}
