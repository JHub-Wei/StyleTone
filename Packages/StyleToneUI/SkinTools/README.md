# WP-16 · 皮肤工具 UI + 点选去瑕疵

- 状态：**review**（代码与测试完成；Windows 会话无 Swift/Xcode，CI 待 macOS runner）
- 依赖：WP-03（DesignSystem/无障碍/路由）、WP-07（`RetouchRendering` / `BlemishRemoving`）
- 解锁：WP-17 编辑器集成
- 范围：`Packages/StyleToneUI/Sources/StyleToneUI/SkinTools/` + `Packages/StyleToneUI/Tests/StyleToneUITests/SkinTools/`
- 文档：本目录（任务卡中的 WP 目录）

> 任务卡写的所有权目录是 `Packages/StyleToneUI/SkinTools/`，但 SwiftPM target 的源码路径是
> `Packages/StyleToneUI/Sources/StyleToneUI`。因此实现放在 `Sources/StyleToneUI/SkinTools/`，
> 测试放在 `Tests/StyleToneUITests/SkinTools/`，任务卡目录只放本文档。未修改
> `Retouch`、`Editor`、`DesignSystem` 或任何共享文件。

---

## 1. 交付内容

| 能力 | 实现 |
|---|---|
| 磨皮滑杆 | `SkinToolsPanel` + `SliderRow`；标识复用冻结的 `editor.smoothingSlider` |
| 匀肤滑杆 | 新增 `editor.evennessSlider`，范围 0...1，步进 0.01 |
| 强度 0 回原图 | `SkinToolsViewModel` 对 `smoothing == 0 && evenness == 0 && blemishes.isEmpty` 的任务完全不调用引擎，直接把 `displayedImage` 指回 `sourceImage`；测试断言 `CGImage` 同一性 |
| 点选修复 | 进入 blemish 模式 → 画布点选 → 归一化坐标 → `BlemishRemoving.removeBlemish` |
| 放大 | 双指捏合 + 工具栏 1×/2×…/6×；`SkinToolsImageGeometry` 负责 aspect-fit、缩放、平移与点击映射 |
| 半径 | 0.005...0.08（契约 `BlemishPoint.radius` 范围），默认 0.018，滑杆步进 0.001 |
| 撤销 | 仅保留点/半径，不保存整图快照；撤销时从当前磨皮底图重放剩余点，事务提交 |
| 错误态 | 失败保留最后有效图与已提交标记；显示错误文案 + 诊断码 + “Try again”；重试同一任务快照 |
| 取消 | 进行中显示进度 + Cancel；取消立即保留上一张图，并以 token 阻止迟到结果写回 |
| 无脸 / 分析不匹配 | 控件整体移除并显示说明卡；`unavailableBehavior: .hide` 时整个 panel 隐藏 |
| 无障碍 | 所有可交互元素 `editor.*` 标识；画布支持 VoiceOver 自定义动作“中心点修复 / 撤销” |
| UI 测试 | SwiftPM 测试目标内的 view-model 驱动脚本 + 视图构造 + 标识契约（无 XCUITest target） |

---

## 2. 交互流程

```text
选择照片（WP-17）
  → 分析（WP-05）→ PortraitAnalysis
  → SkinToolsPanel
       ├─ Smoothing / Evenness 滑杆
       │     └─ 120ms 合并 → RetouchRendering.retouch
       ├─ “Remove a blemish”
       │     ├─ 画布：aspect-fit / 1–6× / 拖拽平移
       │     ├─ 点按 → NormalizedPoint → BlemishRemoving.removeBlemish
       │     ├─ 半径滑杆（0.005…0.08）
       │     └─ Undo mark / Clear marks
       └─ Reset → 原图 + 所有皮肤参数归零
```

### 渲染顺序

与 contracts §5 / WP-07 README 一致：

```text
source
  → retouch(smoothing, evenness)          （仅当非零）
  → removeBlemish(point 1)
  → removeBlemish(point 2)
  → …
  → displayedImage
```

- 每次滑杆变化都会用当前完整点列表重新合成；因此磨皮底图变化后，已有标记仍落在正确像素上。
- 每次新增/撤销标记也都是“从源图重新合成到目标点列表”，再一次性提交。
- `displayedImage`、`blemishes`、`failure` 只在整条链路成功后一起更新；任一环节失败都不产生半成品。

### 强度 0 的语义

- 磨皮/匀肤均为 0 且没有标记 → `displayedImage.cgImage === sourceImage.cgImage`，且不调用
  `RetouchRendering`。
- 有点选标记时，滑杆为 0 仍会重放标记（点选是独立编辑），但不会调用磨皮引擎。
- 撤销最后一个标记且滑杆为 0 → 直接回到原图，不调用任何引擎。

---

## 3. 状态机（`SkinToolsViewModel`）

| 事件 | 结果 |
|---|---|
| `setSmoothing` / `setEvenness` | 钳制到 0...1；相同值不重渲染；否则取消旧任务、合并 120ms、从源图合成 |
| `beginBlemishMode` / `endBlemishMode` | 仅切换 UI 模式，不影响已渲染结果；无脸时拒绝 |
| `setRadius` | 钳制到 0.005...0.08；NaN → 默认 0.018 |
| `addBlemish(at:)` | 需有脸、非渲染中、未达 24 个上限；新点与当前参数组成目标快照；成功后提交 |
| `undoBlemish` | 目标为 `dropLast()`；成功后提交；失败保留全部标记 |
| `clearBlemishes` | 目标为空；与 undo 相同的事务语义 |
| `retry` | 重新执行失败时的 `RenderJob` 快照（参数 + 目标点列表） |
| `cancelRendering` | token 失效、任务取消、`isRendering = false`、显示取消 notice；旧图不变 |
| `reset` | 取消任务、清空滑杆/标记/错误、回到原图、重置半径/缩放 |
| `replaceSource(image:analysis:)` | 取消任务并重置皮肤区，供 WP-17 换图使用 |
| `zoomIn` / `zoomOut` / `resetZoom` | 1...6×，步进 1×；不影响像素结果 |

失败不会修改 `sourceImage`（`ImageAsset` 本身不可变），也不会替换 `displayedImage`。

---

## 4. WP-17 集成

`StyleToneUI` 不 import `StyleToneRetouch`；宿主在 App target 注入协议实现：

```swift
import StyleToneImaging
import StyleToneRetouch
import StyleToneUI

let skin = SkinToolsViewModel(
    image: previewImage,          // WP-17 的代理图（建议 ≤1600px）
    analysis: analysis,           // WP-05，尺寸必须与 previewImage 一致
    engine: SkinRetoucher(),      // WP-07；同时满足 RetouchRendering + BlemishRemoving
    configuration: .standard      // renderDelay = 120ms
)

SkinToolsPanel(
    model: skin,
    unavailableBehavior: .disable,
    onDisplayedImageChange: { image in
        editor.setSkinPreview(image)   // 只接收成功结果
    }
)
```

- **预览取值**：`skin.displayedImage` 是最后成功结果；`renderRevision` 每次成功/重置/换图递增，
  可用 `.onChange` 触发编辑器刷新。
- **导出/高质量**：代理图上的结果不能直接用于导出。WP-17 应将 `skin.skinParameters` 与
  `skin.blemishPoints` 写入 `RenderRequest` / `ManualAdjustments`，由全分辨率管线重放；
  也可以调用 `skin.applySkinFields(to: &adjustments)` 只覆盖皮肤字段，保留影调/形变字段。
  不要在与 `ImageRendering` 同一条链路里再调用一次 `RetouchRendering`，避免双重磨皮。
- **换图**：调用 `replaceSource(_:analysis:)`，皮肤区自动归零。
- **无脸**：`model.isFaceAvailable == false` 时控件不可用；WP-17 也可用 `.hide` 让整个皮肤区消失。
- **撤销**：本组件的 undo 只针对点选标记；编辑器 20 步全局撤销仍由 WP-17 维护。

---

## 5. 无障碍 / 文案

- 冻结标识复用：`editor.smoothingSlider`。
- 新增标识（`SkinToolsAccessibilityID`）：
  - 容器：`editor.skinTools`、`editor.skinTools.header`、`editor.skinTools.originalBadge`、
    `editor.skinResetButton`、`editor.skinToolsUnavailable`、`editor.skinToolsMaskWarning`
  - 滑杆：`editor.evennessSlider`、`editor.blemishRadiusSlider`
  - 点选：`editor.blemishButton`、`editor.blemishDoneButton`、`editor.blemishCanvas`、
    `editor.blemishCount`、`editor.blemishEmpty`、`editor.blemishUndoButton`、
    `editor.blemishClearButton`
  - 缩放：`editor.blemishZoomInButton`、`editor.blemishZoomOutButton`、
    `editor.blemishZoomResetButton`、`editor.blemishZoomValue`
  - 进度/错误：`editor.skinToolsProgress`、`editor.skinToolsCancelButton`、
    `editor.skinToolsError`、`editor.skinToolsErrorCode`、`editor.skinToolsRetryButton`、
    `editor.skinToolsErrorDismissButton`、`editor.skinToolsNotice`、
    `editor.skinToolsNoticeDismissButton`
- 画布是一个整体无障碍元素，value 报告“标记数 + 缩放倍数”；VoiceOver 动作：
  “Repair a spot at the centre”“Undo the last mark”。
- 文案全部走 `SkinToolsCopy`（`LocalizationKey` + 英文 fallback），键在 `editor.skin.*`；
  无硬编码中文（测试扫描 CJK 区段）。
- 无脸状态不是错误：显示 `editor.skinToolsUnavailable` 说明卡，而不是弹窗/红条。

---

## 6. 测试

```bash
# macOS（CI 同款）
swift test --filter SkinTools
```

| 文件 | 覆盖 |
|---|---|
| `SkinToolsViewModelTests` | 强度 0 同一性、只磨皮/只匀肤、钳制、无脸、分析尺寸不匹配、缺/错尺寸 skinMask、点选成功/撤销、失败保图、undo 失败、滑杆变化重放、重置、取消、换图、上限、WP-17 参数映射、点/半径安全 |
| `SkinToolsImageGeometryTests` | aspect-fit 信箱、边界/外部点击、1×/2× 映射、缩放下限、标记直径、平移钳制、非法尺寸、pan 偏移 |
| `SkinToolsCopyTests` | 键前缀/合法性、fallback 完整、错误/notice 映射、格式化、无 CJK、标识合法/唯一/editor 域、冻结标识复用 |
| `SkinToolsPanelTests` | panel 构造、无脸 disable/hide、完整点选 UI 脚本、验收常量、配置消毒、缩放范围 |

验收映射：

| 验收 | 证据 |
|---|---|
| 强度 0 回原图 | `testStrengthZeroReturnsTheSourceWithoutCallingTheEngine`：引擎调用次数保持 1，第二次归零后 `displayedImage.cgImage === sourceImage.cgImage` |
| 点选可撤销 | `testBlemishTapAppliesAndUndoRestoresOriginalWithoutRerendering`、`testUndoFailureKeepsMarksAndRetryCanRemoveOne`、`testFullBlemishRepairUIScript` |
| 失败不破坏原图 | `testBlemishFailureKeepsImageAndHistoryThenRetryCommits`、`testUndoFailureKeepsMarksAndRetryCanRemoveOne`：`sourceImage` 始终同一 `CGImage`，失败后 `displayedImage` 保持上一张 |
| 无脸隐藏/禁用 | `testNoFaceDisablesAndIgnoresEveryAction`、`testNoFacePanelIsDisabledOrHidden` |
| 与 WP-17 状态兼容 | `skinParameters` / `blemishPoints` / `manualAdjustments` / `renderRevision` / `replaceSource` + `testBlemishLimitNoticeAndEditorParameterMapping` |

> 仓库没有 XCUITest target（WP-24 范围）。本 WP 的“UI 测试”是 view-model 驱动的完整交互脚本、
> 视图构造、几何映射和标识契约；真机点按/缩放测试待 UI test target。

---

## 7. 风险 / 未决

1. **CI 未跑**：本会话是 Windows，没有 `swift`/`xcodebuild`。语法已用 tree-sitter 校验，但类型检查、
   Swift 6 并发检查和 SwiftUI 手势 API 需要在 macOS runner 上确认。重点：`MagnifyGesture`、
   `onTapGesture(count:coordinateSpace:)`、`accessibilityAction` 的 actor 隔离。
2. **无 XCUITest**：点选/捏合的真实触摸路径没有在模拟器上跑过；几何映射已有纯函数测试。
3. **重放成本**：滑杆变化会重放全部标记（最多 24 个），每个点是一次引擎调用。预览代理图下可接受；
   全分辨率导出由 WP-17 一次性管线处理。若真机拖动卡顿，建议 WP-17 在拖动期间只更新滑杆，
   松手后再合成标记。
4. **撤销语义依赖确定性**：不保存整图快照，撤销/重做通过“源图 + 参数 + 剩余点”重放。WP-07 的
   patch 搜索是确定性的；若未来引擎引入随机性，撤销结果可能不同，需要改为快照或缓存。
5. **半径上限**：0.08 短边在大图上可能覆盖眼睛/五官附近。UI 默认 0.018 偏小，但没有自动五官保护；
   引擎只保证“盘外不改”，盘内会替换。建议 WP-17/QA 在真实人像上复核默认值与提示。
6. **多脸**：只要 `analysis.faces` 非空就启用；实际皮肤蒙版范围由 WP-05 决定。若产品要求只处理
   主脸，需要 WP-05 或 WP-17 在传入前裁剪分析。
7. **取消后的滑杆值**：取消只停止渲染并保留旧图，滑杆仍显示新值；再次调整即触发新合成。这是
   “取消不写半成品”的取舍，文案已说明。
8. **代理图分辨率**：`radius` 是归一化短边比例，与分辨率无关；但预览代理与导出的像素级修复结果
   可能略有差异，导出必须以全分辨率重放。
9. **字符串目录**：`editor.skin.*` 与 `editor.skin.zoom.*` 需要 WP-26 在 `Localizable.xcstrings`
   中补齐 zh-Hans；当前英文 fallback 仅开发用。
10. **未改 DesignSystem**：新增标识/键都在 SkinTools 本地枚举中，没有扩展冻结的
    `AccessibilityID.all` / `L10n.allKeys`；若 WP-26 希望集中登记，需要后续 CCR。
11. **WP-17 集成时移除占位 skin 区**：本 panel 复用冻结的 `editor.smoothingSlider`。若编辑器仍保留
    `EditorPlaceholderScreen` 里的同名滑杆，会出现重复标识；接入时应整段替换。

---

## 8. 文件索引

```text
Packages/StyleToneUI/Sources/StyleToneUI/SkinTools/
├── SkinToolsModels.swift           常量、配置、BlemishEdit、失败/notice/可用性
├── SkinToolsCopy.swift             editor.skin.* 文案与 fallback
├── SkinToolsAccessibility.swift    本地无障碍标识
├── SkinToolsImageGeometry.swift    aspect-fit/缩放/平移/点击映射
├── SkinToolsViewModel.swift        渲染、事务、撤销、取消、错误重试
├── SkinToolsBlemishCanvas.swift    画布、标记、捏合/拖拽/点选、VoiceOver 动作
├── SkinToolsPanel.swift            滑杆/点选区/缩放/进度/错误/notice/无脸态
└── SkinToolsPreviews.swift         DEBUG 预览（合成图，无真实照片）

Packages/StyleToneUI/Tests/StyleToneUITests/SkinTools/
├── SkinToolsTestSupport.swift      图像/分析 fixture、retouch/blemish spy、取消闸门
├── SkinToolsViewModelTests.swift   16 个行为测试
├── SkinToolsImageGeometryTests.swift 8 个几何测试
├── SkinToolsCopyTests.swift        9 个文案/标识测试
└── SkinToolsPanelTests.swift       7 个 panel/UI 脚本测试

Packages/StyleToneUI/SkinTools/
└── README.md                       本文档
```
