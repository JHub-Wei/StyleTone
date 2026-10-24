# 工作包状态

## WP-00 · 工程骨架

- 状态：**review / CI_PENDING**
- 分支：`main`
- 提交：`7f4666a`（骨架）、`5f58427`（构建说明）
- 完成内容：
  - XcodeGen `project.yml`：App target + 9 个 SwiftPM library target。
  - 根 `Package.swift`：9 个 library + 9 个 test target。
  - 9 个模块 marker 与占位测试。
  - SwiftUI App 入口与占位页。
  - GitHub Actions macOS CI（xcodegen/build/swift test/app test）。
  - Makefile、SwiftFormat、SwiftLint、`.gitignore`、`.gitattributes`。
  - `BUILD.md` 构建说明。
- 已完成的本地静态校验：
  - `Package.swift` 中所有 target path 存在。
  - `project.yml` 的 9 个 product 与 `Package.swift` 一致。
  - `Info.plist` XML 可解析。
  - 30 个 Swift 文件括号平衡；Makefile 使用 tab。
  - Git 工作区干净。
- **未完成（受 Windows 限制）**：
  - 未运行 `xcodegen generate`。
  - 未运行 `xcodebuild build/test`。
  - 未运行 `swift test`（本机无 Swift/Xcode）。
- 下一步：
  1. 在 macOS 上执行 `brew install xcodegen` → `xcodegen generate` → `make build` / `make test`。
  2. 或推送到 GitHub，让 `.github/workflows/ios.yml` 跑 macOS CI（无需 Mac，见 [CI-SETUP.md](../../CI-SETUP.md)）。
  3. CI 绿灯后把 WP-00 标记为 `done`，再启动 WP-01（Core 契约）。
- 已知风险：
  - XcodeGen 的本地 package 路径 `path: .` 需在 macOS 实机验证。
  - CI 默认模拟器 `iPhone 16` 需与 runner 的 Xcode 版本匹配；不匹配时改 `project.yml`/`Makefile`/CI 的 destination。
  - 测试 target 使用 `TEST_HOST` 指向 App，需在 macOS 验证；若报 host 错误，可改为无 host 的 logic test。

> Windows 会话不要声称“构建通过”；只报告 `CI_PENDING` 或 `BUILD_UNVERIFIED_ON_WINDOWS`。
