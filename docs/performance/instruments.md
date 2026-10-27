# Instruments / 真机测量手册

> 目标：在 iPhone 13（参考）与 iPhone SE 3（低端）上，用同一套场景采集首帧、
> 形变 fps、学习、导出、内存、热，并把结果写入
> `Tests/Performance/Baselines/performance-baselines.json`。
>
> 当前仓库没有真机 trace；本文件是**可执行手册**，不是伪造的结果。

## 1. 签名点（Points of Interest）

`PerformanceKit` 定义：

- subsystem：`com.styletone.performance`
- category：`performance`
- 事件：`first-frame`、`preview-frame`、`slider-response`、`analysis`、
  `learning`、`export`、`memory`、`cancellation`、`proxy-scale`

集成测试已经用 `PerformanceSignposter` 包裹关键区间；生产 App 的合成根在接入时
应复用同名事件（WP-17 owner 的 patch）。

Instruments 查看：**Points of Interest** track；筛选 subsystem。

## 2. 冷启动 / 首帧

### 2.1 XCTest（推荐，可自动化）

新增一个 UI test target（WP-00/WP-03 owner；当前 App 还未接通照片导入，
WP-24 不越权提供 project.yml 补丁），用：

```swift
func testColdLaunch() {
    measure(metrics: [XCTApplicationLaunchMetric()]) {
        XCUIApplication().launch()
    }
}
```

- 跑 5 次；取 p95；目标 ≤2 s。
- 首帧用 App 内 `first-frame` signpost：`applicationDidFinishLaunching` → 首张
  `displayedImage` 赋值。
- 关闭“启动时预加载风格/分析”的测试开关，避免污染。

### 2.2 xctrace

```bash
# 先确认设备与 App 已安装
xcrun devicectl list devices
xcrun xctrace list devices

# 方案 A：Instruments 里 File > Record，选 App Launch + Points of Interest
# 方案 B：命令行（参数随 Xcode 版本变化，先看 xctrace help record）
xcrun xctrace record \
  --template 'App Launch' \
  --device <UDID> \
  --time-limit 30s \
  --output .perf-traces/launch-$(date +%s).trace
```

> iOS App 的 `--launch` 可能需要可执行路径；若失败，用 `devicectl` 启动 App，
> 再 `xctrace record --attach StyleTone`。以本机 `xctrace help record` 为准。

## 3. 形变预览 fps

1. 打开 12MP 人像，进入编辑器。
2. Instruments：**Metal System Trace** + **Time Profiler** + **Points of Interest**。
3. 连续拖动脸型滑杆 20 s（脚本可用 XCUITest 的 `press(forDuration:thenDragTo:)`）。
4. 读取 `preview-frame` 区间的 p95 帧时间；fps = 1 / p95。
5. 目标 ≥30 fps；记录 GPU 利用率、是否降频、代理档位。

```bash
xcrun xctrace record \
  --template 'Metal System Trace' \
  --device <UDID> \
  --time-limit 40s \
  --output .perf-traces/warp-$(date +%s).trace
```

同时跑门禁：

```bash
ST_PERF_REFERENCE=1 ST_PERF_STRICT=1 \
  swift test --filter WarpFramePerformanceTests
```

## 4. 5 组学习

- 学习无 GPU；用 Time Profiler。
- 在 App 内连续完成 3 次 5 组学习，取 p95；目标 ≤90 s。
- 检查峰值内存（Allocations）与主线程卡顿（Hang）。

## 5. 12MP 导出

1. 真实编辑（脸/身/皮肤/影调）后导出 HEIC 与 JPEG 各 3 次。
2. **Time Profiler** + **Allocations** + **Points of Interest**（`export`）。
3. 记录 p95、峰值 `phys_footprint`、临时文件清理。
4. 目标 p95 ≤6 s、内存 ≤500 MB、无 Jetsam。

## 6. 内存 / Jetsam

### 6.1 进程峰值

```bash
ST_PERF_REFERENCE=1 swift test --filter MemoryPerformanceTests
# 或真机 App + Instruments Allocations，记录 phys_footprint
```

- 预览：打开 12MP → 拖动 60 s → 峰值 ≤300 MB。
- 导出：12MP 导出 3 次 → 峰值 ≤500 MB。
- `MemoryFootprint` 使用 `task_vm_info.phys_footprint`，与 Jetsam 记账一致；
  不用 `resident_size`。

### 6.2 Jetsam

```bash
# 设备日志（保留最近 10 分钟）
xcrun devicectl device info ...
log collect --device --last 10m --output .perf-logs/jetsam.logarchive
log show .perf-logs/jetsam.logarchive --predicate 'eventMessage CONTAINS "jetsam"' --last 10m
```

- 失败条件：任一 `jetsam`/`memorystatus` kill、App 被系统终止、`phys_footprint`
  超过 300/500 MB 并收到 pressure warning。
- 记录设备型号、iOS 版本、热状态、后台 App 数量。

## 7. 热 soak（10 分钟）

1. 满电、关闭低电模式、亮度 50%、飞行模式（减少干扰）。
2. 循环拖动滑杆 + 每 60 s 导出一次（可选），持续 10 min。
3. 每 5 s 记录 `ProcessInfo.thermalState`、`preview-frame` p95、当前代理档位。
4. 通过标准：
   - 不进入 `critical` 持续 >60 s；
   - 不出现 Jetsam；
   - 后 3 min 的 p95 帧时间 ≤ 1/24 s（严重降频阈值），且 UI 仍可拖动；
   - 目标仍是后 3 min ≥30 fps；低端机按 degradation.md 的低端目标。
5. 采样脚本：`Tests/Performance/Tools/thermal_soak.sh`（App 内需暴露
   `performanceLevel` 诊断；或读 signpost）。

## 8. 采集清单

每次签核上传：

- `.xcresult`（包含 performance-Markdown attachment）；
- `.perf-reports/*.json`；
- `.perf-traces/*.trace`（或 Instruments 导出的 `.trace`）；
- `jetsam.logarchive`；
- 设备信息：型号、iOS、build、电量、环境温度。

命名：`<scenario>-<device>-<os>-<commit>-<date>.<ext>`。

## 9. 注意事项

- 不要在低电量/过热/后台更新时采基线；记录环境。
- 每次只改一个变量（构建配置、设备、代理档）。
- Debug 与 Release 基线分开；CI debug 不能作为发布基线。
- Instruments 的 “Average” 不是 p95；用 Points of Interest 的区间耗时或导出
  signpost interval 统计。
