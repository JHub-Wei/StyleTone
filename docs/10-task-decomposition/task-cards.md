# 工作包任务卡（WP-00 ~ WP-29）

- 版本：v1.0
- 使用方式：每个会话只领取一张卡；先读 [README](README.md) 与 [contracts.md](contracts.md)。
- 每张卡的 `Owns` 是硬边界；`Do not edit` 之外的文件不要改。
- Windows 会话无法跑 iOS 构建：推分支触发 macOS CI，报告 `CI_PENDING`，不要声称测试通过。

**阶段归属（以 index.csv 的 phase 为准）**：

- Phase A 自用：WP-00~11、12~17、19、21、23~25
- Phase B 朋友：WP-18、22、27
- Phase C 商业化：WP-20、26、28、29

> Phase A 不要领取 WP-18/20/22/26/27/28/29；这些是后续阶段。Phase A **必须**包含 WP-09/10/11（配对/校准/风格学习），否则不是同一产品。

---

## WP-00 · 仓库/XcodeGen/模块骨架/CI

- Wave：0｜PD：8｜Owner：iOS-A
- 依赖：无｜解锁：WP-01~04
- Owns：`project.yml`、`Package.swift`、`App/StyleToneApp.swift`、`.github/`、`Makefile`、`.swiftformat`、`.swiftlint.yml`、各模块空壳
- Do not edit：业务实现文件（由后续 WP 创建）

### Goal
建立可重复生成、可编译、可跑测试的 iOS 单仓库；后续所有 WP 不再改工程结构。

### Deliverables
- XcodeGen `project.yml`：App target + 9 个 SwiftPM library target（单根 Package.swift）。
- `Package.swift`：模块 target 与依赖方向按 contracts §1.2。
- App 启动到占位页；Debug/Release 配置；iOS 17。
- GitHub Actions macOS：`xcodegen` → build → `swift test` → simulator test。
- SwiftFormat/SwiftLint 配置；Makefile 快捷命令。
- 模块空壳与 `Tests/<Module>Tests` 占位。

### Acceptance
- `xcodegen generate` 成功；`xcodebuild ... build` 成功。
- 所有模块可 `swift test`；CI 绿灯。
- 无第三方运行时依赖；无网络权限。
- `Core` 不依赖 SwiftUI/UIKit/Vision/Metal/StoreKit。

### Prompt
```text
实现 WP-00。只改 project.yml、Package.swift、App/StyleToneApp.swift、.github、Makefile 和模块空壳。建立 9 个 SPM 模块与 App target，依赖方向严格按 docs/10-task-decomposition/contracts.md §1.2。生成工程后构建通过，CI 在 macOS runner 跑通。不要实现业务功能，不要改 docs/task cards。
```

---

## WP-01 · Core 契约与 JSON schema

- Wave：0｜PD：9｜Owner：iOS-A
- 依赖：WP-00｜解锁：全部模块
- Owns：`Packages/StyleToneCore/`
- Do not edit：其他 Package、App、UI

### Goal
落地 contracts §3–§6 的类型/协议/错误/JSON，打 `core-v1` tag，冻结接口。

### Deliverables
- `PixelSize`、`ImageAsset`、`MaskBuffer`、`PortraitAnalysis`、`StyleProfile`、`RenderRequest` 等。
- 协议：`PortraitAnalyzing`、`StyleLearning`、`RetouchRendering`、`GeometryRendering`、`ImageRendering`、`ImageExporting`、`StyleProfileStore`、`PurchaseServicing`。
- `StyleToneError` 分类；`AppError` 映射；日志/时钟协议。
- `StyleProfile` Codable roundtrip + schemaVersion 3 + 默认值/兼容解码。
- TestSupport：Mock analyzer/learner/purchaser/image factory（可放 Core 的 test target）。
- DocC 注释；`core-v1` tag。

### Acceptance
- 单元测试：JSON roundtrip、错误映射、Mask 长度校验、Sendable 编译。
- 其他模块只 import Core 即可编译占位。
- 无 UI/系统框架依赖（CoreGraphics/ImageIO 除外）。
- 公开 API 无 `fatalError`。

### Prompt
```text
实现 WP-01。严格按 docs/10-task-decomposition/contracts.md §3–§6 落地 StyleToneCore，不要扩展需求。补 Codable roundtrip、MaskBuffer 校验、错误映射测试。提供 Mock 供其他 WP 使用。完成后打 core-v1 tag 并报告公开 API 清单。
```

---

## WP-02 · 图像 I/O/方向/色彩/编码

- Wave：0｜PD：9｜Owner：iOS-A/IMG
- 依赖：WP-00、WP-01｜解锁：WP-05/06/07/19
- Owns：`Packages/StyleToneImaging/`
- Do not edit：Core、UI、Vision/Geometry

### Goal
统一解码、方向、色彩与导出，避免每个模块各自处理颜色空间。

### Deliverables
- `ImageLoader`：HEIC/JPEG/PNG，EXIF orientation，降采样，错误分类。
- `ColorPipeline`：sRGB ↔ linear extended sRGB，P3 输入，色域映射。
- `ImageWriter`：HEIC/JPEG，质量，ICC，去 GPS（EXIF 处理）。
- `ImageExporting` 的文件编码实现（URL 输出；相册保存由 WP-19）。
- 内存/降采样 API：preview 2048、export 分块接口。
- 测试：方向、纯色、渐变、P3/sRGB、损坏文件。

### Acceptance
- 四种格式/方向正确；导出 ICC 正确；无偏色。
- 预览降采样不改变宽高比；错误可恢复。
- 单测覆盖编码/解码/方向/损坏文件。

### Prompt
```text
实现 WP-02。只改 Packages/StyleToneImaging。实现 decode/orient/downsample/color pipeline/encode 与 ImageExporting 文件输出；导出默认去 GPS。补方向、纯色、渐变、损坏文件测试。不要接相册 UI，不要改 Core。
```

---

## WP-03 · 设计系统/App Shell/路由

- Wave：0｜PD：9｜Owner：iOS-B/PD
- 依赖：WP-00、WP-01｜解锁：WP-09/10/16/17/18/20/21/22
- Owns：`Packages/StyleToneUI/DesignSystem/`、`App/AppShell/`
- Do not edit：业务页面、Core、工程文件

### Goal
冻结视觉 token、路由、可访问性 ID 规范，让所有页面能独立开发。

### Deliverables
- Color/Spacing/Typography tokens；暗色；18% 灰照片背景。
- 通用组件：PrimaryButton、SliderRow、SectionHeader、PhotoCanvas、Toast、Loading。
- App Shell：Tab/路由枚举、依赖注入容器（协议注入，不 import 具体实现）。
- 占位页面 + Preview。
- 无障碍 ID 命名规范；动态字体基线。
- 本地化 key 前缀规范。

### Acceptance
- 所有页面可用占位；切换路由不崩。
- 组件支持 Dynamic Type/对比度；无硬编码颜色。
- Snapshot/Preview 可跑；CI 编译。

### Prompt
```text
实现 WP-03。只改 StyleToneUI/DesignSystem 与 App/AppShell。建立 token、通用组件、路由、DI 容器和占位页；定义 accessibilityIdentifier 与本地化 key 规范。不要实现业务逻辑，不要 import Vision/Metal/StoreKit 具体实现。
```

---

## WP-04 · 测试 Harness/合成 Fixtures

- Wave：0｜PD：7｜Owner：QA/iOS-A
- 依赖：WP-00、WP-01｜解锁：所有测试
- Owns：`Tests/Shared/`、`Tests/GoldenSupport/`、`Fixtures/`
- Do not edit：各模块源码

### Goal
提供不依赖真实用户照片的测试基础设施。

### Deliverables
- 合成图生成器：纯色、渐变、棋盘、色卡、噪声、边缘/直线、简单人脸轮廓示意（非真实人像）。
- 授权样本 manifest（真实照片由项目负责人后续放入，不入库）。
- 图像差异工具：逐像素 ΔE/SSIM/阈值报告。
- 共享 Mock：analysis/style/purchase/image。
- 性能测试模板；CI 报告格式。

### Acceptance
- 任意模块可 import `GoldenSupport` 做图像比较。
- 合成图可复现；测试不依赖网络/真实照片。
- 10 个基础 fixtures 通过自检。

### Prompt
```text
实现 WP-04。只改 Tests/Shared、Tests/GoldenSupport、Fixtures。提供合成图生成、图像差异工具、共享 Mock 和性能模板。不要提交真实用户照片；不要改业务模块。
```

---

## WP-05 · 人像分析 + 配对质量

- Wave：1｜PD：13｜Owner：IMG
- 依赖：WP-01、WP-02、WP-04｜解锁：WP-12~15
- Owns：`Packages/StyleToneVision/`
- Do not edit：Core/Geometry/UI

### Goal
把一张人像转为 `PortraitAnalysis`：人脸关键点、人体姿态、人体分割、皮肤/背景边缘蒙版；同时实现 `PairQualityAnalyzing`（相似度/配准/分辨率/结构改动）。

### Deliverables
- `VisionPortraitAnalyzer: PortraitAnalyzing`。
- 人脸关键点（Vision）→ `FaceLandmarkKind` 归一化点。
- 人体姿态 → `BodyJointKind`；人体分割 → `MaskBuffer`。
- 皮肤概率蒙版（人脸椭圆 + 自适应阈值）；背景边缘/直线蒙版。
- 多脸/无人脸/无人体的 warnings；置信度。
- `VisionPairQualityAnalyzer: PairQualityAnalyzing`：FeaturePrint 相似度、配准、分辨率、结构差异。
- 性能：1024px 代理分析 ≤1.5s；不阻塞主线程。
- 20 张授权样本人工验收 + 合成图/坐标转换单测。

### Acceptance
- 输出坐标在 0...1；蒙版尺寸正确；单测覆盖坐标转换/空结果。
- 无人脸/多人不崩溃，返回 warning。
- 配对质量分级（good/warning/rejected）稳定，原因可本地化。
- 不识别身份、不建人脸模板、不写日志。
- 真实样本检测率/蒙版可用性达到人工抽检标准。

### Prompt
```text
实现 WP-05。只改 Packages/StyleToneVision。用 Vision 做人脸关键点/人体姿态/人体分割，输出 contracts 的 PortraitAnalysis 与 MaskBuffer；同时实现 PairQualityAnalyzing（相似度/配准/分辨率/结构差异）。补坐标转换、空输入、多脸、配对分级测试。不要传照片/不建人脸模板/不写 PII 日志。
```

---

## WP-06 · 网格形变 Core

- Wave：1｜PD：10｜Owner：IMG/iOS-A
- 依赖：WP-01、WP-02、WP-04｜解锁：WP-12~15/17
- Owns：`Packages/StyleToneGeometry/Core/`
- Do not edit：Face/Body/Legs/Background 子目录、Core/UI

### Goal
提供可复用的 Metal 网格形变/采样/边界约束，不含具体瘦脸/瘦身业务。

### Deliverables
- 32×32 预览 / 64×64 导出网格；顶点位移场；Metal compute/render。
- 边界固定、双线性采样、边缘羽化；无位移时字节级近似原图。
- `GeometryRendering` 的编排骨架（调用 Face/Body/Legs/Background 的位移贡献）。
- 性能 harness：1080p 30fps 目标。

### Acceptance
- 合成网格图形变正确；无位移时与原图在 ΔE/像素阈值内。
- 边界不露黑边；内存/帧率达预算。
- 单测覆盖位移场/边界/采样；不依赖具体人脸。

### Prompt
```text
实现 WP-06。只改 StyleToneGeometry/Core。实现 Metal 网格/纹理采样/边界约束和 GeometryRendering 骨架；无位移应近似原图。补合成图测试与 1080p 性能测试。不要实现脸/身体具体形态，不要改 Core。
```

---

## WP-07 · 磨皮/匀肤/去瑕疵 Core

- Wave：1｜PD：11｜Owner：IMG
- 依赖：WP-01、WP-02、WP-04｜解锁：WP-16
- Owns：`Packages/StyleToneRetouch/`
- Do not edit：UI/Geometry/Core

### Goal
提供基于蒙版的磨皮/匀肤/点选小范围修复；保留纹理，不做美白。

### Deliverables
- 引导滤波/双边滤波 + 高频分离；按 `smoothing` 强度混合。
- 匀肤：肤色蒙版内低频亮度/颜色均衡；限幅，不改变色相。
- 点选修复：`BlemishRemoving` 输入点/半径 → patch-based inpainting/纹理合成；可撤销由 UI 负责。
- 多肤色安全测试；无蒙版时安全降级。
- 性能：12MP 单次 ≤2s（目标设备）。

### Acceptance
- 合成皮肤纹理测试：强度 0 近似原图；强度高保留边缘。
- 多肤色样本无过亮/偏灰；不执行美白。
- 去瑕疵不改变五官/大结构；空输入/越界安全。

### Prompt
```text
实现 WP-07。只改 Packages/StyleToneRetouch。实现磨皮、匀肤、点选小范围修复，使用 SkinParameters；保留纹理、限幅、不做美白。补合成纹理与多肤色测试，记录性能。不要做 UI。
```

---

## WP-08 · 本地持久化与迁移

- Wave：1｜PD：6｜Owner：iOS-B
- 依赖：WP-01｜解锁：WP-09/10/18/21/22
- Owns：`Packages/StyleTonePersistence/`
- Do not edit：UI/Core

### Goal
本地保存风格/编辑记录；支持 schema 迁移、删除全部数据、无账号。

### Deliverables
- SwiftData models：StyleProfileRecord、EditRecord、PairSessionRecord、QuotaRecord。
- `StyleProfileStore` 实现；JSON 文件 + SwiftData 索引。
- schemaVersion 迁移；损坏恢复；删除全部数据。
- 文件保护；缩略图生命周期（如实现）。
- 单测：CRUD、迁移、损坏、删除。

### Acceptance
- 重启后数据保留；旧 schema 可迁移或明确提示。
- 删除全部数据无残留；不涉及账号/网络。
- 并发读写安全；无主线程 I/O。

### Prompt
```text
实现 WP-08。只改 Packages/StyleTonePersistence。用 SwiftData + 文件实现 StyleProfileStore、迁移、删除全部数据。补 CRUD/迁移/损坏测试。不要做 UI/账号/网络。
```

---

## WP-09 · 配对导入/质量检查 UI

- Wave：1｜PD：7｜Owner：iOS-B/IMG
- 依赖：WP-02、WP-08｜可 mock WP-05｜解锁：WP-10/18
- Owns：`Packages/StyleToneUI/Pairing/`
- Do not edit：Calibration/Editor/DesignSystem

### Goal
让用户完成 3/5/8 组原图/成片选择，看到绿/黄/红质量提示。

### Deliverables
- PHPicker 选择原图/成片；替换/删除；会话持久化。
- 配对卡片；调用 `PairQualityAnalyzing`（Core 已定义；WP-05 实现前用 mock）→ UI 分级与原因。
- 进度 1/3、1/5、1/8；完成/跳过入口。
- 空状态/权限/错误；无障碍 ID；UI 测试。

### Acceptance
- 12 组操作 ≤6 分钟目标可测；替换/删除不丢数据。
- 红色拒绝不进入学习；原因可读。
- 无完整相册权限也能选图；照片不复制到共享容器。

### Prompt
```text
实现 WP-09。只改 StyleToneUI/Pairing。用 PHPicker 做原图/成片配对、替换/删除、会话持久化与质量分级 UI；质量分析先用协议/mock，不要阻塞在 WP-05。补 UI 测试与无障碍 ID。
```

---

## WP-10 · 3/5/8 校准 + AB UI

- Wave：1｜PD：10｜Owner：iOS-B
- 依赖：WP-03、WP-08、WP-09｜可 mock WP-11｜解锁：WP-18
- Owns：`Packages/StyleToneUI/Calibration/`
- Do not edit：Learning/Pairing/Editor

### Goal
3 组配对后可选 6–8 次 AB，生成试用/标准/稳定风格；可跳过。

### Deliverables
- 3/5/8 流程、AB 卡片、进度、取消/恢复。
- 调用 `StyleLearning`（mock 可用）；风格卡预览占位。
- 跳过 → 自然默认；重新校准入口。
- 文案/无障碍/UI 测试。

### Acceptance
- 3 组完成 ≤4 分钟目标；AB 选择可跳过。
- 样本不足/失败有明确出口；不丢已选配对。
- 无登录/账号入口。

### Prompt
```text
实现 WP-10。只改 StyleToneUI/Calibration。做 3/5/8 校准、6–8 次 AB、跳过/自然默认、进度与错误态；StyleLearning 用 mock。补 UI 测试。不要改 Learning/Pairing。
```

---

## WP-11 · 风格学习

- Wave：1｜PD：8｜Owner：IMG
- 依赖：WP-01、WP-04｜解锁：WP-17/18
- Owns：`Packages/StyleToneLearning/`
- Do not edit：UI/Vision/Geometry/Retouch

### Goal
从配对与 AB 估计 `StyleProfile`：色彩/影调 + 磨皮/形变力度 + 置信度。

### Deliverables
- 影调/白平衡/饱和度拟合；肤色保护。
- 磨皮/脸型/身材力度估计（从 mock/真实关键点差）；限幅。
- AB 偏好 → 参数约束；3/5/8 收缩；留出验证；置信度。
- JSON 输出符合 schema 3；算法版本。
- 单测：合成参数、AB 方向、置信度边界。

### Acceptance
- 5 组 ≤90s；输出在安全范围；置信度与样本数/误差一致。
- 3 组强收缩，8 组稳定；异常样本不崩溃。
- 不自动应用高强度形变；不做身份识别。

### Prompt
```text
实现 WP-11。只改 Packages/StyleToneLearning。实现影调/肤色/力度/AB 偏好拟合、3/5/8 收缩、留出验证与置信度，输出 StyleProfile schema 3。用 fixtures/mocks 测试；不要做 UI/视觉检测。
```

---

## WP-12 · 瘦脸/下颌工具

- Wave：2｜PD：8｜Owner：IMG/iOS-A
- 依赖：WP-05、WP-06｜解锁：WP-17
- Owns：`Packages/StyleToneGeometry/Face/`
- Do not edit：Core/Body/Legs/Background/UI

### Goal
实现瘦脸/下颌位移场，保护五官与发际线。

### Deliverables
- `FaceWarpContributor`：实现 `GeometryPass`（contracts §4.1），基于人脸关键点的脸颊/下颌位移。
- 五官/牙齿保护；左右脸对称；强度限幅。
- 与 WP-06 网格接口对接；单元/合成测试。
- 多脸按面积处理；失败 warning。

### Acceptance
- 合成关键点位移正确；强强度不吞五官。
- 背景保护由 WP-15 接入；本 WP 不直接实现背景。
- 性能满足 30fps 贡献。

### Prompt
```text
实现 WP-12。只改 StyleToneGeometry/Face。基于人脸关键点实现瘦脸/下颌位移贡献，保护五官/发际线，强度限幅，接入 WP-06 网格接口。用合成关键点测试。不要改 Core/其他子目录/UI。
```

---

## WP-13 · 瘦手臂/腰工具

- Wave：2｜PD：7｜Owner：IMG/iOS-A
- 依赖：WP-05、WP-06｜解锁：WP-17
- Owns：`Packages/StyleToneGeometry/Body/`
- Do not edit：Core/Face/Legs/Background/UI

### Goal
实现手臂/腰部轮廓内收；保护手、衣物、背景。

### Deliverables
- 基于人体姿态/分割的 `GeometryPass` 位移贡献；左右/多人处理。
- 遮挡/低置信度 warning；强度限幅。
- 合成/样本测试；性能。

### Acceptance
- 轮廓内收自然；无人体/遮挡安全跳过。
- 不改变背景直线（交给 WP-15 叠加）。
- 不识别身份/不做身体测量。

### Prompt
```text
实现 WP-13。只改 StyleToneGeometry/Body。基于人体姿态/分割实现手臂与腰部内收位移，处理多人/遮挡/低置信度，强度限幅。补合成测试。不要改 Core/UI。
```

---

## WP-14 · 瘦腿/拉长工具

- Wave：2｜PD：6｜Owner：IMG/iOS-A
- 依赖：WP-05、WP-06｜解锁：WP-17
- Owns：`Packages/StyleToneGeometry/Legs/`
- Do not edit：Core/Face/Body/Background/UI

### Goal
实现瘦腿与 1.00–1.15 倍拉长；保护脚/鞋、边缘延展。

### Deliverables
- 髋/膝/踝锚点位移；实现 `GeometryPass` 的纵向非线性拉伸。
- 脚部/鞋不裁切；边缘填充/镜像；强度限幅。
- 合成测试/性能。

### Acceptance
- 拉长不产生黑边/明显拉伸纹理；脚部完整。
- 无人体/低置信度安全跳过。
- 不改变无关背景（由 WP-15 保护）。

### Prompt
```text
实现 WP-14。只改 StyleToneGeometry/Legs。实现瘦腿与 1.00–1.15 拉长，使用髋/膝/踝锚点、脚部保护、边缘延展；补合成测试。不要改 Core/UI。
```

---

## WP-15 · 背景保护

- Wave：2｜PD：8｜Owner：IMG/iOS-A
- 依赖：WP-05、WP-06｜解锁：WP-17
- Owns：`Packages/StyleToneGeometry/Background/`
- Do not edit：Core/Face/Body/Legs/UI

### Goal
在形变时保护直线、边缘、文字、建筑结构，降低“背景拉歪”。

### Deliverables
- 边缘/直线/矩形检测 → 实现 `GeometryConstraint` 的保护权重图。
- 位移惩罚/边界约束；与 Face/Body/Legs 贡献叠加。
- 开关；关闭时 warning；质量指标。
- 合成门框/地砖/桌沿测试；100 张真实样本人工验收（授权）。

### Acceptance
- 明显背景扭曲样本 <5%；开关有效。
- 不显著降低瘦身效果；性能可接受。
- 不修改分析模块。

### Prompt
```text
实现 WP-15。只改 StyleToneGeometry/Background。用边缘/直线检测生成保护权重，对位移场施加惩罚/边界约束，输出 warning。用门框/地砖/桌沿合成图测试，并记录人工样本结果。不要改 Core/UI。
```

---

## WP-16 · 皮肤工具 UI + 点选去瑕疵

- Wave：2｜PD：10｜Owner：iOS-B/IMG
- 依赖：WP-03、WP-07｜解锁：WP-17
- Owns：`Packages/StyleToneUI/SkinTools/`
- Do not edit：Retouch Core/Editor/DesignSystem

### Goal
把磨皮/匀肤/点选修复接入编辑器皮肤区。

### Deliverables
- 磨皮/匀肤滑杆；点选修复交互（放大、点选、半径、撤销），通过 `BlemishRemoving` 落点。
- 调用 `RetouchRendering`；取消/错误态。
- 无障碍 ID；UI 测试。

### Acceptance
- 强度 0 回原图；点选可撤销；失败不破坏原图。
- 不改变五官/大结构；无脸时隐藏/禁用。
- 与 WP-17 编辑器状态兼容。

### Prompt
```text
实现 WP-16。只改 StyleToneUI/SkinTools。做磨皮/匀肤滑杆与点选修复交互，调用 RetouchRendering；支持撤销/错误态/无障碍。补 UI 测试。不要改 Retouch Core/Editor。
```

---

## WP-17 · 编辑器状态/预览/撤销

- Wave：2｜PD：12｜Owner：iOS-A
- 依赖：WP-03、WP-06、WP-07、WP-11｜可 mock｜解锁：WP-19/23/24
- Owns：`Packages/StyleToneUI/Editor/`
- Do not edit：Face/Body/Legs/Background/SkinTools

> Phase A 可先用静态 `StyleProfile`（自然默认/手动默认）代替 WP-11；WP-11 到 Phase B 再接。

### Goal
编排分析→修饰→形变→影调→导出，提供四区工具、强度、对比、撤销。

### Deliverables
- `EditorViewModel`：状态/动作/撤销栈 ≥20 步。
- 四个 Tab：脸型/身材/皮肤/影调；滑杆绑定。
- 预览管线：拖动低分辨率，松手高质量；取消旧渲染。
- 长按/分屏/缩放；自然档/总强度；背景保护开关。
- 维护 `blemishPoints`，传入 `RenderRequest`；场景 warnings；性能降级。

### Acceptance
- 无操作时原图/导出一致；拖动不卡死；取消不写半成品。
- 20 步撤销；重置；错误可恢复。
- 与各引擎协议/mock 可独立运行。

### Prompt
```text
实现 WP-17。只改 StyleToneUI/Editor。用协议编排分析/修饰/形变/影调，做四区工具、强度、对比、20 步撤销、预览降级与场景 warning。用 mock 引擎补 UI/集成测试。不要改各算法子目录。
```

---

## WP-18 · 风格卡/档案管理

- Wave：2｜PD：6｜Owner：iOS-B
- 依赖：WP-08、WP-10、WP-11｜解锁：WP-22
- Owns：`Packages/StyleToneUI/StyleProfile/`
- Do not edit：Calibration/Learning/Persistence

### Goal
展示风格卡、置信度、标签；支持重命名/删除/重新校准。

### Deliverables
- 风格卡 UI；标签/置信度/样本数；缩略图（如实现）。
- 重命名/删除/重新校准；空状态。
- 本地 store 调用；无障碍/UI 测试。

### Acceptance
- 删除彻底；重命名持久化；重新校准入口正确。
- 无账号/云同步文案。
- 无风格时引导校准/自然默认。

### Prompt
```text
实现 WP-18。只改 StyleToneUI/StyleProfile。做风格卡、标签/置信度、重命名/删除/重新校准与空状态，调用 StyleProfileStore。补 UI 测试。不要改 Calibration/Learning。
```

---

## WP-19 · 导出/相册/分享

- Wave：2｜PD：8｜Owner：iOS-A
- 依赖：WP-02、WP-17｜解锁：WP-23/24
- Owns：`Packages/StyleToneUI/Export/`
- Do not edit：Imaging/Editor

### Goal
全分辨率导出到相册/分享，默认去 GPS，处理权限/失败/进度。

### Deliverables
- 导出流程 + 进度/取消/重试；PhotoKit add-only。
- 系统分享；文件与相册一致；格式/质量选项（HEIC/JPEG）。
- 元数据去 GPS；失败不扣免费次数。
- UI/集成测试（PhotoKit mock）。

### Acceptance
- 12MP p95 ≤6s；失败可重试；权限拒绝有出口。
- 保存/分享成功计数；取消不计。
- 不产生长期临时文件。

### Prompt
```text
实现 WP-19。只改 StyleToneUI/Export。接 ImageExporting 做全分辨率导出、PhotoKit add-only、系统分享、去 GPS、进度/取消/重试。补权限与失败测试。不要改 Imaging/Editor。
```

---

## WP-20 · 订阅/付费墙/恢复

- Wave：2｜PD：8｜Owner：iOS-B
- 依赖：WP-03｜解锁：WP-27/28
- Owns：`Packages/StyleToneCommerce/`、`Packages/StyleToneUI/Paywall/`
- Do not edit：Core/其他 UI

### Goal
仅月付 ¥29.9；前 3 次免费；StoreKit 2 本地校验；恢复购买。

### Deliverables
- Product 加载/购买/交易监听；JWS 校验；离线宽限。
- 免费额度（成功导出计数，失败不计）。
- 付费墙 UI/条款/恢复/管理订阅链接。
- StoreKit Configuration 测试；UI 测试。

### Acceptance
- 月付购买/恢复/退款/离线路径通过。
- 第 4 次导出前触发；关闭可继续编辑。
- 无年付/买断/账号；价格展示以 StoreKit 为准。

### Prompt
```text
实现 WP-20。只改 StyleToneCommerce 与 StyleToneUI/Paywall。StoreKit 2 仅月付 ¥29.9、前 3 次免费、恢复购买、JWS 校验、离线宽限；付费墙条款/管理订阅链接。补 StoreKit 配置测试。不要做年付/买断/账号。
```

---

## WP-21 · 设置/隐私/诊断

- Wave：2｜PD：6｜Owner：iOS-B
- 依赖：WP-08｜解锁：WP-26
- Owns：`Packages/StyleToneUI/Settings/`
- Do not edit：Persistence/Core

### Goal
设置、隐私说明、删除本地数据、诊断开关、帮助。

### Deliverables
- 设置页：隐私、诊断、许可、版本、客服。
- 删除全部本地数据（二次确认）；订阅不取消说明。
- 诊断只本地/无 PII；可复制诊断码。
- UI/无障碍测试。

### Acceptance
- 删除彻底；重启回到引导；无账号入口。
- 无照片/文件名日志；订阅说明准确。
- 诊断关闭后不再收集。

### Prompt
```text
实现 WP-21。只改 StyleToneUI/Settings。做隐私/诊断/许可/版本/客服、删除全部本地数据与确认；说明订阅不自动取消。补 UI 与删除测试。不要加账号/云。
```

---

## WP-22 · 引导/示范/空状态

- Wave：2｜PD：8｜Owner：iOS-B/PD
- 依赖：WP-03、WP-08｜解锁：WP-26
- Owns：`Packages/StyleToneUI/Onboarding/`
- Do not edit：Calibration/Pairing/Editor

### Goal
无需登录完成首次体验：欢迎、隐私、示范、跳过、空状态。

### Deliverables
- 欢迎/隐私页；示范素材（授权）自然/标准；开始校准/自然默认。
- 权限教育、空状态、错误出口。
- 本地模式说明；无登录入口。
- UI/无障碍测试。

### Acceptance
- 无照片权限也能看示范；不产生导出计数。
- 跳过校准可用自然默认；文案不误导。
- 首次流程 ≤3 步到编辑。

### Prompt
```text
实现 WP-22。只改 StyleToneUI/Onboarding。做欢迎/隐私/示范/跳过/空状态，强调无需登录与本地处理。用授权样片；补 UI 测试。不要加登录/账号。
```

---

## WP-23 · 错误/离线/边界态

- Wave：3｜PD：7｜Owner：QA/iOS-B
- 依赖：WP-09、WP-17、WP-19｜解锁：WP-27
- Owns：`Packages/StyleToneUI/ErrorStates/`、`Tests/EdgeCases/`
- Do not edit：页面实现（通过 PR 提议）

### Goal
统一错误文案/恢复动作；覆盖离线、权限、存储、低电、中断。

### Deliverables
- ErrorPresenter/Toast/Recovery；错误码映射。
- 离线/StoreKit 失败/相册拒绝/存储不足/低电/来电中断测试。
- 页面钩子（由页面 owner 合入）；测试清单。

### Acceptance
- 所有错误有用户文案/动作/诊断码；不泄露 PII。
- 核心功能离线可用；失败可重试。
- 无崩溃/卡死。

### Prompt
```text
实现 WP-23。只改 StyleToneUI/ErrorStates 与 Tests/EdgeCases。统一错误展示/恢复动作，覆盖离线/权限/存储/低电/中断；页面改动以 PR 建议给 owner。补边界测试。
```

---

## WP-24 · 性能/内存/热优化

- Wave：3｜PD：11｜Owner：iOS-A/QA
- 依赖：WP-05/06/07/17｜解锁：WP-27
- Owns：`Tests/Performance/`、`docs/performance/`
- Do not edit：算法/页面（优化 PR 需 owner 审）

### Goal
达到预览 30fps、首帧 1.5s、导出 6s、内存预算。

### Deliverables
- Instruments 基线；降采样/缓存/并发/取消优化。
- 低端机降级（网格/代理/分辨率）；低电/热提示。
- 性能回归门槛；报告。
- 优化 PR 分派给模块 owner。

### Acceptance
- 目标设备达标；无 Jetsam/严重降频。
- 性能回归 >10% 阻断。
- 优化不破坏画质/契约。

### Prompt
```text
实现 WP-24。只改 Tests/Performance 与 docs/performance，优化补丁按模块提 PR 给 owner。测首帧/形变 fps/学习/导出/内存/热，建立降级策略与回归门槛。不要擅自改 Core 契约。
```

---

## WP-25 · 黄金图与质量回归

- Wave：3｜PD：12｜Owner：QA/IMG
- 依赖：WP-04/05/07/12~15｜解锁：WP-27
- Owns：`Tests/Integration/`、`Tests/GoldenSupport/`
- Do not edit：算法模块（测试失败提 issue）

### Goal
100 张背景/肤色/体型回归；防止算法越改越差。

### Deliverables
- 授权样本集（不入库原图；本地/CI 加密）；合成图集。
- 指标：ΔE00/SSIM/背景直线/肤色区域/边缘；阈值。
- 失败报告：可视化 diff；CI artifact。
- 质量门：背景 <5%、肤色无事故、盲测 ≥65%（人工）。

### Acceptance
- CI 可跑黄金图；失败可定位。
- 覆盖 I–VI 肤色/多体型/多人/遮挡/门框地砖。
- 不把真实用户照片提交到仓库。

### Prompt
```text
实现 WP-25。只改 Tests/Integration 与 GoldenSupport。建立 100 张授权/合成样本的回归、指标与可视化报告；覆盖背景/肤色/体型。不要改算法模块；失败提 issue。
```

---

## WP-26 · 无障碍/简中/本地化

- Wave：3｜PD：5｜Owner：QA/PD
- 依赖：WP-03、WP-22｜解锁：WP-27
- Owns：`Packages/StyleToneUI/Accessibility/`、`Localizable.xcstrings`
- Do not edit：页面实现（PR 建议）

### Goal
VoiceOver 全流程、动态字体、对比度、简中无截断。

### Deliverables
- Accessibility audit；ID 补齐；VoiceOver 标签。
- 最大动态字体布局；对比度修复。
- 简中字符串/术语表；伪本地化测试。
- 报告。

### Acceptance
- 核心流程 VoiceOver 可完成；200% 字体不截断。
- 对比度 ≥4.5:1；无英文占位。
- 不改变业务逻辑。

### Prompt
```text
实现 WP-26。只改 StyleToneUI/Accessibility 与 Localizable.xcstrings；页面修复以 PR 建议给 owner。做 VoiceOver/动态字体/对比度/简中审计与伪本地化测试。补报告。
```

---

## WP-27 · Beta/TestFlight/反馈

- Wave：3｜PD：8｜Owner：PD/QA
- 依赖：WP-24、WP-25｜解锁：WP-28
- Owns：`docs/beta/`、TestFlight 配置
- Do not edit：代码（缺陷交 owner）

### Goal
100 人外部 Beta 2 周；收集稳定性/自然度/付费反馈。

### Deliverables
- Beta 构建/分组/邀请；反馈表；崩溃/导出/订阅指标。
- Top 问题清单与优先级；Go/No-Go 输入。
- 隐私/素材授权检查。

### Acceptance
- 100 人/2 周；崩溃自由 ≥99%；无 P0/P1。
- 反馈覆盖背景/肤色/自然度/付费。
- 不在 Beta 收集照片。

### Prompt
```text
执行 WP-27。只改 docs/beta 与 TestFlight 配置。组织 100 人 2 周 Beta，收集稳定性/自然度/付费反馈，输出 Top 问题与 Go/No-Go 建议。不要改业务代码；缺陷交 owner。
```

---

## WP-28 · App Store/备案/隐私/提审

- Wave：3｜PD：8｜Owner：PD/法务
- 依赖：WP-20、WP-27｜解锁：WP-29
- Owns：`docs/appstore/`、隐私政策/商店素材
- Do not edit：代码（审核问题交 owner）

### Goal
完成 App 备案、隐私政策、商店素材、IAP 审核、提审。

### Deliverables
- App 备案/ICP/软著材料；隐私政策/服务条款。
- 6–8 截图/30s 视频/关键词/描述；审核说明。
- 隐私标签/出口合规/年龄分级；IAP 审核。
- 提审与回复记录。

### Acceptance
- 备案号/隐私 URL/支持 URL 可用。
- 商店描述不夸大；无登录演示路径。
- 订阅条款/恢复/取消清晰。

### Prompt
```text
执行 WP-28。只改 docs/appstore 与合规素材。完成 App 备案/隐私政策/商店素材/隐私标签/IAP 审核/提审与回复。不要改代码；审核缺陷交 owner。
```

---

## WP-29 · 发布/Runbook/复盘

- Wave：3｜PD：5｜Owner：PD/iOS-A
- 依赖：WP-28｜解锁：上线
- Owns：`docs/release/`
- Do not edit：代码（热修交 owner）

### Goal
分阶段发布、监控、热修、复盘。

### Deliverables
- 发布 Runbook：1% 起、监控阈值、暂停/回滚。
- 客服 FAQ/回复模板；值班表。
- 发布后 7/30 天复盘；v2.1 决策输入。

### Acceptance
- 发布日按 Runbook 执行；异常可暂停。
- 监控/客服/回滚就绪。
- 复盘有数据/结论。

### Prompt
```text
执行 WP-29。只改 docs/release。编写并执行分阶段发布 Runbook、监控阈值、客服 FAQ、回滚/热修流程与复盘模板。不要改代码；问题交 owner。
```

---

## 附：领取顺序速查

```text
Wave 0：WP-00 → WP-01 → (WP-02 || WP-03 || WP-04)
Wave 1：WP-05 || WP-06 || WP-07 || WP-08 || WP-09 || WP-10 || WP-11
Wave 2：WP-12 || WP-13 || WP-14 || WP-15 || WP-16 || WP-17 || WP-18 || WP-19 || WP-20 || WP-21 || WP-22
Wave 3：WP-23 || WP-24 || WP-25 || WP-26 → WP-27 → WP-28 → WP-29
```

> 标 `||` 的可并行；同一模块的子目录（Geometry Face/Body/Legs/Background）可并行，但 `Core/` 只能 WP-06 改。任何共享契约变更走 CCR。
