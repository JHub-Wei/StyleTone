# WP-24 性能热点与优化项

> 证据来源：本仓库已有模块基线（WP-02/05/06/07/11/17/19 的 README/PERFORMANCE）
> + 代码审查 + WP-24 场景设计。**没有**编造真机 profiler 数字；每条优化都给出
> 期望收益、验证方法和风险。

## 1. 形变预览：每帧重新分配纹理（WP-06）

**位置**：`Packages/StyleToneGeometry/Sources/StyleToneGeometry/Core/MetalGeometryWarp.swift`
`renderTexture` / `warp`。

**观察**：每帧都：
- `makeSourceTexture(from:)` 上传整张源图（1080p = 8.3 MB）；
- `makeOutputTexture` 分配 8.3 MB render target；
- `makeOffsetBuffer`、index buffer、vertex buffer 重新分配；
- 预览 `GeometryRenderingEngine.warp` 还走 `makeImage` 做 CPU 回读（交互路径若
  通过 `GeometryRendering` 协议，必然回读）。

**已有基线**：WP-06 CI，1080p 预览 p95 **25.3 ms / 39.6 fps**，其中包含
“per-frame source texture upload and allocation”。30 fps 预算 33.3 ms，余量
约 24%。WP-24 的 20 样本场景在 debug CI 上 p50 **28.9 ms**、p95 51.5 ms
（两个调度尾延迟）；p50 与 WP-06 同量级，尾延迟不作为设备结论。

**优化**（[`patches/wp-06-metal-frame-resource-cache.patch`](patches/wp-06-metal-frame-resource-cache.patch)）：
1. 按 `ObjectIdentifier(cgImage)` + 尺寸缓存源纹理；
2. 按尺寸缓存 output texture 与 index buffer；
3. 预分配 vertex/offset buffer（按 grid 尺寸复用）；
4. 可选：为预览提供 texture 直出路径（需要 WP-17 协议扩展，单独立 CCR，不在本补丁）。

**期望**：每帧少一次 8.3 MB 上传与两次大分配；CI 预览 p95 预计降 10–20%
（2.5–5 ms），内存 churn 降低。**风险**：缓存必须按 CGImage 身份失效，避免用户
换图后读到旧纹理；纹理池并发访问要串行（引擎 actor 已串行）。**验证**：
`WarpFramePerformanceTests` + WP-06 像素回归。

## 2. 预览代理 mask 缩放（WP-17）

**位置**：`Packages/StyleToneUI/Sources/StyleToneUI/Editor/EditorPreview.swift`
`CoreGraphicsPreviewScaler.scale(_ mask:to:)`。

**观察**：对 `personMask`、`skinMask`、`backgroundEdgeMask` 各跑一次纯 Swift
双重循环；1280×960 每个 mask ≈1.23M 次迭代，3 个 ≈3.7M 次，且带边界
`min`/乘法。它在 actor 上，不阻塞主线程，但计入滑杆响应/首帧。

**实测（WP-24 CI，2026-10-27，commit `135e721`）**：
`preview.proxyScale` p95 **0.823 s**（2048 图 + 3 个 mask → 1280），
`preview.firstFrame` p95 **1.129 s**，即 proxy 缩放占首帧 **73%**。这是当前
最大的可优化项；`preview.sliderResponse` 0.052 s 因为代理有缓存，未重复缩放。

**优化**（[`patches/wp-17-preview-mask-scaling.patch`](patches/wp-17-preview-mask-scaling.patch)）：
1. 用 Accelerate `vImageScale_Planar8`（当前补丁实现）；
2. 无 Accelerate 时回退原逐像素路径；
3. 加 `needsResize == false` 快速路径（已有）。

**期望**：3 个 mask 的缩放从 O(n) 单线程变 vImage，按 3–8× 估算，1280 档
预计从 0.82 s 降到 0.1–0.25 s；首帧有望降到 0.4–0.6 s。**风险**：vImage 与
手写最近邻的采样点可能差半个像素；只影响预览，不影响导出；需要
`EditorPreviewTests` 的 mask 尺寸/边界断言更新。**验证**：
`PreviewCachePerformanceTests` + 预览画质肉眼/黄金图。

## 3. 首帧：完整 12MP 解码 + 全尺寸 mask（WP-02/05/17 集成）

**观察**：
- `ImageLoader` 支持 `.preview`（2048），但编辑器宿主若先 `.fullResolution` 再
  `VisionPortraitAnalyzer`，会先分配 48 MB 源图，再在内部生成 1024 proxy，
  最后把 mask 重采样回 12MP（3×12 MB），再在首次 preview 时缩到 1280。
- `EditorViewModel.load` 首帧直接把全分辨率 `image` 赋给 `displayedImage`；
  SwiftUI 绘制 12MP 首帧本身也有成本。

**优化**（集成建议，不改算法）：
1. 编辑器会话用 `ImageLoader(options: .preview)` 解码 2048 作为工作图，分析、
   预览、滑杆都基于它；
2. 导出时再解码全分辨率，或复用全分辨率缓存；导出前已有 `cancelAll` 时序；
3. 首帧显示 2048 代理（或 1280 proxy），full 渲染完成后再替换；
4. 这样 12MP 全解码/全尺寸 mask 只在导出路径发生，首帧内存降一个数量级。

**期望**：首帧解码 12MP→2048 通常比全解码快 40–60%，峰值内存省约 80 MB；
预览内存更容易守住 300 MB。**风险**：预览/导出一致性——必须保证导出使用全分辨率
且分析坐标/掩码尺寸一致；现有 `EditorPreviewPreparer` 已处理 mask 重采样，导出
仍走全尺寸。**验证**：`FirstFramePerformanceTests`、`MemoryPerformanceTests`、
WP-17 的导出原图一致性测试。

> 该优化跨 App 合成根与 WP-17，无法在 WP-24 的目录内实现；建议作为集成任务，
> 由 WP-17 owner 在 App 装配层落地。

## 4. 导出编码的内存复制（WP-02/WP-19）

**位置**：`ImageWriter.data` → `Data` → `write(options: .atomic)`；
`FileImageExporter`。

**观察**：12MP HEIC 约 3–8 MB，JPEG 约 2–5 MB；相比 48 MB 像素缓冲不算大，
但 `Data` + 原子写会多一份编码结果副本。导出峰值更多来自渲染缓冲。

**优化**（[`patches/wp-02-streaming-export.patch`](patches/wp-02-streaming-export.patch)）：
- `FileImageExporter` 直接用 `CGImageDestinationCreateWithURL` 写到临时文件，
  避免 `Data` 中间层；失败时删除半成品。
- 仍保留 `ImageWriter.data` 给分享/测试。

**期望**：省 3–8 MB 峰值 + 一次拷贝；对 6 s 预算贡献小，但降低 Jetsam 风险。
**风险**：原子性——先写 `.tmp` 再 rename；失败清理。**验证**：WP-19 导出测试、
`ExportPerformanceTests` 内存。

## 5. 热/低电/低端机没有生产集成（WP-17/23）

**观察**：`EditorPerformanceGovernor` 只根据 preview 时长降代理；没有 thermal /
lowPower / deviceClass 输入；没有提示文案。CI 无法触发 thermalState。

**优化**（[`patches/wp-17-thermal-degradation.patch`](patches/wp-17-thermal-degradation.patch)）：
- 新增 `EditorThermalPolicy`（从 `PerformanceKit.ThermalPerformancePolicy` 移植）；
- `EditorViewModel` 订阅 `ProcessInfo.thermalStateDidChangeNotification` 与
  `NSProcessInfoPowerStateDidChange`，取 max 档；
- `EditorCanvasView` 显示一次性提示；导出前 `showsExportWarning`；
- 诊断页展示当前档位/原因（WP-21 已有诊断框架）。

**期望**：不提升峰值 fps，但避免 serious/critical 下的持续降频、卡顿和 Jetsam；
低端机默认 960 代理更稳。**风险**：通知回调线程、UI 文案/无障碍；只降预览，
不动导出。**验证**：`ThermalPolicyPerformanceTests` + 真机 soak。

## 6. 不需要优化的项

- **学习**：5 组 4.98 s（WP-11 CI）/ 90 s 预算，余量 18×；不投入。
- **背景保护/脸/身/腿 planning**：WP-12/13/14/15 已各自在 33.3 ms 预算内；
  WP-24 只做整体门禁，不重复优化。
- **CPU 形变 fallback**：正确性路径，不进 30 fps 目标；设备无 Metal 时降级/提示。

## 7. 优化优先级

| 优先级 | 项 | 预期收益 | 风险 | Owner |
|---|---|---|---|---|
| P0 | 首帧 2048 工作图（#3） | 首帧/内存最大 | 中（一致性） | WP-17 + App |
| P1 | 预览 mask 缩放（#2） | 滑杆响应 | 低 | WP-17 |
| P1 | 热/低电降级（#5） | 稳定性/热 | 中 | WP-17/23 |
| P2 | Metal 纹理缓存（#1） | 预览 fps 余量 | 中 | WP-06 |
| P3 | 导出流式写（#4） | 内存小幅 | 低 | WP-02/19 |

> 每个补丁都必须在目标设备复测并更新 `baselines/performance-baselines.json`；
> 未合入前，WP-24 不声称收益已实现。
