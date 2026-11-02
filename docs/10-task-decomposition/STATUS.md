# 工作包状态

## WP-00 · 工程骨架

- 状态：**done**
- 分支：`main`
- 工程骨架提交：`7f4666a`；最新 CI 成功提交：`e67d759`
- 完成内容：
  - XcodeGen `project.yml`：App target + 9 个 SwiftPM library target。
  - 根 `Package.swift`：9 个 library + 9 个 test target。
  - 9 个模块 marker 与占位测试。
  - SwiftUI App 入口与占位页。
  - GitHub Actions macOS CI：xcodegen → swift test → 自动选模拟器 → build → test → 上传 `.xcresult`。
  - Makefile、SwiftFormat、SwiftLint、`.gitignore`、`.gitattributes`。
  - `BUILD.md`、`CI-SETUP.md`。
- 本地静态校验：
  - `Package.swift` 中所有 target path 存在。
  - `project.yml` 的 9 个 product 与 `Package.swift` 一致。
  - `Info.plist` XML 可解析。
  - 21 个 Swift 文件括号平衡；Makefile 使用 tab。
  - Git 工作区干净。
- **macOS CI 结果：success**
  - 最新 Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40090672908
  - 提交：`e67d759c4c96c714cf72d10bf616073861029fb3`
  - 所有步骤通过：Set up / Checkout / Toolchain / Install XcodeGen / Generate / Swift package tests / Select simulator / Build app / Run app tests / Upload xcresult。
  - 首次成功 Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40090394824
- 远程状态：
  - `origin`：`https://github.com/JHub-Wei/StyleTone.git`
  - `main` 已推送；本地/远程均包含工程骨架。
- 下一步：
  1. 启动 **WP-01 Core 契约**（`docs/12-session-prompts.md` 的 S-A1 Prompt）。
  2. WP-01 完成后打 `core-v1` tag，再并行 WP-02/03/04。
- 说明：
  - 本次验证使用 GitHub Actions macOS runner；Windows 本机仍不能直接跑 `xcodebuild`。
  - GitHub 直连需要本地代理；Git 已配置当前仓库代理 `127.0.0.1:7890`。
  - 后续若新增 iOS-only API 导致 `swift test` 失败，可把 SwiftPM 测试拆成 iOS 测试或使用 `xcodebuild test`。

---

## WP-01 · Core 契约

- 状态：**done**
- 提交：`1117dae`
- Tag：`core-v1`
- CI：https://github.com/JHub-Wei/StyleTone/actions/runs/40091414979 （success）
- 完成内容：
  - `PixelSize`、`NormalizedPoint/Rect`、`ImageAsset`、`MaskBuffer`。
  - `PortraitAnalysis`、人脸/人体关键点、分析 warning。
  - `StyleProfile` schema 3 + 参数结构 + ISO8601 JSON 编解码。
  - `ManualAdjustments`、`BlemishPoint`、`RenderRequest`、`RenderOutput`。
  - `PairQuality`、`PairSample`、`CalibrationAnswer`。
  - `ExportOptions`、`PurchaseState`、`PurchaseProduct`。
  - 全部协议：分析/配对/学习/修饰/形变/渲染/导出/存储/购买。
  - `StyleToneError`、`AppError` 映射、Logger/Date 支持。
  - Core 契约测试 + test doubles（Mock analyzer/learner/purchaser/store）。
- 验收结果：
  - `swift test` 通过。
  - Xcode App build/test 通过。
  - 无网络/照片上传代码。
- 说明：
  - 当前 Mock 位于 Core 的测试 target，供契约测试使用；跨 Package 共享的 TestSupport target 由 WP-04 统一补齐，在那之前各 WP 可写自己的本地 mock。
- 下一步：
  1. 并行启动 WP-02（图像）、WP-03（设计/Shell）、WP-04（测试 Harness）。
  2. 三者完成后进入 WP-05/06/07/08/09/10/11。

---

## WP-02 ~ WP-11 · done（2026-10-25 拉取）

- 本地已切回 `main` 并拉取到 `9901a0c`（Merge PR #9，WP-11）。
- 远程 `main` CI：https://github.com/JHub-Wei/StyleTone/actions/runs/40110565858 （success）。
- 已完成并合并：
  - WP-02 图像 I/O / 色彩 / 编码
  - WP-03 设计系统 / App Shell / 路由
  - WP-04 测试 Harness / TestShared / GoldenSupport
  - WP-05 人像分析 + 配对质量
  - WP-06 网格形变 Core
  - WP-07 磨皮/匀肤/去瑕疵 Core
  - WP-08 SwiftData 持久化与迁移
  - WP-09 配对导入 / 质量 UI
  - WP-10 3/5/8 校准 + AB UI
  - WP-11 风格学习（tone/WB/saturation/strength/AB/confidence）
- WP-11 实测：
  - CI Debug、合成 160×160 样本：5 组约 **4.98 s**，8 组约 **7.81 s**。
  - 预算：5 组 ≤90 s，8 组 ≤150 s；当前远低于预算。
- 本地状态：
  - `main` 与 `origin/main` 同步，工作区干净。
  - 拉取前把 WP-09/10/11 的未跟踪本地产物存入 `stash@{0}`；远程已有对应源码，暂不恢复，待人工确认后可删除。
- 下一步可并行：
  - WP-12 瘦脸/下颌
  - WP-13 瘦手臂/腰
  - WP-14 瘦腿/拉长
  - WP-15 背景保护
  - WP-16 皮肤工具 UI
  - WP-17 编辑器
  - WP-19 导出
  - WP-21 设置

---

## WP-12 ~ WP-14 · done（2026-10-25 拉取）

- 本地 `main` 已从 `b27420b` 快进到 `d574799`（Merge PR #12，WP-14）。
- 工作区干净；`stash@{0}` 仍保留，未恢复。
- 已完成并合并：
  - WP-12 瘦脸/下颌
  - WP-13 瘦手臂/腰
  - WP-14 瘦腿/拉长
- CI 结果：
  - `d574799` 的 push run 曾因 GitHub Actions 账单问题未启动；手动 `workflow_dispatch` 已成功。
  - Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40159268015
  - 所有步骤 success：XcodeGen、SwiftPM 测试、模拟器构建、App 测试。
- 下一步可并行：
  - WP-15 背景保护
  - WP-16 皮肤工具 UI
  - WP-17 编辑器
  - WP-19 导出
  - WP-21 设置

---

## WP-15 ~ WP-21（A4）· done（2026-10-27 拉取）

- 本地 `main` 已从 `392dc00` 快进到 `b005dd7`（Merge PR #16，WP-21）。
- 已完成并合并：
  - WP-15 背景保护
  - WP-16 皮肤工具 UI + 点选去瑕疵
  - WP-17 编辑器 / 预览 / 撤销 / 导出编排
  - WP-19 全分辨率导出 / PhotoKit / 分享
  - WP-21 设置 / 隐私 / 诊断 / 删除本地数据
- CI 结果：
  - Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40481035914
  - `b005dd7`，所有步骤 success：XcodeGen、SwiftPM 测试、模拟器构建、App 测试。
- 当前 Phase A 剩余：
  - WP-23 错误/离线/边界态
  - WP-24 性能/内存/热
  - WP-25 黄金图/质量回归
- 本地 stash：
  - `stash@{0}`：A4 的 Export/SkinTools 未跟踪产物
  - `stash@{1}`：WP-09/10/11 未跟踪产物
  - 远程已有对应源码，暂不恢复。

---

## WP-23 ~ WP-25（A5）· done（2026-10-28 拉取）

- 本地 `main` 已从 `9a601df` 快进到 `36b94ef`（Merge PR #20，WP-25）。
- 已完成并合并：
  - WP-23 错误/离线/边界态
  - WP-24 性能/内存/热
  - WP-25 黄金图/质量回归
- main CI：
  - Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40681827712
  - 结论：**success**
  - 所有步骤通过：XcodeGen、SwiftPM 测试、模拟器 Build、App tests、golden artifacts 上传。
- Phase A 状态：
  - 23 个 Phase A WP 全部 `done`。
- 下一步：
  - 进入 Phase B（WP-18 风格卡、WP-22 引导、WP-27 TestFlight）。

---

## Issue #19 · fixed（2026-10-28）

- 结论：issue 描述的 **V/VI 肤色漂移是真实问题**，但“CTM 未翻转导致上下镜像”的诊断不成立。
- 回归验证：
  - 不加 CTM flip，低频场保持 top-down，方向测试通过；
  - 加上 issue 建议的 `translate`/`scale` flip，低频场反而镜像（32 px 场 luma 质心 27.4，期望 <8）。
- 实际根因：
  - `LowFrequencyField` 用整张图构建 luma/chroma；evenness 会从皮肤边界外的背景/头发/衣服借色，导致深肤色被提亮、去饱和。
- 修复：
  - 低频场按 skin alpha 加权（降采样到 field grid）。
  - 全 coverage mask 走原始 three-blur 快路径，保住 512×512 预览性能预算。
  - 新增方向回归 + 暗肤色/亮背景边界回归。
- 合并：
  - PR #23，squash commit `711aed4`。
  - PR CI：https://github.com/JHub-Wei/StyleTone/actions/runs/40697662632 （success）
  - Issue 已关闭。
- WP-25 后续（已完成）：
  - WP-07 修正 evenness 混合方向（从 guided base 出发，不再越过低频场）、增加 2 px silhouette guard、加入 source-aware headroom clamp。
  - bootstrap `evenness: 0.35`：100 样本 skin incidents **0**、edge failures **0**、background 3.37%、fairness 0.095 ΔL、dark-skin 0.103 ΔL。
  - Run：https://github.com/JHub-Wei/StyleTone/actions/runs/40735868266 （success）
  - 新 baseline + 12 goldens 已提交；comparison run：https://github.com/JHub-Wei/StyleTone/actions/runs/40740318152 （success）
  - PR #25，merge commit `1a1d65c`。
- Phase C（WP-20/26/28/29）在 Phase B 验证后启动。

---

## A6 · App 集成与真机安装（2026-11-01）

- 状态：**done（集成/安装）**，真机 Gate A Smoke 待执行。
- PR #26，merge commit `de07c35`。
- 内容：
  - `A6RootView` 接管 App 入口，替换 WP-00 占位页。
  - 真实依赖：Vision、SwiftData、StyleLearning、SkinRetoucher、Geometry、FileImageExporter、PhotoKit。
  - 流程：最小欢迎 → 配对 → 校准 → 编辑器 → 导出 → 设置/删除数据。
  - Info.plist 增加相册 add/read 权限说明与 export compliance。
  - 新增 unsigned IPA workflow。
- 验证：
  - iOS CI（SwiftPM + app build + app tests）：https://github.com/JHub-Wei/StyleTone/actions/runs/41215018035 （success）
  - unsigned IPA：https://github.com/JHub-Wei/StyleTone/actions/runs/41213604810 （success）
  - 真机：iPhone15 / iOS 27.0.1，Sideloadly 免费签名安装成功，App 可打开。
- 分发：
  - Sideloadly 位于 `D:\Tools\Sideloadly\app`；IPA 位于 `D:\Tools\Sideloadly\A6`。
  - Apple Mobile Device Support/iTunes 为系统组件，安装在 C 盘。
  - 免费签名 7 天过期，auto-refresh daemon 已运行。
- 下一步：
  - 按 [sideloadly-validation.md](../beta/sideloadly-validation.md) 执行 Gate A Smoke。
  - 重点验证配对/校准/编辑/导出/权限/删除数据。
  - Phase B 继续冻结。

---

## 中文本地化（2026-11-01）

- 状态：**done**
- 问题：App 没有 `Localizable.xcstrings`，所有功能页回退到英文。
- 修复：
  - 新增 `App/Localizable.xcstrings`，680 条 zh-Hans（覆盖全部 661 个英文 fallback key + A6 copy）。
  - `L10n.resolve` 强制 zh-Hans；Info.plist 增加 `CFBundleLocalizations = zh-Hans`。
  - `DEVELOPMENT_LANGUAGE = zh-Hans`；新增本地化回归测试。
- 验证：
  - iOS CI：https://github.com/JHub-Wei/StyleTone/actions/runs/41316549195 （success）
  - 中文 unsigned IPA：https://github.com/JHub-Wei/StyleTone/actions/runs/41316548972 （success）
  - 真机覆盖安装后确认中文界面。
- PR #27，merge commit `a2dd26c`。
- 报告：[zh-Hans-localization-report.md](../zh-Hans-localization-report.md)。

---

## Tone 渲染与校准强度修复（2026-11-02）

- 状态：**done**
- 问题：用户完成 3 组配对 + 8 张 A/B 后，照片仍接近原图。
- 诊断：profile 被保存但几乎中性（`色温0 · 对比-2 · 饱和-1 · 磨皮0 · 瘦脸0`）。
- 修复：
  - 新增 `CoreImageToneRenderer`，接入预览和导出：曝光、对比、高光/阴影、色温/色调、饱和、颗粒、暗角。
  - 3 组 A/B 影响力从“几乎不可见”提升到可见强度，仍受 `StyleSafetyRanges` 限制。
  - 3 组 shrink 从 `0.35` 提高到 `0.50`；学习代理图从 `256px` 提高到 `384px`。
  - 编辑器顶部新增“已学习 N 组 · 色温/对比/饱和/磨皮/瘦脸”摘要，便于确认真实 profile。
- 验证：
  - iOS CI：https://github.com/JHub-Wei/StyleTone/actions/runs/41458662966 （success）
  - Unsigned IPA：https://github.com/JHub-Wei/StyleTone/actions/runs/41464081192 （success）
  - 真机重新校准后确认照片有变化。
- PR #28，merge commit `74d3540`。









