# Tests/Performance

WP-24 的性能门禁与场景。说明文档在 [`docs/performance`](../../docs/performance/)。

## 结构

| 路径 | 内容 |
|---|---|
| `Harness/` | 平台无关的 `PerformanceKit`：场景、基线、10% 门禁、热策略、内存、报告 |
| `Harness/Tests/` | 门禁库单测（可 `swift test --package-path Tests/Performance/Harness`） |
| `Tests/PerformanceTests/` | 集成场景：首帧、形变、滑杆、学习、导出、内存、取消、缓存 |
| `Baselines/performance-baselines.json` | 按环境/构建配置提交的基线 |
| `Tools/` | 真机运行、基线记录、报告汇总、热 soak |

## 运行

```bash
# 集成场景（需要根 Package.swift 已合入 integration/Package.swift.patch）
swift test --filter StyleTonePerformanceTests

# 只跑门禁库（无需 iOS SDK）
swift test --package-path Tests/Performance/Harness

# 报告落盘
ST_PERF_REPORT_DIR="$PWD/.perf-reports" swift test --filter StyleTonePerformanceTests
```

## 规则

- p95 比同环境基线慢 **>10%** → 阻断；见 `docs/performance/regression-gate.md`。
- `ST_PERF_STRICT=1` 或参考/低端真机 → 同时强制 §10 绝对预算。
- 无基线只报告，不阻断；发布签核用 `ST_PERF_REQUIRE_BASELINE=1`。
- 合成素材；不提交真实照片；报告不含 PII。

## 依赖

- `PerformanceKit`（本目录）由根 `Package.swift` 以 target 引入；
  合入补丁见 `docs/performance/integration/Package.swift.patch`。
- 集成测试依赖 Core/Imaging/Geometry/Learning/UI + GoldenSupport/TestShared。
- Metal 场景在无 GPU runner 上 `XCTSkip`；门禁库与纯 CPU 场景仍运行。
