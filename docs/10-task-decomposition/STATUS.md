# 工作包状态

## WP-00 · 工程骨架

- 状态：**done**
- 分支：`main`
- 工程骨架提交：`7f4666a`；最新 CI 成功提交：`e67d759`
- 完成内容：
  - XcodeGen `project.yml`：App target + 9 个 SwiftPM library target。
  - 根 `Package.swift`：9 个 library + 9 个 test target。
  - 9 个模块 marker 与占位测试。
  - SwiftUI App 入口与占位页。
  - GitHub Actions macOS CI：xcodegen → swift test → 自动选模拟器 → build → test → 上传 `.xcresult`。
  - Makefile、SwiftFormat、SwiftLint、`.gitignore`、`.gitattributes`。
  - `BUILD.md`、`CI-SETUP.md`。
- 本地静态校验：
  - `Package.swift` 中所有 target path 存在。
  - `project.yml` 的 9 个 product 与 `Package.swift` 一致。
  - `Info.plist` XML 可解析。
  - 21 个 Swift 文件括号平衡；Makefile 使用 tab。
  - Git 工作区干净。
- **macOS CI 结果：success**
  - 最新 Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40090672908
  - 提交：`e67d759c4c96c714cf72d10bf616073861029fb3`
  - 所有步骤通过：Set up / Checkout / Toolchain / Install XcodeGen / Generate / Swift package tests / Select simulator / Build app / Run app tests / Upload xcresult。
  - 首次成功 Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40090394824
- 远程状态：
  - `origin`：`https://github.com/JHub-Wei/StyleTone.git`
  - `main` 已推送；本地/远程均包含工程骨架。
- 下一步：
  1. 启动 **WP-01 Core 契约**（`docs/12-session-prompts.md` 的 S-A1 Prompt）。
  2. WP-01 完成后打 `core-v1` tag，再并行 WP-02/03/04。
- 说明：
  - 本次验证使用 GitHub Actions macOS runner；Windows 本机仍不能直接跑 `xcodebuild`。
  - GitHub 直连需要本地代理；Git 已配置当前仓库代理 `127.0.0.1:7890`。
  - 后续若新增 iOS-only API 导致 `swift test` 失败，可把 SwiftPM 测试拆成 iOS 测试或使用 `xcodebuild test`。

---

## WP-01 · Core 契约

- 状态：**done**
- 提交：`1117dae`
- Tag：`core-v1`
- CI：https://github.com/JHub-Wei/StyleTone/actions/runs/40091414979 （success）
- 完成内容：
  - `PixelSize`、`NormalizedPoint/Rect`、`ImageAsset`、`MaskBuffer`。
  - `PortraitAnalysis`、人脸/人体关键点、分析 warning。
  - `StyleProfile` schema 3 + 参数结构 + ISO8601 JSON 编解码。
  - `ManualAdjustments`、`BlemishPoint`、`RenderRequest`、`RenderOutput`。
  - `PairQuality`、`PairSample`、`CalibrationAnswer`。
  - `ExportOptions`、`PurchaseState`、`PurchaseProduct`。
  - 全部协议：分析/配对/学习/修饰/形变/渲染/导出/存储/购买。
  - `StyleToneError`、`AppError` 映射、Logger/Date 支持。
  - Core 契约测试 + test doubles（Mock analyzer/learner/purchaser/store）。
- 验收结果：
  - `swift test` 通过。
  - Xcode App build/test 通过。
  - 无网络/照片上传代码。
- 下一步：
  1. 并行启动 WP-02（图像）、WP-03（设计/Shell）、WP-04（测试 Harness）。
  2. 三者完成后进入 WP-05/06/07/08/09/10/11。

