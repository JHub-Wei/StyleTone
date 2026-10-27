# WP-24 验收与签核矩阵

> 状态：**代码/门禁完成并已通过绿色 CI（run 40531729843）；真机证据待采集**。
> 本文件区分“CI 已证明”和“必须真机才能证明”的项目，不做虚假勾选。

## 1. 契约 §10

| # | 项目 | 目标 | CI 证据（2026-10-27, `6d4fea8`） | iPhone 13 | 低端机（SE 3） | 结论 |
|---|---|---|---|---|---|---|
| 1 | 冷启动 | ≤2 s | 未接入 | 待测 | 待测 | **pending** |
| 2 | 首帧 | p95 ≤1.5 s | **1.021 s** | 待测 | 待测 | **CI 通过；真机待测** |
| 3 | 形变预览 | ≥30 fps | **p50 28.9 ms / p95 51.5 ms**（debug） | 待测 | 待测 | **CI p50 达标；真机待测** |
| 4 | 滑杆响应 | ≤100 ms | **32.4 ms** | 待测 | 待测 | **CI 通过；真机待测** |
| 5 | 5 组学习 | ≤90 s | **2.964 s** | 待测 | 待测 | **CI 通过；真机待测** |
| 6 | 12MP 导出 | p95 ≤6 s | **0.344 s**（替身算法） | 待测 | 待测 | **CI 通过；真机待测** |
| 7 | 预览内存 | ≤300 MB | **14.47 MB 增量** | 待测 | 待测 | **CI 通过；真机待测** |
| 8 | 导出内存 | ≤500 MB | **50.94 MB 增量** | 待测 | 待测 | **CI 通过；真机待测** |

“CI 通过”= 在 macOS debug CI 的合成素材上，测试断言/门禁通过；绝对设备性能仍需
真机。形变预览在 debug CI 上 p50 28.9 ms（34.6 fps），但 p95 受两个调度尾延迟影响为
51.5 ms；因此 CI 的回归比较使用 p50，绝对 p95 契约只在参考设备强制，参考设备
必须 ≥30 fps。

## 2. 其它验收

| 项目 | 证据 | 状态 |
|---|---|---|
| 无 Jetsam | 真机 10 min soak + `log collect` | 待测 |
| 无严重降频 | soak 后 3 min p95 ≤1/24 s，且不进 critical >60 s | 待测 |
| 回归 >10% 阻断 | `PerformanceGate` 单测 + 集成场景 | **完成** |
| 不破坏契约 | 未改 Core / 模块源码；补丁只动预览/缓存/热策略 | **完成** |
| 不破坏画质 | 导出路径不降分辨率/质量；补丁审阅 + WP-25 黄金图 | **补丁待合入** |
| 低端机降级 | `ThermalPerformancePolicy` + 设备矩阵 | **策略完成；集成待合入** |
| 低电/热提示 | 文案 key 提案（degradation.md） | **UI 待合入** |
| Instruments 基线 | 手册 + signpost 定义 | **CI 基线已有；真机待采** |
| 报告 | README/baseline/gate/degradation/instruments/findings | **完成** |

## 3. 真机签核记录模板

每次签核复制一份：

```text
设备：iPhone 13 (iPhone14,5) / iOS 18.x / build 20A...
构建：Release / commit <sha>
环境：电量 100%、低电关、亮度 50%、飞行模式、室温 24°C
场景：firstFrame / warp / slider / learning / export / previewMemory / exportMemory
结果：
  firstFrame p95 = ___ s（目标 1.5）
  warp p95 = ___ ms（目标 ≤33.3）
  slider p95 = ___ ms（目标 ≤100）
  learning p95 = ___ s（目标 ≤90）
  export p95 = ___ s（目标 ≤6）
  preview peak = ___ MB（目标 ≤300）
  export peak = ___ MB（目标 ≤500）
  soak：critical 持续 ___ s；末段 p95 ___ ms；Jetsam ___
结论：pass / fail
附件：xcresult / trace / jetsam logarchive
```

## 4. 阻断发布的条件

- 任一 §10 项目在 iPhone 13 上超标；
- 出现 Jetsam 或 App 被系统终止；
- 热 soak 进入 critical 且持续 >60 s，或末段 p95 >1/24 s；
- 任一已记录基线回归 >10% 且无批准的 `gateEnabled=false`；
- 性能优化改变了导出分辨率/质量或 Core 契约；
- 预览/导出不一致（性能补丁引入的回归）。

## 5. 已知风险（发布前必须关闭）

1. 真机基线未采集 → 无法签核 §10 的绝对目标。
2. 12MP 导出未接真实 retouch/tone 引擎 → 当前数字偏乐观。
3. 冷启动未接入 XCUITest/Instruments → 只有手册。
4. 低端机矩阵未实测 → 降级策略未验证。
5. 生产 App 未接热/低电通知 → 策略只在测试库中生效。
