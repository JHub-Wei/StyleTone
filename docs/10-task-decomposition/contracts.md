# 共享工程契约（core-v1）

- 版本：v1.0
- 状态：Wave 0 冻结目标
- 适用：所有 WP；修改必须走 CCR
- 关联：[任务分解 README](README.md) · [技术架构](../02-technical-architecture.md)

---

## 1. 工程与工具链

| 项目 | 约定 |
|---|---|
| 仓库 | 单仓库；`App/` + `Packages/` + `Tests/` + `Fixtures/` + `docs/` |
| 工程生成 | **XcodeGen**，`project.yml` 为唯一工程源；禁止手改 `.xcodeproj` |
| 最低系统 | iOS 17.0 |
| 语言 | Swift 6，严格并发 |
| UI | SwiftUI；必要处 UIKit 包装 |
| 模块 | 9 个 SwiftPM library target，单根 `Package.swift`；按域拆分 |
| 依赖 | MVP 不引入第三方运行时依赖；开发工具 SwiftFormat/SwiftLint 可以 |
| 测试 | XCTest；自建图像差异工具，不引入快照库 |
| CI | GitHub Actions macOS runner；`xcodegen` + `xcodebuild test` |
| 构建环境 | **iOS 构建/测试需 macOS + Xcode**；Windows 会话只能写代码/单测并推 CI |

### 1.1 目录

```text
StyleTone/
├── project.yml
├── Package.swift                  # 9 个 library target
├── App/
│   ├── StyleToneApp.swift          # WP-00
│   └── AppShell/                   # WP-03
├── Packages/
│   ├── StyleToneCore/              # WP-01
│   ├── StyleToneImaging/           # WP-02
│   ├── StyleToneVision/            # WP-05
│   ├── StyleToneGeometry/          # WP-06 + 12/13/14/15 子目录
│   ├── StyleToneRetouch/           # WP-07
│   ├── StyleToneLearning/          # WP-11
│   ├── StyleTonePersistence/       # WP-08
│   ├── StyleToneCommerce/          # WP-20
│   └── StyleToneUI/                # WP-03 + 09/10/16/17/18/21/22 子目录
├── Tests/
│   ├── Shared/                     # WP-04
│   ├── GoldenSupport/              # WP-04
│   └── Integration/                # WP-24/25
├── Fixtures/                       # WP-04
├── docs/
└── .github/workflows/ios.yml       # WP-00
```

### 1.2 模块依赖方向

```text
StyleToneCore  ← 所有模块
StyleToneImaging → Core
StyleToneVision → Core, Imaging
StyleToneGeometry → Core, Imaging
StyleToneRetouch → Core, Imaging
StyleToneLearning → Core
StyleTonePersistence → Core
StyleToneCommerce → Core
StyleToneUI → Core, Imaging
App → 所有模块
```

禁止反向依赖；`Core` 不 import SwiftUI/UIKit/Vision/Metal/StoreKit。

---

## 2. 并发与互操作

- 所有跨 actor 传递的类型必须 `Sendable`。
- `ImageAsset` 是不可变值；**禁止原地修改像素**。
- 需要可变缓冲区时，用 `MaskBuffer`/`Data`，不要共享 `CVPixelBuffer`。
- 渲染/学习引擎实现为 `actor` 或不可变 `struct`；不要在主线程做像素处理。
- UI 只调用协议，不直接 import Vision/Metal/CoreImage。
- 所有长任务支持 `Task.cancel()`；取消后抛 `CancellationError`，不写半成品。

---

## 3. Core 类型（冻结）

> 以下为 `StyleToneCore` 的公开契约。WP-01 负责落地；其他 WP 只使用，不修改。

### 3.1 图像

```swift
import CoreGraphics
import ImageIO

public struct PixelSize: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int)
}

/// 不可变图像交换格式。
/// 约定：orientation 已应用；色彩空间由 colorSpace 明确；模块不得隐式改色。
public struct ImageAsset: @unchecked Sendable {
    public let cgImage: CGImage
    public let colorSpace: CGColorSpace
    public let pixelSize: PixelSize
    public init(cgImage: CGImage, colorSpace: CGColorSpace)
}

public struct MaskBuffer: Sendable {
    public let width: Int
    public let height: Int
    /// 8-bit alpha，row-major，长度 = width * height。
    public let bytes: Data
    public init(width: Int, height: Int, bytes: Data) throws
}
```

**像素格式约定（WP-02 负责实现，不得由其他模块假设）**：

- 交换格式：sRGB，8-bit/通道，premultiplied last；方向已应用。
- 渲染内部：WP-02 提供 `ColorPipeline` 转为 linear extended sRGB Float32；算法模块必须通过它转换。
- 导出：sRGB 或 Display P3；默认 sRGB；不得静默改变。
- 禁止在模块间传递 `CIImage`（Core Image 对象不适合跨 actor/长生命周期）。

### 3.2 几何/分析

```swift
public struct NormalizedPoint: Sendable, Hashable {
    public var x: Double // 0...1
    public var y: Double // 0...1
}

public struct NormalizedRect: Sendable, Hashable {
    public var x, y, width, height: Double
}

public enum FaceLandmarkKind: String, Sendable, CaseIterable {
    case faceContour, leftEye, rightEye, leftEyebrow, rightEyebrow
    case nose, outerLips, innerLips, leftPupil, rightPupil
}

public struct FaceObservation: Sendable {
    public let boundingBox: NormalizedRect
    public let landmarks: [FaceLandmarkKind: [NormalizedPoint]]
    public let confidence: Float
}

public enum BodyJointKind: String, Sendable, CaseIterable {
    case neck, leftShoulder, rightShoulder, leftElbow, rightElbow
    case leftWrist, rightWrist, leftHip, rightHip
    case leftKnee, rightKnee, leftAnkle, rightAnkle
}

public struct BodyObservation: Sendable {
    public let joints: [BodyJointKind: NormalizedPoint]
    public let confidence: Float
}

public enum AnalysisWarning: String, Sendable, Codable {
    case noFace, multipleFaces, noBody, occlusion, lowLight, lowConfidence
}

public struct PortraitAnalysis: Sendable {
    public let imageSize: PixelSize
    public let faces: [FaceObservation]
    public let body: BodyObservation?
    public let personMask: MaskBuffer?
    public let skinMask: MaskBuffer?
    public let backgroundEdgeMask: MaskBuffer?
    public let warnings: [AnalysisWarning]
}
```

### 3.3 参数

```swift
public struct ToneParameters: Codable, Sendable, Equatable {
    public var exposure: Double      // -1...1
    public var contrast: Double      // -1...1
    public var highlights: Double    // -1...1
    public var shadows: Double       // -1...1
    public var temperature: Double   // -1...1
    public var tint: Double          // -1...1
    public var saturation: Double    // -1...1
}

public struct SkinParameters: Codable, Sendable, Equatable {
    public var smoothing: Double     // 0...1
    public var evenness: Double      // 0...1
    public var blemish: Double       // 0...1
}

public struct FaceParameters: Codable, Sendable, Equatable {
    public var slim: Double          // 0...1
    public var jaw: Double           // 0...1
}

public struct BodyParameters: Codable, Sendable, Equatable {
    public var arm: Double           // 0...1
    public var waist: Double         // 0...1
    public var leg: Double           // 0...1
    public var legLength: Double     // 1.0...1.15
}

public struct FinishParameters: Codable, Sendable, Equatable {
    public var grain: Double         // 0...1
    public var vignette: Double      // -1...0
}

public enum ConfidenceLevel: String, Codable, Sendable {
    case trial, standard, stable
}

public struct StyleProfile: Codable, Sendable, Equatable {
    public var schemaVersion: Int        // 3
    public var algorithmVersion: String  // st-3.x
    public var pairCount: Int
    public var confidence: ConfidenceLevel
    public var tone: ToneParameters
    public var skin: SkinParameters
    public var face: FaceParameters
    public var body: BodyParameters
    public var finish: FinishParameters
    /// 本地化 key，不是展示文案；UI 负责 String(localized:)。
    public var tags: [String]
    public var updatedAt: Date
}
```

### 3.4 编辑/渲染

```swift
public struct ManualAdjustments: Codable, Sendable, Equatable {
    public var exposure: Double = 0
    public var contrast: Double = 0
    public var temperature: Double = 0
    public var saturation: Double = 0
    public var grain: Double = 0
    public var faceSlim: Double = 0
    public var jaw: Double = 0
    public var arm: Double = 0
    public var waist: Double = 0
    public var leg: Double = 0
    public var legLength: Double = 0
    public var smoothing: Double = 0
    public var evenness: Double = 0
    public var blemish: Double = 0
}

public struct RenderRequest: Sendable {
    public let image: ImageAsset
    public let analysis: PortraitAnalysis
    public let style: StyleProfile
    public let strength: Double                 // 0...1.5
    public let adjustments: ManualAdjustments
    public let backgroundProtection: Bool
    public let blemishPoints: [BlemishPoint]     // 空数组 = 不修复
}

public struct BlemishPoint: Sendable, Equatable {
    public let point: NormalizedPoint
    public let radius: Double // 归一化短边比例，0.005...0.08
}

public struct RenderWarning: Sendable, Equatable {
    public enum Kind: String, Sendable { case noFace, noBody, occlusion, lowConfidence, backgroundRisk }
    public let kind: Kind
    public let messageKey: String
}

public struct RenderOutput: Sendable {
    public let image: ImageAsset
    public let warnings: [RenderWarning]
    public let duration: TimeInterval
}
```

### 3.5 配对/校准

```swift
public enum PairQualityGrade: String, Sendable, Codable { case good, warning, rejected }

public struct PairQuality: Sendable, Codable, Equatable {
    public let grade: PairQualityGrade
    public let reasons: [String] // localization keys
    public let confidence: Float
}

public struct PairSample: Sendable {
    public let id: UUID
    public let original: ImageAsset
    public let edited: ImageAsset
    public let quality: PairQuality
}

public enum CalibrationDimension: String, Codable, Sendable, CaseIterable {
    case skinTone, smoothing, faceSlim, bodySlim, legLength, tone, naturalness
}

public struct CalibrationAnswer: Codable, Sendable, Equatable {
    public let dimension: CalibrationDimension
    public let choseA: Bool
    public let strengthDelta: Double // -1...1
}
```

### 3.6 导出/订阅

```swift
public enum ExportFormat: String, Codable, Sendable { case heic, jpeg }
public struct ExportOptions: Sendable {
    public var format: ExportFormat = .heic
    public var quality: Double = 0.92
    public var stripLocation: Bool = true
}
public struct ExportResult: Sendable {
    public let url: URL
    public let pixelSize: PixelSize
    public let format: ExportFormat
}
public enum PurchaseState: String, Sendable { case unknown, active, expired }
```

---

## 4. 协议（冻结）

```swift
public protocol PortraitAnalyzing: Sendable {
    func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis
}

public protocol PairQualityAnalyzing: Sendable {
    func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality
}

public protocol StyleLearning: Sendable {
    func learn(samples: [PairSample], answers: [CalibrationAnswer]) async throws -> StyleProfile
}

public protocol RetouchRendering: Sendable {
    func retouch(_ image: ImageAsset,
                 analysis: PortraitAnalysis,
                 parameters: SkinParameters) async throws -> ImageAsset
}

public protocol BlemishRemoving: Sendable {
    func removeBlemish(_ image: ImageAsset,
                       at point: BlemishPoint,
                       analysis: PortraitAnalysis) async throws -> ImageAsset
}

public protocol GeometryRendering: Sendable {
    func warp(_ image: ImageAsset,
              analysis: PortraitAnalysis,
              parameters: FaceParameters,
              body: BodyParameters,
              backgroundProtection: Bool) async throws -> ImageAsset
}

public protocol ImageRendering: Sendable {
    func render(_ request: RenderRequest) async throws -> RenderOutput
}

public protocol ImageExporting: Sendable {
    func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult
}

public protocol StyleProfileStore: Sendable {
    func loadActive() async throws -> StyleProfile?
    func save(_ profile: StyleProfile) async throws
    func deleteAll() async throws
}

public protocol PurchaseServicing: Sendable {
    var state: PurchaseState { get async }
    func product() async throws -> PurchaseProduct
    func purchase() async throws -> PurchaseState
    func restore() async throws -> PurchaseState
}

public struct PurchaseProduct: Sendable, Equatable {
    public let id: String
    public let displayPrice: String
    public let period: String
}
```

**规则**：协议一旦 tag `core-v1`，其他 WP 不得修改签名；需要新增能力用新协议/扩展，走 CCR。

### 4.1 Geometry 内部契约（WP-06 冻结）

`StyleToneGeometry` 内部共享以下类型；WP-12/13/14/15 只能实现 pass/constraint，不得改 WP-06 的 `Core/`：

```swift
public struct GeometryParameters: Sendable {
    public var face: FaceParameters
    public var body: BodyParameters
    public var backgroundProtection: Bool
}

/// 规则网格位移场；offsets 长度 = width * height，单位归一化图像坐标。
public struct WarpField: Sendable {
    public var width: Int
    public var height: Int
    public var offsets: [SIMD2<Float>]
}

public protocol GeometryPass: Sendable {
    var identifier: String { get }
    func contribute(to field: inout WarpField,
                    analysis: PortraitAnalysis,
                    parameters: GeometryParameters) throws
}

/// 背景保护等后置约束；在 pass 叠加后执行。
public protocol GeometryConstraint: Sendable {
    var identifier: String { get }
    func constrain(_ field: inout WarpField,
                   analysis: PortraitAnalysis) throws
}
```

- WP-06 拥有 `WarpField`、pass/constraint 的执行顺序和 Metal 网格采样。
- WP-12/13/14 只实现 `GeometryPass`（Face/Body/Legs）。
- WP-15 只实现 `GeometryConstraint`（Background）。
- 执行顺序：Face → Body → Legs → Background constraint → 边界固定/羽化。

---

## 5. 渲染管线顺序（冻结）

```text
1. Decode/Orient（WP-02）
2. Analyze（WP-05）→ PortraitAnalysis
3. Retouch skin/blemish（WP-07）→ ImageAsset
4. Geometry warp face/body/legs（WP-06/12/13/14/15）→ ImageAsset
5. Tone/color/finish（WP-11/17）→ ImageAsset
6. Export（WP-19）
```

- **先 Retouch 后 Geometry**：避免形变后蒙版坐标漂移；皮肤处理基于原图分析。
- 背景保护在 Geometry 内完成。
- Tone 在最后，使用全局参数；不再回写分析。
- `ImageRendering`（WP-17）只负责编排协议，不实现算法。
- 任何顺序变更必须 CCR。

---

## 6. JSON / 持久化契约

- `StyleProfile.schemaVersion = 3`；`algorithmVersion` 形如 `st-3.0.0`。
- JSON 编码使用 `JSONEncoder`，key 顺序稳定（sortedKeys），日期 ISO8601。
- 不允许可选字段缺失导致解码失败；新增字段用默认值/自定义 `init(from:)`。
- 本地文件：
  - `style-profiles/{uuid}.json`
  - `style-thumbnails/{uuid}.jpg`（若实现）
  - SwiftData 存索引/元数据；大 JSON 可存文件。
- 迁移：读取 `schemaVersion`，旧版本迁移；失败时保留原文件并提示重新校准，不崩溃。
- 删除全部数据：清空 SwiftData + 文件 + 缩略图 + 缓存；不涉及账号。

---

## 7. 测试契约

### 7.1 单元测试

- 每个模块 `Tests/<Module>Tests/`。
- 不使用真实用户照片；用 `Fixtures/` 合成图或授权样本。
- 浮点比较用 tolerance；图像比较用 `GoldenSupport`。
- 异步测试用 `async`/`await`；禁止 `sleep` 等时序。
- 性能测试用 `measure`，记录基线；CI 只做阈值检查，不做绝对设备性能。

### 7.2 测试替身

`StyleToneCore` 提供（或 WP-04 提供）：

- `MockPortraitAnalyzer`：返回固定 `PortraitAnalysis` fixture。
- `MockStyleLearner`：返回固定 `StyleProfile`。
- `MockPurchaser`：模拟 active/expired/restore。
- `MockImageAssetFactory`：生成纯色/渐变/棋盘图。

> 其他 WP 不要互相依赖实现；依赖协议 + mock，集成测试在 Wave 3。

### 7.3 构建命令

```bash
# 生成工程
xcodegen generate

# 单模块
swift test --package-path Packages/StyleToneCore
swift test --package-path Packages/StyleToneGeometry

# App + 全部测试（macOS）
xcodebuild -project StyleTone.xcodeproj -scheme StyleTone \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

Windows 会话不能执行 `xcodebuild`；必须推分支走 CI，报告 `CI_PENDING`。

---

## 8. UI/设计契约

- 设计 token 在 `StyleToneUI/DesignSystem`；禁止页面硬编码颜色/字号/间距。
- 默认深色；照片预览背景 18% 灰。
- 四个工具区：`face` / `body` / `skin` / `tone`；每个区 ≤5 个滑杆。
- 滑杆拖动时用低分辨率代理；松手后触发高质量渲染；具体节流由 WP-17 实现。
- 所有可交互元素设置 `accessibilityIdentifier`，命名 `screen.element`：
  - `onboarding.startButton`
  - `pairing.addPairButton`
  - `editor.faceSlimSlider`
  - `paywall.subscribeButton`
- 文案 key 统一：
  - `onboarding.*`, `pairing.*`, `calibration.*`, `editor.*`, `paywall.*`, `settings.*`, `error.*`
- 仅 `zh-Hans` 首发；代码用 `String(localized:)`，不硬编码中文。

---

## 9. 隐私/安全契约

- MVP 无账号、无业务后端、无照片/参数上传。
- 禁止 import 任何网络图片上传 SDK；禁止把 `ImageAsset` 传给网络层。
- 日志使用 `OSLog`，禁止打印照片、文件名、相册 ID、用户输入。
- 临时导出文件放 `tmp/`，成功后删除；失败可重试，不长期保留。
- 本地文件 `NSFileProtectionComplete`；Keychain 只存购买权益缓存。
- 不接入第三方分析 SDK；如需诊断，用本地环形日志/用户主动导出。
- 代码审查必须检查：
  - 是否新增网络请求；
  - 是否把图片写入磁盘/上传；
  - 是否记录 PII；
  - 是否引入未批准依赖。

---

## 10. 性能预算（每个 WP 自查）

| 场景 | 目标 |
|---|---|
| 冷启动 | ≤2s |
| 首帧 | p95 ≤1.5s |
| 形变预览 | ≥30fps（iPhone 13） |
| 滑杆响应 | ≤100ms |
| 5 组学习 | ≤90s |
| 12MP 导出 | p95 ≤6s |
| 预览内存 | ≤300MB |
| 导出内存 | ≤500MB |

WP-24 负责最终测量；其他 WP 在自己的范围内不得明显超预算。

---

## 11. 交付报告模板

每个会话在 PR/消息中返回：

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

## 12. 冻结清单（Wave 0 出口）

- [ ] `core-v1` tag 已打；
- [ ] `StyleProfile` JSON roundtrip 测试通过；
- [ ] `ImageAsset`/`MaskBuffer` 契约测试通过；
- [ ] 所有协议有 mock；
- [ ] 渲染管线顺序写入 README 并被各 WP 引用；
- [ ] 设计 token/路由/无障碍 ID 规范冻结；
- [ ] CI 在 macOS 跑通；
- [ ] 文件所有权表无冲突。
