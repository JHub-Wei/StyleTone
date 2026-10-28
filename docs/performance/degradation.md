# 低端机 / 低电 / 热降级策略

> 契约 §10 的绝对目标只针对 iPhone 13；低端机允许**预览质量**降级，但导出
> 分辨率/质量、画质契约、算法结果不降级。

## 1. 原则

1. **只降预览，不降导出**：代理长边和网格可以降；`RenderOutput` 与导出文件
   始终使用全分辨率、原质量。性能告警不能成为“悄悄导出低清”的理由。
2. **可解释**：降级有原因、有 UI 提示、可在设置诊断里看到；不静默。
3. **可恢复**：热/低电解除后回到上一档；WP-17 governor 已有恢复规则。
4. **不破坏契约**：不改变 `StyleParameters`、`RenderRequest`、`ImageAsset`、
   `ExportOptions` 等 Core 类型；不改变预览/导出文件的一致性语义。
5. **不牺牲画质**：预览降档只影响拖动时的临时帧；松手后的 full 渲染仍是原图
   分辨率（除非 critical 热，此时延后 full 渲染，但仍不允许降分辨率）。

## 2. 设备分级

| 分级 | 判定 | 初始档位 |
|---|---|---|
| `reference` | iPhone 14,2/14,3/14,4/14,5（13 系列） | full（1280） |
| `lowEnd` | iPhone SE 2/3、12 mini、11 系列，或物理内存 <3.5 GB | reduced（960） |
| `unknown` | 模拟器/CI/未识别 | full（不应用 UI 策略） |

判定由宿主提供（`PerformanceTestEnvironment.deviceClass` 是测试侧参考实现），
不在算法层用 benchmark 猜设备。生产实现建议放 `StyleToneUI/Editor`，见
[`patches/wp-17-thermal-degradation.patch`](patches/wp-17-thermal-degradation.patch)。

## 3. 热 / 低电映射

`ThermalPerformancePolicy`（`Tests/Performance/Harness/Sources/PerformanceKit/ThermalPolicy.swift`）
的可执行规格：

| 状态 | 档位下限 | full 渲染 | 导出 | 提示 |
|---|---|---|---|---|
| `nominal` + normal | full（低端机 reduced） | 允许 | 允许 | 仅低端机提示 |
| `nominal` + lowPower | reduced | 允许 | 允许 | `editor.performance.lowPower` |
| `fair` | reduced | 允许 | 允许 | `editor.performance.thermalFair` |
| `serious` | minimal（640） | 允许 | 允许，导出前提示 | `editor.performance.thermalSerious` |
| `critical` | minimal（640） | **延后** | 允许，导出前提示 | `editor.performance.thermalCritical` |

与 WP-17 governor 合并时取**更差**档位：

```text
tier = max(deviceBase, thermalBase, lowPowerBase, governorTier)
```

- governor 只看完成 preview 的耗时：两次 ≥280 ms 降一档；三次 ≤100 ms 升一档
  （已实现于 `EditorPerformanceGovernor`）。
- 热/低电是外部约束，不能被 governor 的“恢复”抵消；解除后 governor 仍按自己的
  快/慢 streak 恢复。
- `critical` 时暂停下一次 full-quality render，等回到 `serious`/`fair` 再补；
  预览继续用 640 代理，保证 UI 不冻结。
- 导出永远允许：用户已经完成编辑时，阻止导出比慢一点更糟。导出前提示“设备较热，
  可能更慢”，不改变输出。

## 4. 档位

| 档位 | 长边 | 当前网格 | 用途 |
|---|---:|---:|---|
| full | 1280 | 32×32 | 参考设备正常 |
| reduced | 960 | 32×32 | 低端机/低电/fair |
| minimal | 640 | 32×32 | serious/critical |

当前 `EditorPerformanceGovernor` 只改代理长边，不改网格。网格降级是 WP-06
owner 的后续工作（需要新增 24×24 档位并验证边界/画质）；WP-24 的
`wp-06-metal-frame-resource-cache.patch` 只做资源缓存，**不**声称网格降级已生效。

## 5. 提示文案（提案，需 UI owner 合入）

| key | 场景 | 建议文案（zh-Hans） |
|---|---|---|
| `editor.performance.lowPower` | 低电模式 | 已开启低电量模式，预览会使用较低清晰度；导出不受影响。 |
| `editor.performance.thermalFair` | 设备温热 | 设备温度偏高，已降低预览清晰度。 |
| `editor.performance.thermalSerious` | 较热 | 设备较热，预览已降为低清晰度；导出可能更慢。 |
| `editor.performance.thermalCritical` | 很热 | 设备温度过高，已暂停高质量预览；导出前请等待降温。 |
| `editor.performance.lowEnd` | 低端机 | 当前设备使用流畅优先的预览清晰度。 |
| `editor.performance.reducedPreview` | governor 降档 | 预览清晰度已自动降低。 |

- 不放“设备过热”红色警告制造焦虑；用中性文案 + 可关闭的一次性提示。
- 提示不阻塞操作；导出警告只出现在用户点导出时。
- 不得把提示做成“性能评分”或对用户设备的贬损。

## 6. 低端机验收

| 检查 | 方法 | 通过标准 |
|---|---|---|
| 预览 30 fps | 1080p 代理，Instruments / 门禁 | 低端机允许降到 24 fps 档位？**不**：§10 仅 iPhone 13；低端机目标 ≥24 fps 且不卡死 |
| 滑杆响应 | 端到端 | ≤150 ms（低端机放宽，记录基线） |
| 首帧 | 12MP 解码 | ≤2.5 s |
| 导出 | 12MP | ≤10 s，且分辨率/质量不变 |
| 内存 | `phys_footprint` | 预览 ≤300 MB；导出 ≤500 MB |
| 热 | 10 min soak | 无 critical 持续 >60 s；无 Jetsam |

> 低端机放宽值不是 §10 的替代品，只是降级矩阵的工程目标；必须在
> `acceptance.md` 里单独记录。
