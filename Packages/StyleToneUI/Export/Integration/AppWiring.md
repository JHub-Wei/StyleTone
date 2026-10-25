# WP-19 · App 接线建议（未执行）

本目录只拥有 `StyleToneUI/Export`。以下是让真实 App 从编辑器进入导出面板所需的 App/Core 侧
改动，供 WP-03（App Shell/DI）与 WP-24（集成）执行；本会话按约束**没有修改** `App/`、
`App/Info.plist`、`Package.swift` 或 `project.yml`。

## 1. Info.plist

把 [`Info.plist.fragment`](Info.plist.fragment) 的 `NSPhotoLibraryAddUsageDescription` 合入
`App/Info.plist`。`project.yml` 已指向该文件，无需改工程配置。

同时把 [`PrivacyInfo.xcprivacy.fragment`](PrivacyInfo.xcprivacy.fragment) 的
`NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1` 合并进 App 的
`PrivacyInfo.xcprivacy`（若 WP-21 已有清单，合并数组，不要覆盖）。

## 2. AppDependencies

`App/AppShell/AppDependencies.swift` 目前只有 Core 协议。增加两项导出依赖：

```swift
import StyleToneUI

struct AppDependencies: Sendable {
    // …existing…
    var exportPhotoLibrary: any ExportPhotoLibrary
    var exportQuota: any ExportQuotaServicing

    init(
        // …existing…
        exportPhotoLibrary: any ExportPhotoLibrary = UnavailableExportPhotoLibrary(),
        exportQuota: any ExportQuotaServicing = UnavailableExportQuota()
    ) {
        // …existing…
        self.exportPhotoLibrary = exportPhotoLibrary
        self.exportQuota = exportQuota
    }
}
```

App 进程内使用 `PhotoKitExportPhotoLibrary()`（iOS）和 WP-20 的额度实现；不要用
`UnlimitedExportQuota` 作为生产默认。

## 3. 路由

`App/AppShell/AppShellView.swift` 的 `case .export:` 目前渲染 `ExportPlaceholderScreen`。
替换为 `ExportScreen`，并把导出源从 WP-17 的编辑器状态传入：

```swift
case .export:
    if let source = editorExportSource {
        ExportScreen(
            source: source,
            dependencies: ExportDependencies(
                renderer: dependencies.imageRenderer,   // WP-17
                exporter: dependencies.exporter,        // WP-02
                photoLibrary: dependencies.exportPhotoLibrary,
                quota: dependencies.exportQuota,
                logger: dependencies.logger,
                dateProvider: dependencies.dateProvider,
                fileStore: ExportTemporaryFileStore(),
                supportsSystemShare: true
            ),
            onClose: { actions.dismissSheet() },
            onUpgrade: { actions.navigate(.paywall) }
        )
    } else {
        // 没有全分辨率 RenderRequest 时显示明确的空态，而不是伪造预览。
    }
```

`ExportSource.request.image` 必须是全分辨率原图；预览图单独放在 `preview`。没有 WP-17 的
`RenderRequest` 时不要构造假 request，否则全分辨率守卫会正确失败。

每次展示面板都应新建一个 `ExportViewModel`（或至少在新的 `ExportSource` 上重建）。保存中关闭
面板时，任务仍会收尾并计数；复用旧 model 可能带着上一次的 `finished`/`cancelled` 状态再次出现。

## 4. 购买后刷新

`ExportScreen.onUpgrade` 默认是 no-op。WP-20 接线时应在付费墙关闭/购买成功/恢复成功后调用：

```swift
let viewModel = ExportViewModel(source: source, dependencies: deps)
// paywall completion:
Task { await viewModel.refreshEntitlement() }
```

如果 App 用 `ExportScreen(source:dependencies:...)` 的便捷初始化，拿不到 view model；建议改用
`ExportScreen(viewModel:onClose:onUpgrade:)`，把 `ExportViewModel` 留在 composition root。

## 5. UI 测试

仓库目前没有 XCUITest target。WP-24 增加后可用：

- `export.root`
- `export.exportButton`（Save）
- `export.shareButton`
- `export.progress`
- `export.cancelButton`
- `export.permissionNotice.settingsButton`
- `export.permissionNotice.shareButton`
- `export.failure.*`
- `export.result.doneButton`

真机/模拟器上的 PhotoKit 授权弹窗需要 `addUIInterruptionMonitor` 或对应的系统权限注入；
本 WP 的权限逻辑已由 `FakePhotoLibrary` / `GatedPhotoLibrary` 覆盖。

## 6. 验收前检查

```bash
# macOS
swift test --filter Export
xcodebuild -project StyleTone.xcodeproj -scheme StyleTone \
  -destination 'platform=iOS Simulator,name=iPhone 15' test

# 真机（WP-24）
# - 12MP 全流程 p95、内存、48MP 提示
# - 首次授权 / 拒绝后 Settings 返回 / 分享完成与取消
# - 导出后 <tmp>/StyleToneExports 为空
# - PhotoKit add-only 弹窗文案与 Info.plist 一致
```
