# WP-10 · Calibration (3/5/8 + AB)

This directory is the ownership boundary for the calibration work package.
SwiftPM requires source files under `Sources/` and tests under `Tests/`, so the
compiled implementation lives at:

- `Packages/StyleToneUI/Sources/StyleToneUI/Calibration/`
- `Packages/StyleToneUI/Tests/StyleToneUITests/Calibration/`

Nothing outside the calibration feature was changed.

## Flow

1. **Pairs** — uses only good/warning `PairSample` values. Rejected pairs stay
   visible but are not used. The user picks 3, 5 or 8 pairs; three is the
   default entry point. The four-minute target is `CalibrationLimits.pairStageTargetSeconds`.
2. **AB** — eight deterministic cards, with a finish action after six. Every
   card can be skipped. "Skip AB and use natural default" exits without calling
   the learner.
3. **Learning** — `CalibrationViewModel` calls the injected `StyleLearning`,
   then saves through the injected `StyleProfileStore`.
4. **Result** — placeholder style card, confidence, pair count, tag chips,
   use-style and recalibrate actions.

## Integration

```swift
let model = CalibrationViewModel(
    samples: pairsFromWP09,
    learner: realLearner,          // WP-11; use CalibrationMockStyleLearning until then
    profileStore: realProfileStore, // WP-08
    progressStore: FileCalibrationProgressStore()
)

CalibrationView(
    model: model,
    onAddPairs: { /* open WP-09 pairing */ },
    onOpenStyleCard: { profile in /* WP-18 */ },
    onContinue: { profile in /* editor */ },
    onClose: { /* dismiss */ }
)
```

- The draft JSON stores pair UUIDs, answers and the optional profile only. It
  never copies photographs. WP-09 remains the owner of the images.
- `FileCalibrationProgressStore` writes under Application Support. The file
  protection/retention policy remains WP-08's responsibility.
- There is no login, account or purchase entry in this feature. All copy and
  accessibility identifiers are local to `Calibration/`.

## Tests

`swift test --filter Calibration` covers the 3/5/8 tiers, rejected pairs,
6–8 AB exits, skip/natural-default, cancel/restore, failure retention, the mock
learner, draft file round-trip/corruption, copy keys, accessibility IDs and the
no-account audit. The package has no XCUITest target; these are SwiftPM
behavior/copy tests rather than simulator UI tests.
