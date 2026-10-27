# 性能基线（WP-24）

> 基线不是“目标”，而是“同环境下的可重复观测”。目标在 `contracts.md` §10；
> 回归门禁见 [`regression-gate.md`](regression-gate.md)。

## 1. 环境矩阵

| 环境 id | 用途 | 设备/构建 | 是否门禁 |
|---|---|---|---|
| `ci.macos.arm64` | PR 回归 | GitHub Actions `macos-15`（Apple Silicon 或 x86_64，按 runner 实际） | **是**（>10%） |
| `device.iphone13` | 发布签核 / 参考设备 | iPhone 13 系列（含 13/13 Pro/Pro Max/13 mini），Release | **是**（>10% + 契约） |
| `device.iphone14,6` | 低端降级矩阵 | iPhone SE（第 3 代），Release | 记录 + 契约 |
| `simulator.*` | 冒烟 | iOS Simulator | 否（只报告） |
| `local.macos.*` | 开发者本机 | macOS | 否（只报告） |

> 环境 id 由 `PerformanceTestEnvironment` 生成；`buildConfiguration` 也参与比较。
> Debug 基线与 Release 基线永不互相比较。

## 2. 方法

所有场景使用 `ContinuousClock`，先 warm-up 再记录；报告 p50/p95，门禁用 p95。

| 场景 | 工作 | 迭代 | 说明 |
|---|---|---:|---|
| `preview.firstFrame` | 4032×3024 JPEG → `ImageLoader(.preview)` 2048 长边 → `CoreGraphicsPreviewScaler` 1280 代理 | 5 | 不含 UI 提交；显示赋值在解码后同步发生 |
| `preview.frameTime` | 1080p、32×32 网格、`MetalGeometryWarp.renderTexture`（无 CPU 回读） | 8 | 与 WP-06 的 `MetalGeometryWarpTests` 同一路径 |
| `preview.sliderResponse` | 12MP 源 → 1280 代理 → 真实 Metal 形变 → `EditorViewModel` 投递 | 12 | 端到端，仅分析/修饰/tone 为替身 |
| `learning.fivePairs` | 5 × 160×160 合成人像对，`StyleLearningEngine` | 3 | 无缓存、无 I/O |
| `export.twelveMegapixel` | 4032×3024、64×64 网格、`EditorRenderer` + `FileImageExporter`（JPEG） | 3 | 含编码与临时文件写入/清理 |
| `preview.memoryPeak` | 12MP JPEG → 2048 + 全尺寸 masks → 1280 代理，保持同时存活 | 1 | CI 记录峰值增量；真机记录绝对 `phys_footprint` |
| `export.memoryPeak` | 12MP 渲染 + 编码 | 1 | 同上 |
| `cancellation.latency` | 取消在飞渲染 → `waitForIdle` | 5 | 不得投递过期完成 |
| `preview.proxyCacheHit` | 同图同档连续 11 次 `preparePreview` | 10 | 缩放器只应执行 1 次 |
| `preview.proxyScale` | 2048 + 3 masks → 1280 | 5 | 代理缩放本身成本 |
| `launch.coldStart` | XCUITest / Instruments App Launch | 5 | **尚未在 CI 内实现**；见 instruments.md |

> 12MP 导出的 retouch/tone 使用 passthrough 替身，因为 WP-07 的 12MP 包络另有
> 测试；WP-24 的目标是验证 **渲染组合 + 编码 + 内存** 的整体预算。真实算法接入后
> 必须在参考设备重录基线。

## 3. CI 基线

**记录状态**：2026-10-27，commit `135e721`，CI run
[40528609160](https://github.com/JHub-Wei/StyleTone/actions/runs/40528609160)，
环境 `ci.macos.arm64`（`arm64-apple-macosx15.0`，debug `swift test`，
Apple Paravirtual GPU）。

| 场景 | 样本 | p95 | 契约/说明 |
|---|---:|---:|---|
| `preview.firstFrame` | 5 | **1.129 s** | ≤1.5 s；其中代理缩放占 0.82 s |
| `preview.frameTime` | 8 | **34.9 ms（28.7 fps）** | 30 fps 目标 33.3 ms；debug CI 不强制 |
| `preview.sliderResponse` | 12 | **52.4 ms** | ≤100 ms |
| `learning.fivePairs` | 3 | **2.948 s** | ≤90 s |
| `export.twelveMegapixel` | 3 | **0.379 s** | ≤6 s；retouch/tone 为替身 |
| `preview.memoryPeak` | 1 | **10.78 MB 增量** | 绝对目标 300 MB；增量不代表绝对占用 |
| `export.memoryPeak` | 1 | **50.99 MB 增量** | 绝对目标 500 MB；增量不代表绝对占用 |
| `preview.proxyScale` | 5 | **0.823 s** | 内部场景；2048 + 3 masks → 1280 |
| `preview.proxyCacheHit` | 10 | **0.000001 s** | 缓存命中；缩放器只跑 1 次 |
| `cancellation.latency` | 5 | **0.699 ms** | cancelAll → idle |

解释：

- **首帧接近预算但瓶颈明确**：`preview.proxyScale` 0.823 s 占首帧 73%。
  这是 3 个 mask 的纯 Swift 逐像素缩放；WP-17 mask 缩放补丁是 P0/P1
  优化项（findings #2）。
- **形变帧 34.9 ms** 略高于 30 fps（33.3 ms），与 WP-06 记录的 25.3 ms 同量级
  差异来自本次使用非零合成 field、禁用 identity shortcut，并包含每帧源纹理
  上传；这正是 WP-06 纹理缓存补丁的收益点（findings #1）。
- **内存数字是峰值增量**：CI 进程本身已有 XCTest 基线，不能与设备绝对
  `phys_footprint` 直接比；设备签核必须重录绝对值。
- **导出 0.379 s** 只证明“Metal 形变 + 编码 + 临时文件”组合在本 runner 上远低于
  6 s；不等于 iPhone 13 + 真实 retouch/tone 的完整耗时。

> 在 CI 上，debug 构建不强制契约绝对预算（除学习/导出这两个宽松预算由测试直接
> 断言外），只比较与 CI 基线的相对回归。原因：共享 runner 的绝对性能不是产品
> 不变量（contracts §7.1）。

## 4. 参考设备基线

**状态：待采集（阻塞发布签核）。**

| 场景 | 目标 | iPhone 13 p95 | 低端机（SE 3）p95 | 备注 |
|---|---:|---:|---:|---|
| 冷启动 | ≤2 s | 待测 | 待测 | Instruments App Launch |
| 首帧 | ≤1.5 s | 待测 | 待测 | 12MP HEIC |
| 形变帧 | ≥30 fps | 待测 | 待测 | 1080p / 1280 代理 |
| 滑杆响应 | ≤100 ms | 待测 | 待测 | 端到端 |
| 5 组学习 | ≤90 s | 待测 | 待测 | 160×160 合成 |
| 12MP 导出 | ≤6 s | 待测 | 待测 | HEIC + JPEG |
| 预览内存 | ≤300 MB | 待测 | 待测 | 绝对 \(phys\_footprint\) |
| 导出内存 | ≤500 MB | 待测 | 待测 | 绝对 \(phys\_footprint\) |
| 热 soak 30 fps | ≥30 fps（不严重降频） | 待测 | 待测 | 10 min 连续拖动 |

真机记录流程：

```bash
Tests/Performance/Tools/run_device_performance.sh <DEVICE_UDID>
python3 Tests/Performance/Tools/record_baseline.py \
  --environment device.iphone13 \
  --reports .perf-reports \
  --commit "$(git rev-parse --short HEAD)"
git diff Tests/Performance/Baselines/performance-baselines.json
```

## 5. 已知未覆盖

1. **冷启动**：XCUITest/Instruments 目标尚未接入 CI；当前只有场景定义与运行手册。
2. **真机热 soak**：CI 无法制造 thermalState 迁移；只有策略单测。
3. **12MP 全算法导出**：retouch/tone 为替身；需要 WP-07/影调引擎接入后重录。
4. **Jetsam**：CI 只能看 `phys_footprint`；真机需要 `log collect` 与 Instruments
   Allocations，见 instruments.md。
5. **低端机**：矩阵已定义，设备尚未采集；降级策略见 degradation.md。
