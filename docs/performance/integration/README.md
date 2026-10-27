# 集成补丁（WP-24 → WP-00 owner）

WP-24 的所有权只覆盖 `Tests/Performance/` 与 `docs/performance/`。下面的改动
必须由 WP-00 owner 合入，门禁才会在普通 PR 的 `swift test` 中自动运行。

## 1. `Package.swift.patch`

新增：

- `PerformanceKit` target（`Tests/Performance/Harness/Sources/PerformanceKit`）；
- `StyleTonePerformanceTests` test target
  （`Tests/Performance/Tests/PerformanceTests`），依赖 Core/Imaging/Geometry/
  Learning/UI + GoldenSupport/TestShared。

合入后：

```bash
swift test --filter StyleTonePerformanceTests
```

## 2. `ios.yml.patch`

- 在 `swift test` 步骤设置 `ST_PERF_REPORT_DIR=${{ runner.temp }}/performance`；
- `if: always()` 上传 `performance-reports-<run_id>` artifact（14 天）。

这样失败时也能拿到 JSON/Markdown 报告；xcresult 仍由现有步骤上传。

## 3. 可选：真机 UI test target

冷启动的 `XCTApplicationLaunchMetric` 需要 UI test target；WP-24 不提供
`project.yml` 补丁，因为 App 当前尚未接通照片导入（WP-09/17 的集成仍在进行）。
合入 UI 测试后，把 `Tests/Performance/UITests/LaunchPerformanceTests.swift`
（待添加）加入 target，并在 `run_device_performance.sh` 里改用 `xcodebuild test`
的 UI scheme。方案见 `docs/performance/instruments.md` §2。

## 4. 合入顺序

1. `Package.swift.patch`（先让测试被编译）；
2. `ios.yml.patch`（报告 artifact）；
3. 更新 `Baselines/performance-baselines.json` 的 CI 条目（首次 run 后）；
4. 再启用 PR 上的门禁（当前门禁已在测试内部执行，只是测试尚未进入 `swift test`）。

## 5. 验证

```bash
# 应用两个补丁后
xcodegen generate
swift test --filter StyleTonePerformanceTests
git diff --stat Tests/Performance
```

预期：`StyleTonePerformanceTests` 在 macOS CI 上执行；Metal 缺失时相关场景
`XCTSkip`，不失败。
