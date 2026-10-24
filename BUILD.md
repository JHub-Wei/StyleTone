# BUILD · 工程骨架

> WP-00 只提供可生成、可编译的骨架；业务功能尚未实现。

## 环境

- macOS（iOS 构建必需）
- Xcode（当前稳定版；iOS 17+ SDK）
- XcodeGen：`brew install xcodegen`
- Swift 6（随 Xcode 提供）

## 生成与构建

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project StyleTone.xcodeproj -scheme StyleTone \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO build
```

## 测试

```bash
# SwiftPM 单元测试（macOS 可跑，骨架阶段）
swift test

# iOS 模拟器 App 测试
xcodebuild -project StyleTone.xcodeproj -scheme StyleTone \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

如果模拟器名称不同，用 `xcrun simctl list devices available` 查看并替换 `iPhone 16`。

## 真机自用

1. 在 Xcode 中打开 `StyleTone.xcodeproj`。
2. 选择 `StyleTone` target → Signing & Capabilities → 选择自己的 Team。
3. 连接 iPhone，选择真机运行。
4. 免费 Apple ID 签名通常 7 天过期；建议 Apple Developer Program（$99/年）。

## Windows

Windows 不能运行 `xcodebuild`。可以在 Windows 写代码并推送到 GitHub，由 `.github/workflows/ios.yml` 在 macOS runner 上构建/测试。没有 Mac 时，TestFlight 也需要 macOS CI 先产出构建。

完整的 Windows→macOS CI 方案见 [CI-SETUP.md](CI-SETUP.md)。

## 当前骨架

- 9 个 SwiftPM library target：Core / Imaging / Vision / Geometry / Retouch / Learning / Persistence / Commerce / UI。
- 每个 target 只有模块 marker 与占位测试。
- App 入口是 `App/StyleToneApp.swift`，显示占位页。
- 业务实现从 WP-01（Core 契约）开始。
