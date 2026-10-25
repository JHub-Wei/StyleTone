# WP-21 · 设置 / 隐私 / 诊断

- 状态：**review**（实现与测试完成；本会话是 Windows，iOS 构建与测试待 macOS CI）
- 范围：`Packages/StyleToneUI/Sources/StyleToneUI/Settings/`（SwiftPM target 源码）
- 文档：`Packages/StyleToneUI/Settings/`（任务卡中的 WP 目录）
- 测试：`Packages/StyleToneUI/Tests/StyleToneUITests/Settings/`
- 依赖：WP-08 `StyleProfileStore.deleteAll()`
- 解锁：WP-26 集成、WP-28 隐私政策/客服地址

> 任务卡写的所有权目录是 `Packages/StyleToneUI/Settings/`，但 SwiftPM target 的实际路径是
> `Packages/StyleToneUI/Sources/StyleToneUI`。因此实现放在 `Sources/StyleToneUI/Settings/`，
> 本目录放交付文档；测试必须放在 `Tests/StyleToneUITests/Settings/` 才会被 SwiftPM 编译。
> 没有改 `DesignSystem/`、`App/`、Persistence 或任何其他 WP 的目录。

---

## 1. 页面与交付

| 能力 | 实现 |
|---|---|
| 隐私说明 | 设置页隐私卡 + `SettingsPrivacyView`：本地处理、无账号、无上传、数据清单、Apple 购买边界、诊断说明、用户选择 |
| 诊断开关 | `SettingsDiagnosticsService` actor 统一门禁；默认关闭；关闭时删除本地日志 |
| 诊断码 | `SettingsDiagnosticCode`：版本/构建/OS 主版本/开关/条数 + FNV-1a 校验和；`Copy diagnostic code` 写入系统剪贴板 |
| 许可 | `SettingsLicensesView`：应用声明、Apple 系统框架、第三方组件（本构建没有） |
| 版本 | Version / Build / System 三行，来自 `BundleSettingsVersionProvider`，不含设备名 |
| 客服 | 邮箱 `mailto:` 链接 + 复制邮箱；提示附上诊断码；隐私政策 URL 由 WP-28 注入 |
| 删除全部本地数据 | 两段式确认 sheet；删除后成功/失败卡；失败可重试 |
| 订阅说明 | 明确“删除本地数据/删除 App 不取消订阅，订阅由 Apple ID 管理” |
| 无账号 | 没有登录、注册、云同步或购买入口；静态审计测试 |
| 无障碍 | 全部可交互元素 `settings.*` 标识；标题 header trait；Dynamic Type 语义字体；44pt 触控目标；VoiceOver 提示 |

### 文件索引

```text
Sources/StyleToneUI/Settings/
├── SettingsCopy.swift                 110 条 settings.* / error.settings.* 文案
├── SettingsAccessibility.swift        settings.* 无障碍标识与 all 清单
├── SettingsVersion.swift              版本值、Bundle/静态 provider、诊断码安全 token
├── SettingsSupport.swift              客服邮箱、mailto、可选隐私政策 URL
├── SettingsLicenses.swift             许可目录与 provider
├── SettingsDiagnosticsModels.swift    事件白名单、entry、snapshot、协议
├── SettingsDiagnosticCode.swift       诊断码与校验和
├── SettingsDiagnosticsService.swift   UserDefaults 开关、文件/内存日志、门禁、删除
├── SettingsLocalDataDeletion.swift    删除组件、报告、文件系统边界、coordinator
├── SettingsDependencies.swift         依赖容器、live/placeholder、剪贴板
├── SettingsViewModel.swift            加载/开关/复制/两段确认/删除状态机
├── SettingsComponents.swift           卡片、notice、链接行、值行、bullet
├── SettingsDeleteDataSheet.swift      第一次说明 + 第二次最终确认
├── SettingsPrivacyView.swift          隐私详情页
├── SettingsLicensesView.swift         许可详情页
└── SettingsScreen.swift               设置主屏 + PREVIEWS

Tests/StyleToneUITests/Settings/
├── SettingsTestSupport.swift
├── SettingsCopyTests.swift
├── SettingsAccessibilityTests.swift
├── SettingsVersionTests.swift
├── SettingsDiagnosticsTests.swift
├── SettingsLocalDataDeletionTests.swift
├── SettingsViewModelTests.swift
├── SettingsScreenTests.swift
└── SettingsPrivacyAuditTests.swift
```

---

## 2. 删除语义（验收核心）

`SettingsDataDeletionCoordinator` 按固定顺序执行并**验证**：

1. `StyleProfileStore.deleteAll()`（WP-08：profiles、edits、pair sessions、quota、缩略图、备份、索引）；
2. `loadActive()` 必须返回 `nil`，否则报告 `profileResidue`；
3. `SettingsDiagnosticsDataClearing.deleteDiagnosticData()`：关闭开关、清空日志、清 preference key；
4. `SettingsLocalPreferencesClearing.clearLocalPreferences()`：删除整个 app preference domain，包含
   onboarding/首启标记（WP-22 落地后无需再改这里）；Keychain 购买缓存**不动**，订阅不受影响；
5. 删除 `Application Support/StyleTone` 整棵目录（校准草稿、配对元数据、缓存、备份、诊断文件）；
6. 清空 `Library/Caches` 与临时目录内容（图像/导出缓存、URL cache、导出/渲染临时文件），保留目录本身；
7. 生成 `SettingsLocalDataDeletionReport`。

任何一步失败都会进入 `failures`，`isComplete == false`；UI 只在这种报告为空时才显示
“All local data deleted”。失败后可以重试，重试前不再要求两次确认（意图已确认）。

**重启回引导**：删除清空了 profile store 与全部 app preferences，下一次启动没有可恢复数据；
`SettingsLocalDataDeletionReport.requiresOnboarding` 与 `SettingsViewModel.requiresOnboarding`
提供即时导航信号。宿主应在成功回调里把路由切到 onboarding：

```swift
SettingsScreen(dependencies: dependencies) {
    // 数据与 preferences 已清空；立即回到 onboarding。
    // 即使这次不切换，下次冷启动也会因为空 store 进入 onboarding。
    appRouteState = .onboarding
}
```

> 真实接线时，`SettingsDependencies.live(profileStore:)` 返回 `nil` 表示 sandbox 路径无法解析，
> 此时不要提供删除按钮；这是 fail-closed，而不是假装删除成功。

### 二次确认

- 第一次：sheet 列出“会删除 / 会保留”的内容，说明订阅不会取消、相册里已保存的成片会保留；
- 第二次：同一 sheet 的最终步骤，只有 `Delete everything` destructive 按钮才进入 `.deleting`；
- sheet 被下拉/取消只回到 `.idle`，不会开始删除；删除中显示阻塞式 loading overlay。

---

## 3. 诊断与隐私

- **默认关闭**（`settings.diagnostics.optIn` 不存在 = false）。
- 事件是 enum 白名单（启动、设置打开、导出成功/失败、渲染失败、恢复购买等），不是自由文本；
  错误码只接受 `[A-Z][A-Z0-9_]{1,31}`，路径/文件名/邮箱/相册 ID 无法通过校验。
- entry 只含：事件、错误码、时间、app 版本/构建、平台、OS 版本；无设备名、无广告 ID、无照片。
- 日志：`Application Support/StyleTone/Diagnostics/diagnostics.json`，最多 200 条、≤256KB、
  原子写、iOS 完整文件保护；损坏/超大文件忽略，不崩溃。
- **关闭即停止**：`record()` 先检查 actor 内 opt-in；关闭时清空内存与文件。若关闭时文件清理失败，
  返回错误；下次加载发现“关闭但仍有日志”会再次尝试清理。
- 可复制的是**诊断码**，不是日志上传；整个 feature 没有网络 API、账号 SDK 或照片 API。
- 删除本地数据会同时删除诊断文件、诊断 key 和日志；删除成功后不会再写一条“已删除”事件
  （否则等于立刻重建日志）。

---

## 4. 集成

```swift
import StyleToneCore
import StyleToneUI

// App composition root（可以 import WP-08 / WP-20 / WP-22）
guard let dependencies = SettingsDependencies.live(profileStore: profileStore) else {
    // 无法解析 sandbox 路径：不提供删除入口
    return
}

SettingsScreen(dependencies: dependencies) {
    // 成功删除后的即时跳转；也可以等冷启动由空数据决定。
    showOnboarding()
}
```

- `SettingsDependencies.live` 内部共享同一个 diagnostics service 给屏幕和删除 coordinator，
  确保删除时关闭的是屏幕看到的那个开关。
- 客服邮箱默认 `support@styletone.app`（WP-28 占位，需替换）；隐私政策 URL 默认 `nil`，
  WP-28 通过 `SettingsSupportInfo(privacyPolicyURL:)` 注入后会自动出现链接。
- 现有 `App/AppShell/Placeholders/SettingsPlaceholderScreen.swift` 仍是 WP-03 占位；按所有权
  未修改 App。WP-26 替换占位时使用上面的 `SettingsScreen` 即可。

---

## 5. 无障碍与文案

- 根标识 `settings.root`（等于 `AppRoute.settings.accessibilityID`）；复用冻结
  `settings.deleteDataButton`；新增 `settings.privacyButton`、`settings.diagnosticsToggle`、
  `settings.diagnostics.code`、`settings.deleteData.finalButton` 等，全部 `screen.element` 合法。
- 所有可交互元素都有 identifier；复制/清除/删除/重试/开始按钮均有 VoiceOver label 或 hint。
- 文案 110 条全部走 `SettingsText`（`LocalizationKey` + 英文 development fallback），
  没有硬编码中文；`settings.*` / `error.settings.*` 前缀。
- `SectionHeader` 自带 `.isHeader`；说明列表使用 `accessibilityElement(children: .combine)`；
  `SettingsValueRow` 在 accessibility Dynamic Type 下从 HStack 切成 VStack。
- 订阅/删除/隐私文案避免绝对化安全承诺（测试禁止 `100%`、`guaranteed`、`fully secure` 等）。

---

## 6. 测试

```bash
# macOS（CI 同款）
swift test --filter Settings

# 单独测试类
swift test --filter SettingsDiagnosticsTests
swift test --filter SettingsLocalDataDeletionTests
swift test --filter SettingsViewModelTests
swift test --filter SettingsPrivacyAuditTests
```

| 测试文件 | 覆盖 |
|---|---|
| `SettingsCopyTests` | 110 key 合法/唯一/前缀；无中文/占位；隐私、订阅、删除、诊断文案准确性；无账号 CTA；无绝对化承诺 |
| `SettingsAccessibilityTests` | 标识合法/唯一/settings 域；根 = route；冻结 ID 复用；删除/诊断标识层级 |
| `SettingsVersionTests` + `SettingsSupportTests` | 版本显示/token 清洗；Bundle/静态 provider；邮箱校验、mailto、隐私政策 URL |
| `SettingsDiagnosticsTests` | 默认关闭；关闭不收集；开启持久化；关闭清日志；失败回滚；孤儿清理；环形上限；文件 roundtrip/损坏/超大/清理；诊断码格式/确定性/无路径 |
| `SettingsLocalDataDeletionTests` | 完整删除 + 文件/preferences/diagnostics/profile 验证；重启空状态；幂等；profile/diagnostics/preferences/文件失败；residue；报告语义 |
| `SettingsViewModelTests` | 加载、诊断开关、复制、两段确认/取消/返回、删除成功/失败/重试、删除后 onboarding 信号 |
| `SettingsScreenTests` | placeholder 构造、各删除阶段构造、客服邮箱/许可/版本可见状态 |
| `SettingsPrivacyAuditTests` | 静态扫描无网络/账号/照片 API；import 白名单；诊断无自由文本；record 门禁；删除走 WP-08；无中文；交互标识全部接线；无账号入口 |

验收映射：

| 验收 | 证据 |
|---|---|
| 删除彻底 | coordinator 调 WP-08 `deleteAll` + `loadActive` 验证 + prefs domain + App Support/StyleTone + Library/Caches + tmp；`testCompleteDeletionRemovesAndVerifiesEverything` |
| 重启回引导 | 全部 preferences 清除、store 空；`requiresOnboarding`；`testRelaunchAfterDeletionStartsWithNoProfileOrDiagnostics` |
| 无账号入口 | 无账号 UI 代码；`testNoAccountEntryExists`、copy CTA 测试 |
| 关闭诊断后不再收集 | `record` gate + `testDisablingStopsCollectionAndClearsTheLog`、`testRecordWhileOffCollectsNothing` |
| 诊断无 PII | enum + code 校验 + 文件内容测试；`testOnlyBoundedErrorCodesAreAccepted` |
| 可复制诊断码 | `testCopyDiagnosticCodeUsesTheInjectedPasteboard` |
| 订阅不取消说明 | `testSubscriptionCopyExplainsThatDeletionDoesNotCancel` |

---

## 7. 验证状态

- 本会话是 Windows：没有 `swift`、Xcode 或 iOS Simulator，**未在本地执行 `swift test` / `xcodebuild`**。
- 已做静态核对：源码与测试全部 ASCII、单行 ≤120、无重复文案 key/无障碍 ID、无禁用 API/import、
  所有 110 条文案进入 `all`、所有交互标识在视图中接线。
- CI：见下节（推送后更新 run 链接与结果）。

---

## 8. 风险 / 未决

1. **App 未接线**：按所有权没有改 `App/AppShell`；设置页目前是 StyleToneUI 的 `SettingsScreen`，
   App 仍是 WP-03 占位。WP-26 需要替换占位并接入 `onAllDataDeleted` → onboarding。
2. **XCUITest 缺失**：仓库没有 UI test target（WP-24 范围）。当前“UI 测试”是 view-model 驱动、
   视图构造、文案/标识契约与静态隐私审计；真实点击/截图待 UI test target。
3. **客服地址/隐私政策是占位**：`support@styletone.app` 与 `privacyPolicyURL = nil` 等 WP-28；
   在正式素材落地前不要提审。
4. **清除整个 preference domain**：这是“删除后回引导”的必要条件，但会同时清掉未来新增的
   非数据型偏好。若后续有“应跨删除保留”的开关，需要显式白名单并更新本 WP 的删除测试。
5. **Keychain / 订阅**：不清理 Keychain 购买权益缓存，也不取消订阅；这是产品语义，UI 已说明。
   WP-20 若改变权益缓存位置，需要确认删除后仍能恢复购买。
6. **SwiftData 容器句柄**：coordinator 依赖 WP-08 `deleteAll()` 释放容器后再删 App Support 目录；
   若容器仍持有句柄导致删除失败，会报告 `.fileDeletionFailed` 并支持重试，不会假装成功。
7. **诊断写盘是 best-effort**：写失败不阻塞用户操作，内存中仍有 entry，重启后可能丢失；删除路径
   不依赖 best-effort 写入，而是直接删除日志/目录。
8. **缓存/临时目录全清**：会删除 `Library/Caches` 与 `tmp` 下所有内容（包括正在进行的导出临时文件）；
   只允许在用户确认“删除全部本地数据”后调用。WP-19 导出实现应把临时文件放在 tmp 下并容忍该操作。
9. **文件保护**：诊断文件在 iOS 使用 `.complete`；目录本身未单独设保护类，建议 App target
   同时开 `NSFileProtectionComplete` 默认数据保护（与 WP-08 risk 相同）。
10. **UI 文案**：当前为英文 development fallback；zh-Hans 字符串目录由 WP-26 落地。隐私/订阅
    措辞需要 WP-28 法务复核后再提审。
