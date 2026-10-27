# 给模块 owner 的优化 PR 清单

> WP-24 不直接改算法/页面。以下补丁放在 [`patches/`](patches/)，每个都附：
> 问题、期望收益、验证命令、风险、回滚。合入前请 owner 重新测量并更新基线。

## PR-1 · WP-17：预览 mask 缩放并行化

- **文件**：`Packages/StyleToneUI/Sources/StyleToneUI/Editor/EditorPreview.swift`
- **补丁**：[`patches/wp-17-preview-mask-scaling.patch`](patches/wp-17-preview-mask-scaling.patch)
- **问题**：3 个 mask × 1280×960 纯 Swift 双重循环，计入滑杆响应/首帧。
- **改动**：用 `vImageScale_Planar8`（Accelerate）缩放 mask，保留边界/尺寸语义；
  无加速时回退现有循环。
- **收益**：预览 mask 缩放预计 -50–70%；滑杆响应更稳。
- **验证**：
  ```bash
  swift test --filter EditorPreviewTests
  swift test --filter PreviewCachePerformanceTests
  swift test --filter SliderResponsePerformanceTests
  ```
- **风险**：采样点差半个像素，仅预览；导出不受影响。需要 WP-25 预览/导出黄金图
  复核。
- **回滚**：单文件回退。

## PR-2 · WP-06：Metal 每帧资源缓存

- **文件**：`Packages/StyleToneGeometry/Sources/StyleToneGeometry/Core/MetalGeometryWarp.swift`
- **补丁**：[`patches/wp-06-metal-frame-resource-cache.patch`](patches/wp-06-metal-frame-resource-cache.patch)
- **问题**：每帧上传 1080p 源纹理、分配 output/index/offset/vertex buffer。
- **改动**：按 `CGImage` 身份缓存源纹理；按尺寸缓存 output texture 与 index
  buffer；offset/vertex buffer 按 grid 复用；预览 `renderTexture` 仍不读回。
- **收益**：WP-06 预览 p95 25.3 ms 中预计 -10–20%；减少内存抖动。
- **验证**：
  ```bash
  swift test --filter MetalGeometryWarpTests
  swift test --filter WarpFramePerformanceTests
  ST_PERF_STRICT=1 swift test --filter WarpFramePerformanceTests
  ```
- **风险**：缓存失效必须基于图像身份；纹理池在引擎 actor 内串行；并发调用
  `renderTexture` 的线程安全需 owner 复核。
- **回滚**：单文件回退；不涉及 Core 契约。

## PR-3 · WP-17/WP-23：热 / 低电 / 低端机预览降级与提示

- **文件**：新增 `Packages/StyleToneUI/Sources/StyleToneUI/Editor/EditorThermalPolicy.swift`；
  修改 `EditorViewModel.swift` 与 `EditorPerformanceGovernor.swift`；提示 UI 由 owner
  使用 `model.performanceNoticeKey` 接入，`Localizable.xcstrings` 由 WP-26 添加。
- **补丁**：[`patches/wp-17-thermal-degradation.patch`](patches/wp-17-thermal-degradation.patch)
- **问题**：`EditorPerformanceGovernor` 只看 preview 时长；thermal/lowPower/
  deviceClass 未接入，serious/critical 时仍按 1280 代理跑。
- **改动**：移植 `ThermalPerformancePolicy`；监听
  `ProcessInfo.thermalStateDidChangeNotification` 与
  `NSProcessInfoPowerStateDidChange`；取 max 档；提示 key（degradation.md）。
- **收益**：稳定性/热；不承诺提升峰值 fps。
- **验证**：
  ```bash
  swift test --filter ThermalPolicyPerformanceTests
  swift test --filter EditorViewModelTests
  # 真机 10 min soak
  ```
- **风险**：通知回调线程、UI 文案/无障碍、不能阻断导出；低端机初始档位要产品确认。
- **回滚**：移除新文件与三处调用即可。

## PR-4 · WP-02/WP-19：导出流式写文件

- **文件**：`Packages/StyleToneImaging/Sources/StyleToneImaging/ImageWriter.swift`
- **补丁**：[`patches/wp-02-streaming-export.patch`](patches/wp-02-streaming-export.patch)
- **问题**：`ImageWriter.data` 先编码到内存 `Data`，再原子写，多一份编码结果。
- **改动**：`CGImageDestinationCreateWithURL` 写临时文件 → rename；失败清理；
  保留 `ImageWriter.data` API。
- **收益**：省 3–8 MB 峰值与一次拷贝；对 12MP Jetsam 是边际改善。
- **验证**：
  ```bash
  swift test --filter ExportPerformanceTests
  swift test --filter ExportTests
  ```
- **风险**：原子性/失败清理；HEIC 支持的设备差异。
- **回滚**：单文件回退。

## PR-5 · 集成：编辑器使用 2048 工作图

- **文件**：App 合成根（WP-17/App）+ `EditorViewModel.load` 调用方。
- **补丁**：无代码补丁（当前 App 尚未接照片导入）；方案见
  [`findings.md`](findings.md) §3。
- **问题**：先解码 12MP、再分析、再缩 1280；首帧/内存双倍工作。
- **改动**：编辑会话解码 `.preview` 2048；分析、预览、滑杆用同一工作图；导出再
  解码全分辨率。
- **收益**：首帧预计 -40–60%，峰值内存约 -80 MB。
- **验证**：`FirstFramePerformanceTests`、`MemoryPerformanceTests`、WP-17 导出
  一致性、WP-25 黄金图。
- **风险**：预览/导出一致性；mask 尺寸必须与工作图一致。

## PR-6 · 集成：Package.swift + CI 报告

- **文件**：`Package.swift`、`.github/workflows/ios.yml`
- **补丁**：[`integration/Package.swift.patch`](integration/Package.swift.patch)、
  [`integration/ios.yml.patch`](integration/ios.yml.patch)
- **问题**：WP-24 不能改根清单/CI；当前测试目标尚未进入 `swift test`。
- **改动**：新增 `PerformanceKit` target 与 `StyleTonePerformanceTests` test target；
  CI 上传 performance reports。
- **验证**：`swift test` 全绿；artifact 存在。
- **风险**：CI 时间增加约 30–60 s；共享 runner 抖动由噪声地板/基线控制。
- **状态**：**待 WP-00 owner 合入**；合入后 WP-24 门禁才在 PR 上自动阻断。

## 合入顺序

1. PR-6（清单/CI）→ 门禁能跑；
2. PR-1/PR-2（低风险、可独立测量）；
3. PR-3（热/低电，需产品确认文案）；
4. PR-5（首帧工作图，跨模块）；
5. PR-4（导出内存，边际）。

每个 PR 合入后：

```bash
ST_PERF_REPORT_DIR=.perf-reports swift test --filter StyleTonePerformanceTests
python3 Tests/Performance/Tools/record_baseline.py --environment <env> --reports .perf-reports
```

基线变化必须与 PR 一起 review；如果优化让基线变快，更新基线并保留旧值对比。
