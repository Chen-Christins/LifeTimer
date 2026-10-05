import SwiftUI

struct ContentView: View {
    @StateObject private var model = ClockModel()
    @StateObject private var pip = PiPClockController()
    @State private var mode: ClockMode = .clock

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    previewCard
                    modePicker
                    if mode == .stopwatch {
                        stopwatchControls
                    }
                    floatingSection
                }
                .padding()
            }
            .navigationTitle("LifeTimer")
            .task {
                mode = model.mode
                if ProcessInfo.processInfo.arguments.contains("-StartPiPOnLaunch") {
                    startFloating()
                }
            }
        }
    }

    private var previewCard: some View {
        VStack(spacing: 10) {
            Text(mode == .clock ? "当前时间" : "秒表")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                Text(model.displayString(at: context.date))
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            Text("精确到毫秒")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
    }

    private var modePicker: some View {
        Picker("模式", selection: $mode) {
            Text("当前时间").tag(ClockMode.clock)
            Text("秒表").tag(ClockMode.stopwatch)
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, newValue in
            model.setMode(newValue)
        }
    }

    private var stopwatchControls: some View {
        HStack(spacing: 12) {
            Button {
                model.toggleStopwatch()
            } label: {
                Label(
                    model.state.isRunning ? "暂停" : "开始",
                    systemImage: model.state.isRunning ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                model.resetStopwatch()
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var floatingSection: some View {
        VStack(spacing: 14) {
            PiPPreviewView(displayLayer: pip.displayLayer)
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    startFloating()
                } label: {
                    Label(pip.isRunning ? "悬浮中" : "开启悬浮窗口", systemImage: "pip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    pip.stop()
                } label: {
                    Label("停止", systemImage: "stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!pip.isRunning)
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
    }

    private var statusText: String {
        if let error = pip.lastError { return error }
        return pip.isPiPActive ? "悬浮窗口中（可退到后台）" : "未悬浮"
    }

    private func startFloating() {
        pip.textProvider = { model.displayString(at: Date()) }
        pip.start()
    }
}

#Preview {
    ContentView()
}
