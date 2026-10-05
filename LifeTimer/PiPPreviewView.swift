import AVFoundation
import SwiftUI

struct PiPPreviewView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.displayLayer = displayLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        var displayLayer: AVSampleBufferDisplayLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let displayLayer {
                    layer.addSublayer(displayLayer)
                    displayLayer.videoGravity = .resizeAspect
                    setNeedsLayout()
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            displayLayer?.frame = bounds
        }
    }
}
