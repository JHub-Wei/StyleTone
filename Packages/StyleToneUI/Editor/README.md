# WP-17 · 编辑器状态 / 预览 / 撤销

- 状态：**review**（实现与单测完成；iOS 构建/测试需 macOS CI）
- 范围：`Packages/StyleToneUI/Sources/StyleToneUI/Editor/`（SwiftPM target 源码）
- 文档：`Packages/StyleToneUI/Editor/`（任务卡目录）
- 依赖：WP-03 设计系统、WP-06 形变、WP-07 修饰、WP-11 风格（Phase A 用静态 `StyleProfile` / mock）
- 解锁：WP-19 导出、WP-23 边界态、WP-24 性能

> 任务卡写的所有权目录是 `Packages/StyleToneUI/Editor/`，但本仓库 SwiftPM target 的实际路径是
> `Packages/StyleToneUI/Sources/StyleToneUI`。因此源码放在 `Sources/StyleToneUI/Editor/`，
> 任务卡目录放本文档；测试放在 `Tests/StyleToneUITests/Editor/`。没有修改 DesignSystem、Core、
> Pairing、Calibration、Export、SkinTools 或其他算法子目录。

---

## 1. 交付内容

| 能力 | 实现 |
|---|---|
| 管线编排 | `EditorRenderer`（`ImageRendering`）：analysis 输入 → skin retouch → blemish points → geometry warp → tone/colour/finish → `RenderOutput`。顺序与 `contracts.md §5` 一致 |
| 四区工具 | `EditorViewModel` + `EditorView`：脸型 / 身材 / 皮肤 / 影调；每区 ≤5 个滑杆（2/4/3/5） |
| 总强度 | 0–150%，默认 100%；自然档一键 70%；0% 严格回原图（不调用引擎） |
| 预览 | 拖动时用低分辨率代理（含 mask 重采样），松手 `endInteraction()` 触发全分辨率；latest-wins + 取消 |
| 撤销/重做 | `EditorHistory` 默认 30 步（≥20）；一次滑杆拖动合并为 1 步；支持 reset |
| 对比/缩放 | 长按看原图、分屏拖动对比、双指缩放/双击切换/平移；不改变导出 |
| 背景保护 | 默认开；关闭需二次确认；关闭且在形变时产生 `backgroundRisk` warning |
| blemishPoints | `addBlemishPoint` / `removeLast` / `clear`，维护进 `RenderRequest.blemishPoints`；可撤销 |
| 场景 warnings | 分析 warning + render warning + 背景风险；无脸/无身时对应区禁用 |
| 导出 | `export(options:)`：先取消预览、必要时全分辨率渲染，再交给 `ImageExporting`；取消/渲染失败不调用 exporter |
| 性能降级 | `EditorPerformanceGovernor`：两次慢预览降一档（1280 → 960 → 640），三次快预览恢复 |
| 无障碍 | 所有交互元素 `editor.*` 标识；沿用三个冻结滑杆 ID；新增 35 个 ID |
| 单测 | 65 个测试方法，7 个测试文件；mock 引擎，不依赖 Vision/Metal/SwiftData |

---

## 2. 状态机

```text
idle
  └─ load(image) ──► analyzing ──成功──► ready(original) ──┬─ 无操作 / strength=0 ──► ready(original)
                         │                                  ├─ 非中性 style ────────► rendering(full)
                         │                                  └─ 拖动滑杆 ─────────────► rendering(preview)
                         ├─分析失败──► ready(fallback empty analysis) + issue(.retryAnalysis)
                         └─ style 失败 ─► ready(natural default) + issue(.reloadStyle)

rendering(preview) ──完成──► ready(preview) ──endInteraction──► rendering(full)
rendering(*) ──取消/更新──► 丢弃结果，保留上一次成功图像
rendering(*) ──失败──► failed + issue(.retryRender)，保留上一次成功图像
rendering(*) ──成功──► ready(preview|full)
export: preparing → exporting → completed | failed(idle after cancel)
```

关键不变量：

- **只有成功完成的 `RenderOutput` 才会写入 `displayedImage`**；取消、失败、过期结果一律丢弃。
- `renderGeneration` 单调递增；pipeline 只投递最新 generation 的结果，ViewModel 再校验一次。
- 无操作（中性 style + 中性 adjustments + 空 points，或 strength=0）走 no-op 分支，返回**同一个
  `ImageAsset` / 同一个 `CGImage`**，预览与导出都严格等于原图。
- 分析失败时使用空 `PortraitAnalysis`，仍允许影调；脸/身/皮肤工具禁用。

---

## 3. 渲染编排

`EditorRenderer` 不实现任何像素算法，只调用冻结协议：

| 阶段 | 协议 | 触发条件 |
|---|---|---|
| 1. 分析 | 已完成，`PortraitAnalysis` 作为输入 | 总是 |
| 2. 修饰 | `RetouchRendering` | effective `SkinParameters != .neutral` |
| 3. 点修 | `BlemishRemoving`，逐点 | `blemishPoints` 非空且 strength > 0 |
| 4. 形变 | `GeometryRendering` | effective face/body 非中性，且分析到对应结构 |
| 5. 影调 | `EditorToneRendering`（本 WP 新增协议） | tone/finish 非中性 |
| 6. 导出 | `ImageExporting` | 用户触发，且前序渲染成功 |

- 先磨皮匀肤，再逐点修复，避免修复点被磨皮重新软化；随后形变、最后影调。
- 分析中不存在的结构在 `EditorRenderPlan` 里被归零，禁用工具不会把旧滑杆值偷偷送进引擎。
- 背景保护在 Geometry 阶段内完成；关闭且发生形变时追加 `RenderWarning(.backgroundRisk)`。
- `EditorToneRendering` 是新增能力协议（不改 Core 冻结签名）。真实影调引擎由 App composition root
  注入；默认 `PassthroughToneRenderer` 仅用于 mock/独立运行。

### style 与手动滑杆的关系

- 风格提供基线，滑杆是偏移；`strength` 统一缩放：`neutral + (styleOffset + manualOffset) * strength`。
- `ManualAdjustments.legLength` 的 0 表示“未触碰”，与 `BodyParameters.legLength` 的 1.0 基线不同，
  在 plan 内单独归一化。
- 0% strength 时所有参数归零，包括 style 基线和 blemish points。
- 非中性静态 `StyleProfile` 在加载后会触发一次全质量渲染（FR-08 应用风格默认值）；
  中性 natural default 不触发，首屏就是原图。

---

## 4. 预览 / 取消 / 性能

### 4.1 拖动低分辨率，松手高质量

- `beginInteraction()` 记录手势基线；`setAdjustment` 在交互中只提交 preview job，不写 undo。
- `endInteraction()` 提交一次 undo，然后提交 full job（`cancelActive: true`）。
- preview 通过 `EditorPreviewPreparing` 生成代理：
  - 图像按长边缩放；
  - `personMask` / `skinMask` / `backgroundEdgeMask` 最近邻重采样到同一尺寸；
  - 归一化人脸/人体坐标保持不变；
  - `EditorPreviewPreparer` actor 缓存最近一次代理（按图像身份 + 分析尺寸 + 质量档）。
- Full job 始终使用原始全分辨率图像与全尺寸 masks。

### 4.2 取消与不写半成品

`EditorRenderPipeline` 是 MainActor 上的单 worker、latest-wins 队列：

| 事件 | 行为 |
|---|---|
| 拖动中连续更新 | 只保留最新 pending；当前 preview 完成后立即跑最新；过期结果不投递 |
| 松手 / 全质量请求 | 取消正在跑的 preview；取消完成后再跑 full（绝不并发跑两个引擎） |
| 新图 / 离开页面 | `cancelAll()`：清空 pending、取消 active、禁止投递 |
| 渲染器不支持取消 | 结果仍会被 generation 检查丢弃，不会覆盖新图 |
| 渲染失败 | 保留上一次成功图像；`issue` 提供 retry |

- 没有用 `sleep` 做节流：latest-wins + 单 worker 天然合并中间帧；需要等待的测试用
  `waitForRenderIdle()` / continuation。
- `MainActor` 从不做像素处理；引擎是 actor/不可变 struct，preview 缩放也在 actor 上。

### 4.3 性能降级

- `EditorPerformanceGovernor` 只看完成的 preview 时长：
  - ≥280ms 连续 2 次 → 降一档；
  - ≤100ms 连续 3 次 → 升一档；
  - 中间值清零 streak；full 渲染不参与。
- 代理档位：1280 / 960 / 640（长边）。全质量渲染和导出不降级。
- UI 暴露 `performanceLevel` / `isPerformanceDegraded`（顶部 “Reduced preview quality” badge）。

---

## 5. 撤销 / 重做 / 重置

- `EditorHistory` 容量 30（最低 20，最高 100）。
- 滑杆：`beginInteraction` 拿基线 → 多次 `setAdjustment` 不记录 → `endInteraction` 只记录一次基线。
- 离散动作（背景保护、blemish 点、自然档、reset）各记录一步。
- `cancelInteraction` 回滚到手势基线，不产生历史。
- 新编辑清空 redo 分支。
- `reset` 把状态设为 `EditorEditState.original`（strength=0），因此即使有非中性 style，也严格回到原图；
  style 本身不丢弃，提高 strength 可重新应用。reset 本身可撤销。
- 自然档 = strength 0.7（约 70%），可撤销。

---

## 6. 对比 / 缩放 / 无障碍

- 长按：`isShowingOriginal`，不改渲染状态、不影响导出。
- 分屏：左右显示 original / rendered，分隔条可拖动（0.05–0.95），支持 VoiceOver 可调。
- 缩放：1×–4×，双击切换 2×，平移 offset 归一化并钳制；`Fit` 重置。
- 画布 18% 灰；所有按钮/滑杆/开关/分隔条都有 `editor.*` accessibility identifier。
- 冻结 ID 复用：`editor.canvas`、`editor.faceSlimSlider`、`editor.jawSlider`、
  `editor.smoothingSlider`、`editor.addPhotoButton`、`editor.exportButton`、`editor.styleButton`。
- 新增 ID 见 `EditorAccessibility.newIdentifiers`；测试保证合法、唯一、不与冻结 ID 冲突。

---

## 7. 导出

`EditorViewModel.export(options:)`：

1. `guard` 有图、可编辑、无并发 export。
2. `pipeline.cancelAll()` + `waitForIdle()`，避免预览与导出争用。
3. 计算 plan：
   - no-op → 直接使用原图（保证预览/导出一致）；
   - 已有匹配的 full-quality committed image → 复用（避免重复 12MP 渲染）；
   - 否则用当前状态做一次全分辨率 render。
4. 渲染成功后才调用 `ImageExporting`；渲染失败/取消不触碰 exporter。
5. 成功设置 `lastExport` / `completed`；失败映射 `AppError` 并给出 `.retryExport`。
6. 临时文件清理由 WP-19 exporter 负责；Editor 不写盘。

> WP-19 可以继续使用 `EditorView` 的默认导出按钮，或通过 `onExported` 接管跳转；编排与一致性逻辑不变。

---

## 8. 集成

```swift
import StyleToneUI

let dependencies = EditorDependencies(
    analyzer: VisionPortraitAnalyzer(),            // WP-05
    retoucher: RetouchEngine(),                    // WP-07
    blemishRemover: BlemishEngine(),               // WP-07
    geometryRenderer: GeometryPipeline(),          // WP-06/12/13/14/15
    toneRenderer: ToneFinishEngine(),              // 新增；未接入时用 PassthroughToneRenderer
    exporter: FileImageExporter(),                 // WP-02 / WP-19
    styleProvider: StoreEditorStyleProvider(store: profileStore), // WP-08/11
    logger: OSLogAppLogger()
)

EditorView(
    dependencies: dependencies,
    onAddPhoto: { /* PHPicker → model.load(image:) */ },
    onOpenStyle: { /* 风格卡 */ },
    onExported: { result in /* 分享/相册 */ }
)
```

- 宿主先用 `await model.load(image:)` 载入照片；或直接构造 `EditorViewModel` 并调用 `load`。
- `EditorDependencies.placeholder` 中 analyzer/exporter fail-closed，未接引擎时会显示可恢复 issue，
  而不是假装成功。
- `ImageAsset` 不进入网络层；Editor 不 import Vision/Metal/CoreImage/SwiftData。
- 如果宿主已有 `ImageRendering` 实现，可直接以 `renderer:` 注入，跳过默认 `EditorRenderer` 组合。

---

## 9. 测试

| 文件 | 覆盖 |
|---|---|
| `EditorHistoryTests` | 30 步容量、25 步 undo/redo、容量裁剪、redo 清空 |
| `EditorRenderPlanTests` | no-op、strength 缩放、负影调、legLength、无脸/无身归零、points、背景保护、范围钳制 |
| `EditorPreviewTests` | 目标尺寸、图像+mask 重采样、代理缓存 |
| `EditorPerformanceGovernorTests` | 降档/恢复/中性时长/reset |
| `EditorRendererTests` | 无操作原图身份、四阶段顺序、按需跳过、背景风险、取消/失败传播、时长 |
| `EditorViewModelTests` | 首帧原图、导出原图一致、拖 proxy→松 full、最新优先、全质量取消、失败保留、20+ 撤销、自然档/reset、背景确认、points、无脸/无身、缩放/分屏、性能降级 |
| `EditorCopyTests` | 71 个本地化 key + 8 个复用 key、fallback、ID 唯一/合法、每区 ≤5 滑杆、范围 |

本地（Windows）只做 tree-sitter 语法检查与静态 key/ID 校验；`swift test` 需 macOS CI。
当前会话的 CI 结果记录在交付报告中；若未跑完则报告 `CI_PENDING`。

---

## 10. 性能预算

| 指标 | 预算 | 本 WP 的做法 |
|---|---|---|
| 滑杆响应 | ≤100ms | 预览代理 + 单 worker + latest-wins；主线程不做像素 |
| 形变预览 | ≥30fps | 代理长边 1280/960/640；慢则降档 |
| 首帧 | p95 ≤1.5s | 首帧直接显示原图；分析异步，不阻塞显示 |
| 12MP 导出 | p95 ≤6s | 复用已 committed full image；否则单次全质量 render；export 前取消预览 |
| 预览内存 | ≤300MB | 最多一个缓存代理 + 当前显示图；旧 pending 被替换 |

> 真实 12MP 数据需 WP-24 在 macOS/iPhone 上测量；本会话无设备，不声称实测。

---

## 11. 风险与待决

1. **`EditorToneRendering` 是新增协议（CCR 候选）**：Core 没有影调引擎协议。默认 passthrough 会让
   影调滑杆在未注入真实引擎时“可用但无视觉变化”。集成前必须注入 ToneFinishEngine，或在 Wave 3
   决定将其并入 Core。
2. **代理 mask 重采样**：预览使用最近邻缩放的 mask，边缘质量低于全质量；只影响预览，不影响导出。
   若 WP-07/06 引擎假设 mask 与图像尺寸一致，本实现已保证一致。
3. **风格自动应用**：非中性 `StyleProfile` 首屏会触发一次全质量渲染；若产品要求首屏永远是原图，
   宿主应传入 `.editorNaturalDefault`，或后续加 `autoApplyStyle` 开关。
4. **reset 语义**：reset 用 strength=0 回原图（style 不丢弃）。若产品希望 reset 同时丢弃个人风格，
   需要 CCR/产品确认。
5. **导出复用**：只在 `lastFullRenderedEdits == edits` 且 `ready(.full)` 时复用；任何预览/失败都会
   重新全质量渲染，保证一致但可能多一次 12MP 计算。
6. **UI 测试**：本 WP 是 view-model 级单测；XCUITest、真机拖动手感、长按/分屏触控冲突需 WP-24 在
   模拟器/真机验证。
7. **WP-16 点选交互**：Editor 提供 `blemishPoints` 状态与增删清接口；点选放大/落点 UI 属
   `StyleToneUI/SkinTools`，两边通过 `EditorViewModel` 方法对接，不互相 import 子目录。
8. **并发会话**：本实现位于独立 git worktree（`.build/wp17-worktree`，分支 `wp-17-editor`），
   避免与其他 WP 共用工作区导致分支/未跟踪文件串扰；合并前需按正常 PR 流程 rebase。
