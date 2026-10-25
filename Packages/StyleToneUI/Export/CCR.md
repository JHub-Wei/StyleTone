# CCR 申请 · WP-19 导出/相册/分享

- 状态：**proposed**（未审批；未修改 `core-v1` 的冻结类型/协议）
- 日期：2026-10-25
- 关联：contracts §3.6、§4、§8、§9、§10；WP-19 card
- 申请范围：新增 UI-owned 导出边界与展示类型

`StyleToneUI/Export` 没有修改 `StyleToneCore` 的公开契约。以下类型是 UI 模块内新增的适配/
展示层，按 contracts §4 的“新能力用新协议/扩展，走 CCR”要求登记，供 WP-20/24/26 评审。

---

## 1. 新增公开类型

| 类型 | 作用 | 为什么不是 Core |
|---|---|---|
| `ExportPhotoLibrary` / `PhotoLibraryAccess` / `ExportLibraryError` | add-only 相册边界；`save(ExportStagedFile)` | Core 只有 `ImageExporting`（文件 URL）；相册保存属于设备能力，Core 不 import PhotoKit |
| `ExportQuotaServicing` / `ExportEntitlement` / `UnavailableExportQuota` / `UnlimitedExportQuota` | 免费额度读取与成功计数 | Core `PurchaseServicing` 只有订阅状态，没有次数；WP-20 负责实现 |
| `ExportFailure` + `Kind` + `Recovery` | 导出失败展示、恢复动作、诊断码 | Core `AppError` 的恢复动作不含 share/save/upgrade；导出需要更具体的 UI 动作 |
| `ExportSource` / `ExportSettings` / `ExportQuality` / `ExportStagedFile` / `ExportOutcome` / `ExportTimings` / `ExportDestination` / `ExportStage` / `ExportProgress` / `ExportAcceptance` / `ExportPipelineError` | UI 编排与展示值类型 | 仅导出面板使用；不污染 Core |
| `ExportTemporaryFileStore` | 临时目录、过期清扫、编码文件元数据校验、file protection | WP-02 的 `FileImageExporter` 只负责写文件；生命周期由 WP-19 拥有 |
| `ExportDependencies` / `ExportViewModel` / `ExportScreen` / `ExportAccessibilityID` / `ExportCopy` / `ExportText` | DI、状态机、SwiftUI 面板、标识与文案 | UI 层 |

## 2. 与冻结契约的关系

- `ImageExporting` / `ImageRendering` 签名未改；WP-19 只调用。
- `ExportOptions` 未改；`stripLocation` 默认 `true`，UI 不提供关闭开关。
- `AppError` 未改；`ExportFailure` 是并行的展示模型，`ExportFailure.map` 会把
  `StyleToneError` / `ExportPipelineError` / `ExportLibraryError` 映射为诊断码。
  **建议后续 CCR**：让 `ExportFailure` 内嵌 `AppError` 或让 `AppError` 增加导出恢复动作，
  统一 WP-23 的错误码/诊断展示。
- `LocalizationKey` 前缀表未改；面板文案用 `editor.export.*`，错误用 `error.export.*`，
  Close 复用 WP-03 的 `common.closeButton`（`.common` 是 WP-03 保留前缀）。
- 无障碍标识用 `AccessibilityScreen.export`，未改枚举。

## 3. 需要评审的语义

1. **计数**：契约写“保存/分享均计数”。当前每次成功 save/share 各计一次；同一张图先保存再分享
   会计两次。若要“一次导出只计一次”，需要 WP-20/产品确认并在 `ExportViewModel` 增加 session 去重。
2. **额度写失败**：照片已交付但 WP-20 计数写失败时，导出仍显示成功（`counted == false`），
   同时进入 fail-closed 的额度不可用状态，阻止下一次导出，直到 `refreshEntitlement()` 成功。
3. **全分辨率守卫**：要求渲染尺寸与编码后的**实际文件尺寸**都等于
   `ExportSource.expectedPixelSize`（用 ImageIO 读取元数据，不解码像素）。若 WP-17 未来改变画布
   尺寸（裁切/拉长），需要 CCR 明确“允许的尺寸变化”策略。
4. **文件保护**：WP-02 writer 先写文件；WP-19 在写前把目录设为 `.complete`、写后对文件再设一次。
   若安全评审要求“创建即保护”的强保证，需要 WP-02 在 writer 内部设置 protection class。
5. **色彩空间**：`ExportOptions` 没有输出色彩空间字段，WP-02 默认 sRGB；P3 原图会转 sRGB。
   若要保留 Display P3，需要扩展 Core 或由 App 注入 writer 配置。
6. **性能**：WP-19 的 12MP 测试是 macOS 上的编排 + 平台 ImageIO 编码 p95，不替代 WP-24 的
   iPhone 13 全管线测量；`measure` 基线由 WP-24 建立。
7. **隐私清单**：过期清扫使用 file timestamp API，App 需要合并
   `Integration/PrivacyInfo.xcprivacy.fragment` 的 `C617.1` reason。
8. **性能测试形态**：WP-19 用自定义 p95（预热 + 10 次）而不是 XCTest `measure` 基线，因为
   契约验收是 p95 而不是平均值；完整 WP-17 管线与 ≤500MB 内存仍由 WP-24 在设备上测。

## 4. 审批后动作

- WP-20 实现 `ExportQuotaServicing`（真实计数、订阅、恢复）并注入 App。
- WP-03/24 按 `Integration/AppWiring.md` 接线路由、DI、Info.plist。
- WP-23 复用 `ExportFailure`/`AppError` 的映射；若统一错误模型，需另开 CCR。
- WP-26 收 `editor.export.*` / `error.export.*` 与相册用途文案进字符串目录。
