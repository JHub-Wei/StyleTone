# 在 Windows 上获取 macOS CI 结果

- 日期：2026-10-24
- 适用：当前 WP-00 工程骨架
- 目标：没有 Mac 实机，也能在云端 macOS 上运行 `xcodegen` / `xcodebuild` / `swift test`，拿到构建与测试结果。

> **当前环境实测（2026-10-24）**：Edge 使用本地代理 `127.0.0.1:7890`；Git 直连会超时，配置 `http.proxy/https.proxy` 后已成功执行 `git push -u origin main`。远程 `main` 已存在；CI 结果请在 GitHub Actions 查看。

---

## 1. 推荐方案：GitHub Actions macOS Runner

**可行性：最高；成本：最低；配置：最少。**

- 不需要 Mac。
- 不需要 Apple Developer 账号（模拟器构建/测试不需要签名）。
- 仓库里已经配置好 [.github/workflows/ios.yml](.github/workflows/ios.yml)。
- Windows 上只需要 Git + GitHub 账号。

### 成本

| 仓库类型 | macOS 额度 | 对本项目 |
|---|---|---|
| Public | 标准 runner 通常免费 | 最适合开源/个人项目 |
| Private（Free） | 约 200 macOS 分钟/月（Linux 2,000 分钟 × 10 倍系数） | WP-00 每次约 3–8 分钟，够用 |
| Private（付费） | 按分钟计费 | 频繁跑再升级 |

> 具体额度以 GitHub 当前账单页面为准；macOS runner 的分钟倍率高于 Linux。

### 步骤

1. 在 GitHub 创建一个空仓库（Public 或 Private）。
2. 在 Windows 的 `D:\AI\Personalized-ps` 执行：

```bash
git remote add origin https://github.com/<你的账号>/<仓库名>.git
git push -u origin main
```

3. 打开 GitHub 仓库 → **Actions** → 选择 **iOS CI**。
4. 推送到 `main` 会自动触发；也可以在 Actions 页面点 **Run workflow**（已配置 `workflow_dispatch`）。
5. 打开运行记录：
   - `Generate Xcode project`
   - `Swift package tests`
   - `Build app`
   - `Run app tests`
6. 失败时下载 **xcresult** artifact（保留 7 天），或在日志里看具体错误。

### 如果 `git push` 超时

当前机器实测报错：

```text
fatal: unable to access 'https://github.com/JHub-Wei/StyleTone.git/':
Failed to connect to github.com port 443: Timed out
```

处理顺序：

1. **确认代理/VPN**：浏览器能打开 `https://github.com/JHub-Wei/StyleTone` 不代表 Git 能直连；给 Git 配置代理：

   ```bash
   git config --global http.proxy http://127.0.0.1:<端口>
   git config --global https.proxy http://127.0.0.1:<端口>
   ```

   或只对当前仓库：

   ```bash
   git config http.proxy http://127.0.0.1:<端口>
   git config https.proxy http://127.0.0.1:<端口>
   ```

2. **换网络**：在能访问 GitHub 的电脑/网络执行 `git push -u origin main`。
3. **用 GitHub Web 上传**：私有仓库可以在网页端上传文件，但 47 个文件不推荐；优先命令行。
4. **临时使用其他可达的 Git 托管**：如 Gitee/GitLab，再镜像到 GitHub；会增加同步成本，不推荐作为长期方案。

> 不要在 `git remote` URL 里写 token；使用 Credential Manager/SSH key。私有仓库不要把 token 提交到仓库。

### 这个 workflow 做了什么

```text
checkout
→ 显示 Xcode/Swift/模拟器
→ brew install xcodegen
→ xcodegen generate
→ swift test
→ 自动选择可用的 iPhone 模拟器
→ xcodebuild build
→ xcodebuild test
→ 上传 .xcresult
```

- 模拟器不再写死 `iPhone 16`，而是从 `simctl` 里选第一个可用 iPhone。
- 使用 `CODE_SIGNING_ALLOWED=NO`，不需要证书/描述文件。
- 失败也会上传 `.xcresult`，方便在 Windows 上分析。

### 第一次跑很可能遇到的错误

| 错误 | 处理 |
|---|---|
| `xcodegen: command not found` | workflow 已 `brew install xcodegen`；本地不用装 |
| `Unable to find a destination` | workflow 已自动选模拟器；若仍失败，看 `simctl list` 日志 |
| `No such module StyleTone...` | 检查 `project.yml` 的 package products / `Package.swift` target 名 |
| `Test target ... host application` | 检查 `TEST_HOST`/`BUNDLE_LOADER`；或先去掉 host 改成 logic test |
| `swift test` 失败 | 先看是否是 iOS-only API 在 macOS 编译；骨架阶段只有 Foundation，应该能过 |
| `xcodegen` package path `.` 报错 | 把 `project.yml` 的 `packages.StyleTone.path` 改成绝对/相对正确路径，或拆成独立 package |
| 私有仓库额度不足 | 改 Public，或升级 GitHub 计划 |

> 不要为了让 CI 变绿而删除测试；先修工程配置。

---

## 2. 其他可行方案

| 方案 | 是否需要 Mac | 成本 | 适合 | 注意 |
|---|---|---|---|---|
| **GitHub Actions** | 否 | 免费/低 | CI 构建、测试 | 首选 |
| **Codemagic** | 否 | 有免费额度 | iOS/Flutter CI | 需接仓库；额度以官网为准 |
| **Bitrise** | 否 | 有免费/试用 | 移动 CI | 配置比 GitHub Actions 重 |
| **Azure Pipelines macOS** | 否 | 公共项目有免费额度 | 已有 Azure 生态 | macOS 镜像/Xcode 版本需确认 |
| **Xcode Cloud** | 否 | Apple Developer 包含一定额度 | 已在 App Store Connect 的 App | 需要 Apple Developer，配置偏 Xcode/ASC |
| **MacinCloud / MacStadium / AWS EC2 Mac** | 是（远程 Mac） | 按小时/月 | 需要交互式 Xcode、真机调试 | 比 CI 贵；EC2 Mac 有最短租期 |
| **本地黑苹果/虚拟机** | 是 | 灰色/不合规 | 不建议 | 违反 Apple 许可，稳定性差 |

### 什么时候需要远程 Mac

- 需要**交互式 Xcode**（SwiftUI Preview、Instruments、真机调试）。
- 需要跑 iOS 模拟器手动点 UI。
- 需要配置签名/真机安装/TestFlight。

如果只是“拿 CI 结果”，GitHub Actions 足够，不需要租 Mac。

---

## 3. 后续 TestFlight / 真机

CI 模拟器构建不需要 Apple Developer；但朋友 TestFlight/真机需要：

1. Apple Developer Program（$99/年）。
2. App Store Connect App 记录。
3. 签名证书/Provisioning Profile（可用 Xcode 自动签名，或 CI secrets）。
4. TestFlight 上传（`xcodebuild -exportArchive` + `altool`/`notarytool` 或 Xcode Cloud）。

这些不需要现在做；Phase A 自用可先用 Xcode 真机（需要 Mac）或等 CI 产物。没有 Mac 时，TestFlight 也需要一个 macOS CI 来签名/上传。

---

## 4. 安全与隐私

- CI 只构建代码，不上传照片；测试用合成/授权样本。
- 模拟器构建不需要签名证书；不要把证书/密码提交到仓库。
- 私有仓库注意 Actions 分钟数；Public 仓库注意代码/文档是否可公开。
- `.xcresult` 可能包含测试日志/截图；不要放真实用户照片。

---

## 5. 结论

**用 GitHub Actions 是当前最现实的方案。**

- Windows 上提交/推送；
- GitHub macOS runner 跑 `xcodegen` + `xcodebuild` + `swift test`；
- 在 Actions 页面看日志、下载 `.xcresult`；
- 第一次跑通后，再把 WP-00 标为 `done`，启动 WP-01。

不需要 Mac，也不需要 Apple Developer 账号，就能拿到模拟器构建/测试结果。
