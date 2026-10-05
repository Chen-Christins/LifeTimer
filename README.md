# LifeTimer

一个 iOS 毫秒级时钟 / 秒表。除了 App 内的大字号毫秒时钟外，还可以通过**画中画（Picture in Picture）悬浮小窗**，在退到后台、切到其它 App 时继续显示毫秒跳动。

> 仅供个人侧载使用。使用画中画作为时钟并非 Apple 的典型用途，上架 App Store 大概率会被拒。

## 功能

- **当前时间**：显示到毫秒，如 `00:33:37.197`
- **秒表**：开始 / 暂停 / 重置，显示到毫秒
- **悬浮小窗**：基于 PiP 的自绘帧，30fps 刷新，退出 App 后仍可悬浮在其它界面之上
- 深色悬浮窗，字号随窗口尺寸自适应

## 为什么用画中画而不是灵动岛？

灵动岛（Live Activity）无法显示毫秒：

- 实时活动由系统托管，会忽略自定义动画修饰符，`TimelineView(.animation)` 在其视图中不生效；
- 唯一能持续自更新的是系统计时器文本 `Text(timerInterval:)`，精度只到**秒**；
- `activity.update` 与 APNs 推送都有频率预算，达不到毫秒。

所以灵动岛最多只能做到秒级。要在后台持续显示毫秒，只能借助画中画自己渲染视频帧。

## 环境要求

- Xcode 27.0+（iOS 27.0 SDK）
- iOS 27.0+
- 真机运行（**模拟器不支持画中画**）
- 自签名 / 个人开发者证书

## 构建与运行

```bash
xcodebuild \
  -project LifeTimer.xcodeproj \
  -scheme LifeTimer \
  -configuration Debug \
  -destination 'platform=iOS,id=<你的设备 UDID>' \
  build
```

或直接用 Xcode 打开 `LifeTimer.xcodeproj` 运行到真机。

首次运行若提示「不受信任的开发者」，到 **设置 → 通用 → VPN与设备管理** 信任你的开发者证书。

启动后：

1. 点击「开启悬浮窗口」，出现悬浮小窗显示毫秒；
2. 上滑退到后台 / 切到其它 App，小窗继续显示；
3. 点击「停止」关闭悬浮窗。

## 实现要点

- `LifeTimer/PiPClockController.swift`：用 `AVSampleBufferDisplayLayer` + `CADisplayLink`(30fps) 把当前时间绘制进 `CVPixelBuffer`，经 `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:)` 送入画中画；用静音 `AVAudioEngine` + `AVAudioSession(.playback)` 维持后台运行，依赖 `UIBackgroundModes = [audio]`。
- `LifeTimer/PiPPreviewView.swift`：在 App 内承载同一 `AVSampleBufferDisplayLayer` 作为 inline 预览（画中画要求 layer 存在于可见视图层级）。
- `LifeTimer/ClockModel.swift`：时钟 / 秒表状态与毫秒格式化。
- `LifeTimer/ContentView.swift`：界面与交互。
- `Info.plist`：仅声明 `UIBackgroundModes = [audio]`，与 Xcode 生成的主 Info.plist 合并。

## 已知限制

- 悬浮窗比例固定为 16:9，附带系统播放/暂停按钮（对时钟无实际作用）；
- 锁屏、音频被其它 App 占用、系统内存紧张时，画中画可能被暂停；
- 30fps 持续渲染 + 保活音频，耗电较高；
- 仅个人使用，请勿上架。

## 持续集成

`.github/workflows/build.yml` 会在每次 push / PR 时用最新的 Xcode 构建 iOS 模拟器版本（不签名），并把 `LifeTimer.app` 作为构建产物上传。

## License

[MIT](LICENSE)
