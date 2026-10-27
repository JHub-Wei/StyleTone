# 性能回归门禁

> 验收：**性能回归 >10% 阻断**；不破坏契约与画质。

## 1. 规则

对每个场景：

1. **样本数**：`sampleCount < scenario.minimumSamples` → `insufficientSamples`，阻断。
2. **契约预算**（参考设备/低端机，或 `ST_PERF_STRICT=1`）：**p95** 超过 §10
   目标 → `contractExceeded`，阻断。
3. **基线匹配**：必须同 `environmentID`；否则 `environmentMismatch`，只报告。
4. **基线可用**：`gateEnabled == false` → `baselineNotGated`，只报告。
5. **回归**（使用 `scenario.regressionStatistic`，默认 p95）：
   - 耗时/内存（越低越好）：`measured > baseline × 1.10` 且
     `measured - baseline > noiseFloor` → `regression`。
   - fps（越高越好）：`measured < baseline × 0.90` 且
     `baseline - measured > noiseFloor` → `regression`。
6. 其余 `passed`。

`preview.frameTime` 的 `regressionStatistic` 是 **p50**：共享 CI runner 的 p95
尾部会被 1–2 个调度尾延迟拉到 50 ms，而 p50 稳定在 29 ms。契约仍用 p95，并在
参考设备强制；CI 的 10% 回归用 p50 比较。两种统计量用同一基线、同一 10% 规则，
不改变阻断阈值。

`noiseFloor` 是绝对噪声地板，不是“放宽 10%”。例：25 ms 帧的 1 ms 地板只挡
±4% 的抖动；一旦相对差 >10% **且**绝对差 >1 ms，仍然阻断。每个场景的 floor 在
`PerformanceScenario` 中公开、可审查。

**恰好 10%** 不阻断（实现用 `>`，不是 `>=`）。

## 2. 环境变量

| 变量 | 作用 |
|---|---|
| `ST_PERF_BASELINE_PATH` | 覆盖基线 JSON 路径 |
| `ST_PERF_REPORT_DIR` | 输出 `performance-*.json` / `.md`，供 CI artifact |
| `ST_PERF_REQUIRE_BASELINE=1` | 缺基线改为 `baselineRequired`（发布签核用） |
| `ST_PERF_STRICT=1` | 在 CI 上强制 §10 绝对预算 |
| `ST_PERF_HEAVY=1` | 运行 8 组学习等重型场景 |
| `ST_PERF_COMMIT` / `GITHUB_SHA` | 报告中的 commit |
| `ST_PERF_TOOLCHAIN` | 报告中的工具链说明 |

参考设备由 `uname`/`SIMULATOR_MODEL_IDENTIFIER` 识别，无需手动设置；
`PerformanceEnvironment` 决定是否强制契约预算。

## 3. 输出

每个测试类：

- `print("PERF ...")`：场景名、n、mean/p50/p95。
- `print("PERF_VERDICT ...")`：状态与原因。
- XCTest attachment：完整 Markdown 报告（`.keepAlways`）。
- `ST_PERF_REPORT_DIR`：同一报告的 JSON + Markdown 文件。

报告 JSON 结构：

```json
{
  "generatedAt": "...",
  "environment": { "id": "ci.macos.arm64", "kind": "ci", "buildConfiguration": "debug", ... },
  "commit": "...",
  "observations": [ { "measurement": { "scenarioID": "...", "p95": 0.123, ... } } ],
  "verdicts": [ { "status": "passed", "scenarioID": "...", "measuredValue": 0.123, "baselineValue": 0.12 } ]
}
```

## 4. CI 接入

WP-24 不修改 `.github/workflows/ios.yml`（WP-00 owner）。合入补丁见
[`integration/ios.yml.patch`](integration/ios.yml.patch)：

1. 在 `swift test` 步骤设置 `ST_PERF_REPORT_DIR`；
2. `if: always()` 上传 performance-reports artifact；
3. 可选：在发布分支设置 `ST_PERF_STRICT=1`。

在补丁合入前，当前分支的 CI 仍会执行测试（若 `Package.swift` 已合入），只是
报告文件写到 `$RUNNER_TEMP` 以外时需要手动指定目录。

## 5. 基线更新流程

1. 在**目标环境**运行（参考设备必须 Release）：
   ```bash
   ST_PERF_REPORT_DIR=.perf-reports \
     Tests/Performance/Tools/run_device_performance.sh <UDID>
   ```
2. 生成/更新基线：
   ```bash
   python3 Tests/Performance/Tools/record_baseline.py \
     --environment device.iphone13 \
     --reports .perf-reports \
     --commit "$(git rev-parse --short HEAD)"
   ```
3. Review `performance-baselines.json` 的 diff：
   - 只允许目标环境条目变化；
   - `sampleCount` 不低于场景最低要求；
   - 变慢的基线必须附 issue/原因；**不能**用调高基线来掩盖回归。
4. 两位 owner（iOS-A/QA）批准后合入。

## 6. 豁免

只有一种豁免：把某条基线标为 `"gateEnabled": false`。

- 必须在 PR 说明中写原因、影响范围、到期时间、补录计划；
- 同一场景连续两个 release 不得一直豁免；
- 契约 §10 的绝对预算不能被 `gateEnabled` 豁免（只影响相对基线）；
- 发布签核时 `ST_PERF_REQUIRE_BASELINE=1` 会让缺失基线变成阻断。

## 7. 为什么不用 XCTest `measure`

`measure` 的基线存在 Xcode 的 `BASELINE` 环境里，跨 CI runner 不稳定，且不可
在 PR diff 中 review。WP-24 用显式 JSON 基线 + p95 + 10% 规则，原因：

- 基线可版本化、可审计；
- 与设备/构建配置绑定；
- 同一套逻辑可在 SwiftPM、Xcode 和真机上复用；
- 失败信息直接给出 measured/baseline/limit。
