# Sideloadly 真机验证

## 当前状态

- 日期：2026-11-02
- 设备：iPhone15，iOS 27.0.1
- 安装方式：Sideloadly 0.72 + 免费 Apple ID
- Sideloadly：`D:\Tools\Sideloadly\app`
- IPA：`D:\Tools\Sideloadly\calib\StyleTone-unsigned.ipa`
- A6 merge：`de07c35`（PR #26）
- 中文本地化：PR #27，merge `a2dd26c`；`App/Localizable.xcstrings` 680 条 zh-Hans
- Tone/校准修复：PR #28，merge `74d3540`
- App tests：https://github.com/JHub-Wei/StyleTone/actions/runs/41215018035
- 中文本地化 CI：https://github.com/JHub-Wei/StyleTone/actions/runs/41316549195
- Tone/校准 CI：https://github.com/JHub-Wei/StyleTone/actions/runs/41458662966
- Unsigned IPA：https://github.com/JHub-Wei/StyleTone/actions/runs/41464081192
- 结果：中文版安装成功；完成 3 组配对 + A/B 校准后，照片出现可见风格变化。

## Windows 依赖

- Sideloadly 安装在 D 盘。
- Apple Mobile Device Support 与 iTunes 是系统组件，安装器默认写入 `C:\Program Files`，无法可靠改到 D 盘。
- Apple Mobile Device Service 必须运行，Sideloadly 才能识别 iPhone。

## 免费签名限制

- 免费 Apple ID 签名有效期通常为 **7 天**。
- 同时最多 3 个自签 App，每 7 天最多 10 个 App ID。
- 需要开启 iOS Developer Mode，并在首次启动时信任开发者。
- Sideloadly 自带 auto-refresh daemon；保持电脑和手机连接/同网时可自动续签。
- 不能使用 TestFlight，不能分发给朋友。

## 重新构建 IPA

1. GitHub Actions 手动运行 **Unsigned IPA** workflow。
2. 下载 `StyleTone-unsigned-ipa` artifact。
3. 解压得到 `StyleTone-unsigned.ipa`。
4. 在 Sideloadly 中打开 IPA，选择 iPhone，输入 Apple ID，Start。

## 过期/掉签处理

- App 打不开且提示开发者不受信任：重新用 Sideloadly 签名安装，或等待 auto-refresh。
- 7 天内未续签：删除旧 App 后重装；本地 profile 可能丢失，重要成片先保存到相册。
- 不要使用企业证书、共享账号或灰产签名。

## 下一步

- 按 Gate A Smoke 脚本验证：欢迎页 → 配对 → 校准 → 编辑 → 导出 → 设置删除。
- Phase B 保持冻结；仅允许设计/文案准备。
