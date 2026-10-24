# 12 · 独立/并行开发 Prompt 包

- 文档版本：v1.0
- 日期：2026-10-24
- 用途：按 [30 个工作包](10-task-decomposition/README.md) 直接开独立会话；每段 Prompt 可原样复制。
- 前置：先读 [任务分解](10-task-decomposition/README.md)、[共享契约](10-task-decomposition/contracts.md)、[任务卡](10-task-decomposition/task-cards.md)。

> **不要一次启动 30 个会话。** 先跑完 Wave 0，再按批次并行。下面的 Prompt 已标好前置和阶段。
>
> **Phase A 必须完成核心闭环**：WP-00~11、12~17、19、21、23~25；不能为了缩短工期跳过 WP-09/10/11（配对/校准/风格学习）。

---

## 1. 并行批次

| 批次 | 会话 | 工作包 | 前置 |
|---|---|---|---|
| A0 | 1 个 | WP-00 工程骨架 | 无 |
| A1 | 1 个 | WP-01 Core 契约 | WP-00 |
| A2 | 3 个并行 | WP-02 图像、WP-03 设计/Shell、WP-04 测试 | WP-01 |
| A3 | 7 个并行 | WP-05 分析、WP-06 形变 Core、WP-07 皮肤、WP-08 持久化、WP-09 配对、WP-10 校准、WP-11 风格学习 | Wave 0 |
| A4 | 最多 8 个并行 | WP-12 脸、WP-13 身材、WP-14 腿、WP-15 背景、WP-16 皮肤 UI、WP-17 编辑器、WP-19 导出、WP-21 设置 | WP-05/06/07/08 等 |
| A5 | 3 个并行 | WP-23 边界态、WP-24 性能、WP-25 黄金图 | A3/A4 核心完成 |
| B | 3 个并行 | WP-18 风格卡、WP-22 引导、WP-27 TestFlight | Phase A 自用通过 |
| C | 4 个并行 | WP-20 订阅、WP-26 无障碍、WP-28 商店/备案、WP-29 发布 | Phase B 通过 |

**第一阶段只做 A0–A5。** B/C 的 Prompt 先留存，不要提前启动。

---

## 2. 所有会话的硬约束

每个 Prompt 都已包含，但这里再明确一次：

1. 只改 `Owns` 路径；不改 `StyleToneCore` 公开契约。
2. 不新增第三方依赖、不接网络/账号/云、不上传照片。
3. Swift 6 / iOS 17；公开 API 有 DocC 注释；补单元测试。
4. 不提交真实用户照片；测试用 `Fixtures/` 合成/授权样本。
5. 无 `print`、无照片/文件名/相册 ID 日志。
6. Windows 无法跑 iOS 构建：推分支触发 macOS CI，报告 `CI_PENDING`，不要声称测试通过。
7. 契约不够用：写 CCR 并停；不要擅自改 Core。
8. 完成后按统一格式报告（见第 4 节）。

---

## 3. 独立开发 Prompt

### S-A0 · WP-00 工程骨架

```text
你是独立开发会话，负责 WP-00（仓库/XcodeGen/模块骨架/CI）。工作区：D:\AI\Personalized-ps。

先读：
- docs/10-task-decomposition/README.md
- docs/10-task-decomposition/contracts.md
- docs/10-task-decomposition/task-cards.md 的 WP-00

只改：
project.yml、Package.swift、App/StyleToneApp.swift、.github/、Makefile、.swiftformat、.swiftlint.yml、9 个模块空壳。

目标：
1. 用 XcodeGen 生成 App target + 9 个 SwiftPM library target（单根 Package.swift）。
2. 依赖方向严格按 contracts §1.2；Core 不依赖 UI/Vision/Metal/StoreKit。
3. App 启动到占位页；Debug/Release；iOS 17。
4. GitHub Actions macOS：xcodegen → build → swift test → simulator test。
5. 不实现业务功能、不接网络/账号/云、不引入第三方运行时依赖。

验收：
- xcodegen generate 成功；xcodebuild build 成功。
- 所有模块可 swift test；CI 绿灯。
- 模块空壳与测试占位齐全。

完成后报告：改动、测试命令/结果、CI 状态、风险。当前是 Windows 就推 CI 并标 CI_PENDING。
```

### S-A1 · WP-01 Core 契约

```text
你是独立开发会话，负责 WP-01（Core 契约与 JSON schema）。工作区：D:\AI\Personalized-ps。

先读：
- docs/10-task-decomposition/contracts.md §3–§6
- docs/10-task-decomposition/task-cards.md 的 WP-01
- docs/02-technical-architecture.md 的风格/渲染数据部分

只改：Packages/StyleToneCore/。
目标：落地 PixelSize、ImageAsset、MaskBuffer、PortraitAnalysis、StyleProfile、RenderRequest、BlemishPoint、StyleToneError，以及 contracts §4 的全部协议与 Mock。
要求：
- StyleProfile Codable roundtrip；schemaVersion=3；默认值/兼容解码。
- MaskBuffer 长度校验；坐标 0...1；Sendable 编译。
- 提供 Mock analyzer/learner/purchaser/image factory。
- 公开 API DocC 注释；无 fatalError。
验收：单元测试全绿；其他模块只 import Core 可编译占位。
完成后打 core-v1 tag，并报告公开 API 清单、测试、风险。
```

### S-A2a · WP-02 图像 I/O

```text
你是独立开发会话，负责 WP-02（图像 I/O/方向/色彩/编码）。工作区：D:\AI\Personalized-ps。

先读：docs/10-task-decomposition/contracts.md、task-cards.md 的 WP-02。
只改：Packages/StyleToneImaging/。
依赖：WP-01 已合并；使用 Core 的 ImageAsset/错误类型。

实现：
1. ImageLoader：HEIC/JPEG/PNG、EXIF orientation、降采样、错误分类。
2. ColorPipeline：sRGB ↔ linear extended sRGB、P3 输入、色域映射。
3. ImageWriter：HEIC/JPEG、质量、ICC、默认去 GPS。
4. ImageExporting 的文件编码实现（URL 输出）。
5. 测试：方向、纯色、渐变、P3/sRGB、损坏文件。

验收：四种格式/方向正确；导出 ICC 正确；单测覆盖；预览降采样不改变宽高比；无 UI。
完成后报告：改动、测试、性能、风险。
```

### S-A2b · WP-03 设计系统/Shell

```text
你是独立开发会话，负责 WP-03（设计系统/App Shell/路由）。工作区：D:\AI\Personalized-ps。

先读：docs/10-task-decomposition/contracts.md §8、task-cards.md 的 WP-03。
只改：Packages/StyleToneUI/DesignSystem/、App/AppShell/。
依赖：WP-01 已合并。

实现：
- Color/Spacing/Typography tokens；暗色；18% 灰照片背景。
- PrimaryButton、SliderRow、SectionHeader、PhotoCanvas、Toast、Loading。
- 路由枚举、依赖注入容器（只依赖 Core 协议，不 import 具体 Vision/Metal/StoreKit 实现）。
- 占位页与 Preview；accessibilityIdentifier 规范；本地化 key 前缀。
- 不做业务页面/算法。

验收：组件可 Preview；路由切换不崩；Dynamic Type/对比度基线；无硬编码颜色；CI 编译。
完成后报告：组件清单、截图/Preview、测试、风险。
```

### S-A2c · WP-04 测试 Harness

```text
你是独立开发会话，负责 WP-04（测试 Harness/合成 Fixtures）。工作区：D:\AI\Personalized-ps。

先读：docs/10-task-decomposition/contracts.md §7、task-cards.md 的 WP-04。
只改：Tests/Shared/、Tests/GoldenSupport/、Fixtures/。
依赖：WP-01 已合并。

实现：
- 合成图生成器：纯色、渐变、棋盘、色卡、噪声、直线/边缘、简单人脸轮廓示意。
- 图像差异工具：逐像素 ΔE/SSIM/阈值报告。
- 共享 Mock：analysis/style/purchase/image。
- 性能测试模板；CI 报告格式。
- 不提交真实用户照片；不依赖网络。

验收：任意模块可 import GoldenSupport；10 个 fixtures 自检通过；CI 可跑。
完成后报告：fixtures 清单、工具 API、测试、风险。
```

### S-A3a · WP-05 人像分析 + 配对质量

```text
你是独立开发会话，负责 WP-05（人像分析 + 配对质量）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-05。
只改：Packages/StyleToneVision/。
依赖：WP-01/02/04 已合并；可先用 Fixtures 合成图与授权样本。

实现：
- VisionPortraitAnalyzer：人脸关键点、人体姿态、人体分割、皮肤概率、背景边缘/直线蒙版。
- 输出 PortraitAnalysis：归一化点、MaskBuffer、warnings、confidence。
- VisionPairQualityAnalyzer：FeaturePrint 相似度、配准、分辨率、结构差异 → PairQuality。
- 多脸/无人脸/无人体安全降级；不建人脸模板、不写 PII 日志。

验收：坐标 0...1；蒙版尺寸正确；空输入/多脸测试；20 张授权样本人工抽检；1024px 分析 ≤1.5s。
完成后报告：API、样本结果、性能、风险。
```

### S-A3b · WP-06 形变 Core

```text
你是独立开发会话，负责 WP-06（网格形变 Core）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §4.1、task-cards.md 的 WP-06。
只改：Packages/StyleToneGeometry/Core/。
依赖：WP-01/02/04；可先用 mock analysis。

实现：
- 32×32 预览 / 64×64 导出网格；WarpField；Metal compute/render；双线性采样；边界固定/羽化。
- GeometryPass/GeometryConstraint 执行顺序；GeometryRendering 骨架。
- 无位移时与原图在 ΔE/像素阈值内；无黑边。
- 1080p 30fps 性能 harness。

验收：合成网格正确；边界/采样单测；性能记录；不实现具体脸/身体形态。
完成后报告：API、测试、帧率、风险。
```

### S-A3c · WP-07 皮肤 Core

```text
你是独立开发会话，负责 WP-07（磨皮/匀肤/去瑕疵 Core）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-07。
只改：Packages/StyleToneRetouch/。
依赖：WP-01/02/04；可用 mock masks。

实现：
- RetouchRendering：引导滤波/双边滤波 + 高频分离；smoothing 强度。
- 匀肤：肤色蒙版内低频均衡；限幅、不改色相、不美白。
- BlemishRemoving：点/半径 → patch-based 修复；可撤销由 UI 负责。
- 无蒙版安全降级；多肤色测试；12MP ≤2s。

验收：强度 0 近似原图；保留纹理；多肤色无过亮/偏灰；空/越界安全。
完成后报告：算法参数、测试、性能、风险。
```

### S-A3d · WP-08 持久化

```text
你是独立开发会话，负责 WP-08（本地持久化与迁移）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §6、task-cards.md 的 WP-08。
只改：Packages/StyleTonePersistence/。
依赖：WP-01。

实现：
- SwiftData models：StyleProfileRecord、EditRecord、PairSessionRecord、QuotaRecord。
- StyleProfileStore 实现；JSON + 文件；schemaVersion 迁移；损坏恢复；删除全部数据。
- 文件保护；无账号/无网络；并发安全。
- 测试：CRUD、迁移、损坏、删除。

验收：重启保留；旧 schema 可迁移/明确提示；删除无残留；无主线程 I/O。
完成后报告：模型、迁移策略、测试、风险。
```

### S-A3e · WP-09 配对导入

```text
你是独立开发会话，负责 WP-09（配对导入/质量检查 UI）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-09。
只改：Packages/StyleToneUI/Pairing/。
依赖：WP-02/08；PairQualityAnalyzing 用 mock（WP-05 完成后替换）。

实现：
- PHPicker 选择原图/成片；替换/删除；会话持久化。
- 配对卡片；质量分级/原因；进度 1/3、1/5、1/8；完成/跳过。
- 空状态/权限/错误；accessibilityIdentifier；UI 测试。
- 不复制照片到共享容器；无网络/账号。

验收：12 组 ≤6 分钟目标可测；替换/删除不丢数据；红色拒绝不进入学习。
完成后报告：流程截图、测试、风险。
```

### S-A3f · WP-10 校准 UI

```text
你是独立开发会话，负责 WP-10（3/5/8 校准 + AB UI）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-10。
只改：Packages/StyleToneUI/Calibration/。
依赖：WP-03/08/09；StyleLearning 用 mock（WP-11 完成后替换）。

实现：
- 3/5/8 流程、6–8 次 AB、进度、取消/恢复。
- 调用 StyleLearning；风格卡预览占位；跳过 → 自然默认；重新校准。
- 无登录/账号；文案/无障碍/UI 测试。

验收：3 组完成 ≤4 分钟目标；AB 可跳过；失败不丢配对；无账号入口。
完成后报告：流程、测试、风险。
```

### S-A3g · WP-11 风格学习

```text
你是独立开发会话，负责 WP-11（风格学习）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-11。
只改：Packages/StyleToneLearning/。
依赖：WP-01/04；用 fixtures/mocks。

实现：
- 影调/白平衡/饱和度拟合；肤色保护。
- 磨皮/脸型/身材力度估计；限幅。
- 6–8 次 AB → 参数约束；3/5/8 收缩；留出验证；置信度。
- 输出 StyleProfile schema 3；算法版本。

验收：5 组 ≤90s；输出限幅；3 组强收缩/8 组稳定；异常样本不崩；测试覆盖。
完成后报告：算法、参数范围、测试、风险。
```

### S-A4a · WP-12 瘦脸/下颌

```text
你是独立开发会话，负责 WP-12（瘦脸/下颌）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §4.1、task-cards.md 的 WP-12。
只改：Packages/StyleToneGeometry/Face/。
依赖：WP-05/06 已合并；使用 GeometryPass。

实现：脸颊/下颌位移贡献；五官/发际线保护；左右对称；强度限幅；多脸按面积；失败 warning。不实现背景保护/WP-15。
验收：合成关键点位移正确；强强度不吞五官；性能满足 30fps 贡献；单测。
完成后报告：位移策略、测试、风险。
```

### S-A4b · WP-13 瘦手臂/腰

```text
你是独立开发会话，负责 WP-13（瘦手臂/腰）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §4.1、task-cards.md 的 WP-13。
只改：Packages/StyleToneGeometry/Body/。
依赖：WP-05/06；使用 GeometryPass。

实现：基于姿态/分割的手臂与腰部内收；多人/遮挡/低置信度 warning；强度限幅；不改变背景直线（交给 WP-15）。
验收：轮廓自然；无人体/遮挡安全跳过；单测/性能。
完成后报告：策略、测试、风险。
```

### S-A4c · WP-14 瘦腿/拉长

```text
你是独立开发会话，负责 WP-14（瘦腿/拉长）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §4.1、task-cards.md 的 WP-14。
只改：Packages/StyleToneGeometry/Legs/。
依赖：WP-05/06；使用 GeometryPass。

实现：瘦腿 + 1.00–1.15 拉长；髋/膝/踝锚点；脚/鞋保护；边缘延展/镜像；强度限幅。
验收：无黑边/明显拉伸；脚部完整；无人体安全跳过；单测。
完成后报告：锚点/限幅、测试、风险。
```

### S-A4d · WP-15 背景保护

```text
你是独立开发会话，负责 WP-15（背景保护）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §4.1、task-cards.md 的 WP-15。
只改：Packages/StyleToneGeometry/Background/。
依赖：WP-05/06；实现 GeometryConstraint。

实现：边缘/直线/矩形检测 → 保护权重；位移惩罚/边界约束；开关 warning；门框/地砖/桌沿合成测试；100 张授权样本人工验收。
验收：明显背景扭曲 <5%；不显著降低瘦身效果；性能可接受。
完成后报告：检测/约束策略、样本结果、风险。
```

### S-A4e · WP-16 皮肤工具 UI

```text
你是独立开发会话，负责 WP-16（皮肤工具 UI + 点选去瑕疵）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-16。
只改：Packages/StyleToneUI/SkinTools/。
依赖：WP-03/07。

实现：磨皮/匀肤滑杆；点选修复交互（放大/点选/半径/撤销）；调用 RetouchRendering/BlemishRemoving；错误态；无障碍 ID；UI 测试。
验收：强度 0 回原图；点选可撤销；失败不破坏原图；无脸隐藏/禁用。
完成后报告：交互、测试、风险。
```

### S-A4f · WP-17 编辑器

```text
你是独立开发会话，负责 WP-17（编辑器状态/预览/撤销）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §5、task-cards.md 的 WP-17。
只改：Packages/StyleToneUI/Editor/。
依赖：WP-03/06/07/11；可 mock。

实现：
- 分析→修饰→形变→影调→导出编排；四区工具；滑杆。
- 预览：拖动低分辨率，松手高质量；取消旧渲染。
- 长按/分屏/缩放；自然档/总强度；背景保护；blemishPoints；≥20 步撤销。
- 场景 warnings；性能降级。

验收：无操作原图/导出一致；拖动不卡死；取消不写半成品；20 步撤销；与协议/mock 独立可跑。
完成后报告：状态机、测试、性能、风险。
```

### S-A4g · WP-19 导出

```text
你是独立开发会话，负责 WP-19（导出/相册/分享）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-19。
只改：Packages/StyleToneUI/Export/。
依赖：WP-02/17；可用 mock render。

实现：全分辨率导出、进度/取消/重试；PhotoKit add-only；系统分享；HEIC/JPEG；默认去 GPS；失败不扣次数；UI/集成测试。
验收：12MP p95 ≤6s；失败可重试；权限拒绝有出口；不产生长期临时文件。
完成后报告：流程、测试、性能、风险。
```

### S-A4h · WP-21 设置/隐私

```text
你是独立开发会话，负责 WP-21（设置/隐私/诊断）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-21。
只改：Packages/StyleToneUI/Settings/。
依赖：WP-08。

实现：设置页（隐私/诊断/许可/版本/客服）；删除全部本地数据 + 二次确认；订阅不取消说明；诊断无 PII；无障碍/UI 测试。
验收：删除彻底；重启回引导；无账号入口；关闭诊断后不再收集。
完成后报告：页面、测试、风险。
```

### S-A5a · WP-23 边界态

```text
你是独立开发会话，负责 WP-23（错误/离线/边界态）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-23。
只改：Packages/StyleToneUI/ErrorStates/、Tests/EdgeCases/。
依赖：WP-09/17/19。

实现：统一错误展示/恢复动作；错误码映射；离线/权限/存储/低电/中断测试；页面改动以 PR 建议给 owner。
验收：所有错误有文案/动作/诊断码；核心离线可用；无崩溃/卡死。
完成后报告：错误矩阵、测试、风险。
```

### S-A5b · WP-24 性能

```text
你是独立开发会话，负责 WP-24（性能/内存/热）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §10、task-cards.md 的 WP-24。
只改：Tests/Performance/、docs/performance/；优化补丁按模块提 PR 给 owner。
依赖：WP-05/06/07/17。

实现：Instruments 基线；首帧/形变 fps/学习/导出/内存/热；降采样/缓存/并发/取消；低端机降级；性能回归门槛。
验收：目标设备达标；无 Jetsam/严重降频；回归 >10% 阻断；不破坏契约/画质。
完成后报告：基线/优化/风险。
```

### S-A5c · WP-25 黄金图

```text
你是独立开发会话，负责 WP-25（黄金图与质量回归）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §7、task-cards.md 的 WP-25。
只改：Tests/Integration/、Tests/GoldenSupport/。
依赖：WP-04/05/07/12~15。

实现：100 张授权/合成样本；ΔE/SSIM/背景直线/肤色/边缘指标；可视化 diff；CI artifact；质量门（背景<5%、肤色无事故）。
验收：CI 可跑；失败可定位；覆盖 I–VI 肤色/多体型/多人/遮挡/门框地砖；不提交真实用户照片。
完成后报告：样本/指标/失败、风险。
```

### S-B1 · WP-18 风格卡

> Phase B 才启动；Phase A 自用通过后再用。

```text
你是独立开发会话，负责 WP-18（风格卡/档案管理）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-18。
只改：Packages/StyleToneUI/StyleProfile/。
依赖：WP-08/10/11。

实现：风格卡、标签/置信度/样本数、缩略图（如实现）、重命名/删除/重新校准、空状态；调用 StyleProfileStore；无障碍/UI 测试。
验收：删除彻底；重命名持久化；无账号/云文案；无风格时引导校准/自然默认。
完成后报告：页面、测试、风险。
```

### S-B2 · WP-22 引导/示范

> Phase B 才启动。

```text
你是独立开发会话，负责 WP-22（引导/示范/空状态）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-22。
只改：Packages/StyleToneUI/Onboarding/。
依赖：WP-03/08。

实现：欢迎/隐私/示范（授权样片）/跳过/自然默认/空状态；无需登录；无导出计数；UI/无障碍测试。
验收：无照片权限也能看示范；跳过可用自然默认；首次 ≤3 步到编辑。
完成后报告：流程、测试、风险。
```

### S-B3 · WP-27 TestFlight

> Phase B 才启动。

```text
你是独立开发会话，负责 WP-27（Beta/TestFlight/反馈）。工作区：D:\AI\Personalized-ps。

先读：docs/11-personal-first-roadmap.md 的 Phase B、task-cards.md 的 WP-27。
只改：docs/beta/ 与 TestFlight 配置。
依赖：WP-24/25。

执行：组织 10–30 位朋友 TestFlight 4 周；反馈表；崩溃/导出/自然度/持续使用；Top 问题与 Go/No-Go；不收集照片。
验收：朋友 D7 ≥30%；≥5 人愿意持续/付费；无 P0/P1；不上传照片。
完成后报告：样本、指标、Top 问题、Go/No-Go。
```

### S-C1 · WP-20 订阅

> Phase C 才启动；Phase A/B 免费。

```text
你是独立开发会话，负责 WP-20（订阅/付费墙/恢复）。工作区：D:\AI\Personalized-ps。

先读：contracts.md、task-cards.md 的 WP-20。
只改：Packages/StyleToneCommerce/、Packages/StyleToneUI/Paywall/。
依赖：WP-03。

实现：StoreKit 2 仅月付 ¥29.9；前 3 次免费；JWS 校验；恢复/退款/离线宽限；付费墙条款/管理订阅链接；StoreKit 配置测试。
验收：月付/恢复/退款/离线通过；第 4 张触发；关闭可继续编辑；无年付/买断/账号。
完成后报告：商品/测试/风险。
```

### S-C2 · WP-26 无障碍/简中

> Phase C 才启动。

```text
你是独立开发会话，负责 WP-26（无障碍/简中/本地化）。工作区：D:\AI\Personalized-ps。

先读：contracts.md §8、task-cards.md 的 WP-26。
只改：Packages/StyleToneUI/Accessibility/、Localizable.xcstrings；页面修复以 PR 建议给 owner。
依赖：WP-03/22。

执行：VoiceOver、动态字体、对比度、简中/伪本地化审计；ID 补齐；术语表；报告。
验收：核心流程 VoiceOver 可完成；200% 字体不截断；对比度 ≥4.5:1；无英文占位。
完成后报告：审计、修复、风险。
```

### S-C3 · WP-28 App Store/备案

> Phase C 才启动；Phase A/B 不需要。

```text
你是独立开发会话，负责 WP-28（App Store/备案/隐私/提审）。工作区：D:\AI\Personalized-ps。

先读：docs/04-launch-compliance.md、task-cards.md 的 WP-28。
只改：docs/appstore/、隐私政策/商店素材。
依赖：WP-20/27。

执行：App 备案/ICP/软著材料；隐私政策/服务条款；6–8 截图/30s 视频/关键词/描述；隐私标签/出口合规/年龄分级；IAP 审核；提审与回复。
验收：备案号/隐私 URL/支持 URL 可用；描述不夸大；无登录演示；订阅条款清晰。
完成后报告：材料、审核状态、风险。
```

### S-C4 · WP-29 发布

> Phase C 才启动。

```text
你是独立开发会话，负责 WP-29（发布/Runbook/复盘）。工作区：D:\AI\Personalized-ps。

先读：docs/04-launch-compliance.md、task-cards.md 的 WP-29。
只改：docs/release/。
依赖：WP-28。

执行：分阶段发布（1% 起）、监控阈值、暂停/回滚、客服 FAQ、值班、7/30 天复盘；v2.1 决策输入。
验收：发布日按 Runbook；异常可暂停；监控/客服/回滚就绪；复盘有数据。
完成后报告：发布记录、指标、风险。
```

---

## 4. 统一返回格式

每个会话完成后返回：

```text
WP: WP-XX
状态: done / review / blocked
改动: <文件/模块>
测试: <命令> → <结果>
CI: green / pending / failed
验收: <逐条勾选>
风险/未决: <契约/性能/设计>
下一步: <需要谁>
```

---

## 5. 并行执行建议

- **A0–A2 必须串行**：工程骨架 → Core 契约 → 图像/设计/测试。
- **A3 可开 7 个会话**：WP-05/06/07/08/09/10/11；其中 WP-09/10 先用 mock。
- **A4 最多 8 个会话**：WP-12/13/14/15/16/17/19/21；WP-17 可用 mock 先跑。
- **A5 3 个会话**：WP-23/24/25；必须等核心功能稳定。
- **Phase A 自用 4 周后再开 B**；B 通过付费验证后再开 C。
- 每批完成后由项目负责人更新 `index.csv` 的 `status`，不要让多个会话并发改同一行。
