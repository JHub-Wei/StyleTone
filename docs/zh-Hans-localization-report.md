# zh-Hans String Catalog Report

- **Catalog:** `App/Localizable.xcstrings` (branch `a6/zh-hans`, on top of commit `29b7809`)
- **Source language:** `en` — only `zh-Hans` localizations were added; no English localization.
- **Total entries:** **680**
  - **661** keys with an English development fallback (full coverage of `PairingCopy`, `CalibrationCopy`, `EditorCopy`, `ExportCopy`, `SettingsCopy`, `SkinToolsCopy`, `ErrorCopy`, `L10n`/`ShellCopy`).
  - **19** pre-existing A6 entries whose catalog values are identical to their Chinese-only fallbacks.
- **Scope:** Strings, accessibility labels/hints, validation messages, permission/recovery copy, export diagnostics. Placeholders preserved exactly (`%d`, `%@`, `%.1f`, `%d×`, `%d × %d`); no arguments added or removed.

## Validation

```powershell
py -3 -c "import json; d=json.load(open(r'App/Localizable.xcstrings', encoding='utf-8')); print(len(d['strings']))"
# 680
```

Full audit (Python, reading the catalog with a duplicate-key-detecting
`object_pairs_hook`):

- `json.load` succeeds; **0 duplicate keys**; every entry has
  `state = "translated"` and a non-empty value.
- **661/661** English-fallback keys present; **0** placeholder mismatches
  (checked per key against the Swift fallback, including literal `%`).
- **0** values with leftover English sentences outside the allowed tech/brand
  terms; **0** missing keys.
- UTF-8, no BOM, LF line endings, final newline, 2-space JSON.

## Keys found but intentionally not translated

1. **8 Chinese-fallback A6 keys** — their A6 development copy is already
   idiomatic zh-Hans and the UI falls back to it, so adding them would only
   duplicate strings:
   `editor.a6.recalibrateMessage`, `error.a6.photoImport`,
   `error.a6.exportUnavailable`, `error.a6.profileLoad`, `error.a6.profileSave`,
   `settings.a6.deleteHint`, `settings.a6.deleteMessage`,
   `settings.a6.privacyBody`.
   The other 19 A6 keys were already in the catalog and were kept unchanged.
2. **5 `editor.performance.*` proposals** —
   `editor.performance.thermalCritical`, `...thermalSerious`, `...thermalFair`,
   `...lowPower`, `...lowEnd` exist only in `Tests/Performance` as suggested
   keys; no app UI references them.
3. **Non-key hardcoded English** (cannot be localized without source changes,
   which are out of scope):
   - `SettingsLicenseCatalog.standard` displays the license name
     `"Apple system frameworks"`; the source marks it "not localized".
   - Unknown pair-quality reasons are humanized at runtime by
     `PairingCopy.humanizeReason`, so they cannot be looked up in a catalog.
   - English literals in `DesignSystemPreviews.swift` / `SkinToolsPreviews.swift`
     are Xcode previews only and never ship in the app UI.

## Notes

- 24 keys have **different English fallbacks** at different call sites
  (e.g. `pairing.title` is "Pairing" on the real screen but "Add photo pairs" in
  `ShellCopy`; `editor.note`, `editor.export.subtitle`, `settings.deleteDataButton`
  and 11 `error.export.*` keys). Each received one neutral translation that reads
  correctly in both contexts.
- Eight values are intentionally Latin/format-only: `HEIC`, `JPEG`,
  `%.1f MB`, `%.1f MP`, `%d × %d`, `%d×`, `%d / %d`, and the product name
  `StyleTone Pro`. Brand names **私调** / **StyleTone** and technical terms
  (HEIC/JPEG/PNG, iPhone, App Store, Apple ID, SwiftUI/StoreKit) are kept as-is.
- Wording was refined for 9 entries in the working tree (uncommitted):
  `calibration.pairs.note`, `calibration.pairs.subtitle`,
  `editor.section.skinNote`, `editor.warning.lowLight`,
  `error.networkUnavailable.title`, `error.photoPermission.message`,
  `error.purchaseUnavailable.title`, `pairing.quality.warningHint`,
  `settings.privacy.collectBody`.
