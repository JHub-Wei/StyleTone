import StyleToneUI

/// App-level copy for the Phase A self-use flow.
///
/// The repository has no zh-Hans string catalog yet (WP-26 owns it), so these
/// resolve through the frozen `L10n` key mechanism and fall back to the Phase A
/// Chinese copy. Keys stay inside the allowed prefixes from `contracts.md` §8;
/// the `a6` segment keeps them clear of the future WP-22/WP-21 keys.
enum A6Copy {
    private static func resolve(_ key: String, _ fallback: String) -> String {
        L10n.resolve(LocalizationKey(key), fallback: fallback)
    }

    // MARK: Launch / welcome

    static let launching = resolve("shell.a6.launching", "正在读取本机风格…")
    static let welcomeTitle = resolve("onboarding.a6.title", "欢迎使用私调")
    static let welcomeSubtitle = resolve(
        "onboarding.a6.subtitle",
        "用几组原图与成片，让私调学习你的修图风格。所有照片与风格只留在本机。"
    )
    static let welcomeNote = resolve(
        "onboarding.a6.note",
        "不需要账号，也不会上传。可以先导入配对，或直接使用自然默认，之后再校准。"
    )
    static let startPairingButton = resolve("onboarding.a6.startPairing", "开始导入配对")
    static let naturalDefaultButton = resolve("onboarding.a6.naturalDefault", "使用自然默认")

    // MARK: Tabs

    static let editorTab = resolve("shell.a6.tab.editor", "编辑")
    static let settingsTab = resolve("shell.a6.tab.settings", "设置")

    // MARK: Editor host

    static let importingPhoto = resolve("editor.a6.importing", "正在载入照片…")
    static let photoImportFailed = resolve(
        "error.a6.photoImport",
        "无法读取这张照片，请换一张再试。"
    )
    static let recalibrateTitle = resolve("editor.a6.recalibrateTitle", "重新校准风格")
    static let recalibrateMessage = resolve(
        "editor.a6.recalibrateMessage",
        "重新校准会覆盖当前的风格档案。已有照片仍可在编辑器中继续调整。"
    )
    static let recalibrateStart = resolve("editor.a6.recalibrateStart", "开始重新配对")
    static let exportUnavailable = resolve(
        "error.a6.exportUnavailable",
        "当前的编辑结果无法导出，请稍后再试。"
    )

    // MARK: Settings fallback

    static let settingsTitle = resolve("shell.a6.tab.settings", "设置")
    static let privacyTitle = resolve("settings.a6.privacyTitle", "本地数据与隐私")
    static let privacyBody = resolve(
        "settings.a6.privacyBody",
        "照片、编辑与风格只保存在这台设备上；不需要账号，也不会上传。"
    )
    static let deleteDataButton = resolve("settings.a6.deleteData", "删除全部本地数据")
    static let deleteHint = resolve(
        "settings.a6.deleteHint",
        "删除后风格档案、校准草稿和本地设置都会被清除，无法恢复。"
    )
    static let deleteTitle = resolve("settings.a6.deleteTitle", "删除全部本地数据？")
    static let deleteMessage = resolve(
        "settings.a6.deleteMessage",
        "这个操作会清除本机的风格、配对与校准数据，且无法撤销。"
    )
    static let deleteConfirmButton = resolve("settings.a6.deleteConfirm", "删除")
    static let deleteFailed = resolve("settings.a6.deleteFailed", "删除没有完成，请重试。")

    // MARK: Shared

    static let alertTitle = resolve("error.a6.alertTitle", "提示")
    static let okButton = resolve("common.a6.ok", "好")
    static let cancelButton = resolve("common.a6.cancel", "取消")

    // MARK: Persistence errors

    static let profileLoadFailed = resolve(
        "error.a6.profileLoad",
        "读取本机风格失败，将使用自然默认。"
    )
    static let profileSaveFailed = resolve(
        "error.a6.profileSave",
        "保存风格失败，请稍后重试。"
    )
}
