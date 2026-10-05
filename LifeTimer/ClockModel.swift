import Combine
import Foundation

enum ClockMode: String, Codable, Hashable, CaseIterable, Sendable {
    case clock
    case stopwatch
}

struct ClockState: Codable, Hashable {
    var mode: ClockMode
    var startDate: Date
    var accumulated: TimeInterval
    var isRunning: Bool

    func elapsed(at date: Date) -> TimeInterval {
        guard isRunning else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(startDate))
    }
}

enum ClockText {
    static func clockString(at date: Date) -> String {
        let parts = Calendar.current.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: date
        )
        let milliseconds = (parts.nanosecond ?? 0) / 1_000_000
        return String(
            format: "%02d:%02d:%02d.%03d",
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0,
            milliseconds
        )
    }

    static func elapsedString(_ interval: TimeInterval) -> String {
        let totalMilliseconds = Int(max(0, interval) * 1000)
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        return String(
            format: "%02d:%02d:%02d.%03d",
            totalSeconds / 3600,
            (totalSeconds % 3600) / 60,
            totalSeconds % 60,
            milliseconds
        )
    }

    static func string(for state: ClockState, at date: Date) -> String {
        switch state.mode {
        case .clock:
            return clockString(at: date)
        case .stopwatch:
            return elapsedString(state.elapsed(at: date))
        }
    }

    static func modeLabel(_ mode: ClockMode) -> String {
        switch mode {
        case .clock: return "当前时间"
        case .stopwatch: return "秒表"
        }
    }
}

@MainActor
final class ClockModel: ObservableObject {
    @Published private(set) var state: ClockState

    init() {
        let now = Date()
        state = ClockState(
            mode: .clock,
            startDate: now,
            accumulated: 0,
            isRunning: false
        )
    }

    var mode: ClockMode { state.mode }

    func displayString(at date: Date) -> String {
        ClockText.string(for: state, at: date)
    }

    func setMode(_ mode: ClockMode) {
        guard state.mode != mode else { return }
        state.mode = mode
        if mode == .stopwatch {
            state.startDate = Date()
            state.isRunning = false
            state.accumulated = 0
        }
    }

    func toggleStopwatch() {
        if state.isRunning {
            state.accumulated = state.elapsed(at: Date())
            state.isRunning = false
        } else {
            state.startDate = Date()
            state.isRunning = true
        }
    }

    func resetStopwatch() {
        state.accumulated = 0
        state.isRunning = false
        state.startDate = Date()
    }
}
