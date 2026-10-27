# 性能 / 内存 / 热（WP-24）

> 本目录由 WP-24 拥有。测试代码在 [`Tests/Performance`](../../Tests/Performance/)。
> 其他 WP 的算法/页面代码不在此修改；优化以补丁形式提交给模块 owner（见
> [`prs.md`](prs.md) 与 [`patches/`](patches/)）。

## 1. 目标与结论

| 契约 §10 | 目标 | 当前证据 | 状态 |
|---|---|---|---|
| 冷启动 | ≤2 s | 签名 + Instruments 采集流程已定义 | **待真机** |
| 首帧 | p95 ≤1.5 s | CI **1.021 s**（12MP → 2048 → 1280） | **CI 已测；真机待测** |
| 形变预览 | ≥30 fps（iPhone 13） | CI 1080p p50 **28.9 ms**（p95 51.5 ms，debug 尾延迟） | **CI 已测；真机待测** |
| 滑杆响应 | ≤100 ms | CI 端到端 **32.4 ms** | **CI 已测；真机待测** |
| 5 组学习 | ≤90 s | CI **2.964 s**（160×160 合成） | **CI 已测；真机待测** |
| 12MP 导出 | p95 ≤6 s | CI **0.344 s**（Metal + JPEG；替身算法） | **CI 已测；真机待测** |
| 预览内存 | ≤300 MB | CI 峰值增量 **14.47 MB** | **CI 已测；真机待测** |
| 导出内存 | ≤500 MB | CI 峰值增量 **50.94 MB** | **CI 已测；真机待测** |

> **诚实边界**：WP-24 会话在 Windows 上完成代码与协议，真实设备（iPhone 13 /
> SE 3）的 Instruments 结果尚未采集。没有真机数据时，文档不会写“真机达标”。
> 设备采集步骤见 [`instruments.md`](instruments.md)，签核矩阵见
> [`acceptance.md`](acceptance.md)。
>
> CI 基线来源：[run 40531729843](https://github.com/JHub-Wei/StyleTone/actions/runs/40531729843)
> （绿色，commit `6d4fea8`）以及引入门禁的两次 run；环境 `ci.macos.arm64`，debug。
> 完整数据与“最差回归统计量”方法见 [`baseline.md`](baseline.md) 与
> `Tests/Performance/Baselines/performance-baselines.json`。

## 2. 目录

```text
Tests/Performance/
├── Harness/                      # 平台无关的门禁库（可独立 swift test）
│   ├── Package.swift
│   ├── Sources/PerformanceKit/   # 场景、基线、门禁、热策略、内存、报告
│   └── Tests/PerformanceKitTests
├── Tests/PerformanceTests/       # 集成场景（首帧/形变/学习/导出/内存/取消…）
├── Baselines/
│   └── performance-baselines.json
├── Tools/
│   ├── run_device_performance.sh
│   ├── record_baseline.py
│   └── summarize_reports.py
└── README.md

docs/performance/
├── baseline.md                   # 方法、环境矩阵、实测基线
├── regression-gate.md            # >10% 阻断规则、基线更新、豁免流程
├── degradation.md                # 低端机/低电/热降级策略
├── instruments.md                # Instruments / xctrace / Jetsam / 热 soak
├── findings.md                   # 热点分析与优化项
├── prs.md                        # 给各模块 owner 的 PR 清单
├── acceptance.md                 # 真机签核矩阵
├── patches/                      # 可 review 的优化补丁
└── integration/                  # Package.swift / CI 的合入补丁
```

## 3. 快速开始

```bash
# 全部门禁场景（CI 上的标准入口；已接入 swift test 后自动执行）
swift test --filter StyleTonePerformanceTests

# 只跑门禁库（不依赖 iOS SDK / 应用模块）
swift test --package-path Tests/Performance/Harness

# 记录 CI/设备报告到目录（CI artifact）
ST_PERF_REPORT_DIR="$PWD/.perf-reports" \
  swift test --filter StyleTonePerformanceTests

# 真机参考设备（需要签名与设备；见 Tools/run_device_performance.sh）
ST_PERF_REFERENCE=1 ST_PERF_HEAVY=1 ST_PERF_REQUIRE_BASELINE=1 \
  Tests/Performance/Tools/run_device_performance.sh <DEVICE_UDID>
```

## 4. 门禁摘要

- 每个场景记录 p95；与 **同环境、同构建配置** 的基线比较。契约预算固定用 p95；
  `preview.frameTime` 的 CI 回归用更稳的 p50（尾延迟不作为共享 runner 结论）。
- 慢于基线 **10% 以上**（或 fps 低于基线 10% 以上）→ `regression` → 退出码 1。
- 契约 §10 的绝对预算在参考设备/低端机（或 `ST_PERF_STRICT=1`）上强制执行。
- 样本数低于场景要求 → `insufficientSamples`，也阻断。
- 没有基线 → 只记录、不阻断（首次采集）；发布签核要求
  `ST_PERF_REQUIRE_BASELINE=1`。
- 小绝对差噪声地板（例如 25 ms 帧上的 1 ms）只用于避免共享 CI runner 抖动，
  **不会**放过超过 10% 且超过噪声地板的回归。详见 [`regression-gate.md`](regression-gate.md)。

## 5. 隐私

- 所有性能素材都是合成图；不提交真实用户照片。
- 报告只含场景名、耗时、fps、MiB、设备型号、OS、commit，不含文件名/相册 ID/像素。
- `PerformanceKit` 无网络、无文件上传、无第三方分析 SDK。
