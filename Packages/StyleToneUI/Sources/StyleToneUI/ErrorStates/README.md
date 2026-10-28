# ErrorStates (WP-23)

Unified error presentation, recovery actions and diagnostic codes for every
screen. Owner: WP-23. Only this directory and `Tests/EdgeCases/` are changed by
this work package; the page hooks below are proposals for the screen owners.

## Invariants

1. Every visible error has a title, a message, at least one action and a stable
   support code (`ST-<AREA>-<NNN>`).
2. Copy comes from `ErrorCopy` only. Keys use the frozen `error.*` prefix and
   are resolved through `L10n`; the source contains English development
   fallbacks, never Chinese.
3. No value in `ErrorState`, `ErrorRecord` or the diagnostic log contains a file
   path, photo/library identifier, URL, account data or `localizedDescription`.
4. Cancellation (`CancellationError`, `StyleToneError.cancelled`,
   `URLError.cancelled`, a cancelled pairing assessment) is silent: no card, no
   toast, no history entry.
5. Core work is offline: pairing, calibration, learning, editing, rendering,
   export and saving to Photos all report `.available` when offline. Only
   `purchase`, `restorePurchase` and `productLoading` require a connection.
6. An interruption interrupts at most one job, presents one card, and resumes
   exactly once. A user cancellation is never reported as an interruption.

## Error matrix

`Actions` are the default list; `.dismiss` is always last. `notice` states can
still show a full card when the page wants to surface the action.

| Kind | Code | Severity | Actions | Typical source |
|---|---|---|---|---|
| `offline` | `ST-NET-001` | notice | continueOffline, retry, dismiss | Store call with no link |
| `networkUnavailable` | `ST-NET-002` | notice | retry, dismiss | Timeout, DNS, certificate |
| `lowBattery` | `ST-SYS-001` | notice | continueAnyway, dismiss | Low Power Mode / battery |
| `thermalPressure` | `ST-SYS-002` | notice | continueAnyway, dismiss | Serious/critical thermal |
| `interrupted` | `ST-SYS-003` | notice | resume, dismiss | Incoming call, Siri, background |
| `cancelled` | `ST-SYS-004` | notice | — (silent) | User/system cancellation |
| `photoPermissionDenied` | `ST-PERM-001` | recoverable | openSettings, shareInstead, retry, dismiss | Add-only Photos denied |
| `photoPermissionRestricted` | `ST-PERM-002` | recoverable | shareInstead, dismiss | Parental/MDM restriction |
| `photoLibraryUnavailable` | `ST-PERM-003` | recoverable | shareInstead, dismiss | PhotoKit unavailable |
| `storageLow` | `ST-STOR-001` | notice | freeUpSpace, dismiss | Preflight below reserve |
| `storageFull` | `ST-STOR-002` | recoverable | freeUpSpace, retry, dismiss | Cocoa 640 / POSIX ENOSPC |
| `storageUnavailable` | `ST-STOR-003` | recoverable | retry, dismiss | Read-only / permission |
| `storageWriteFailed` | `ST-STOR-004` | recoverable | retry, dismiss | Unknown write / EIO |
| `purchaseUnavailable` | `ST-PUR-001` | recoverable | retry, continueOffline, dismiss | Product load, payment not allowed |
| `purchaseFailed` | `ST-PUR-002` | recoverable | retry, restorePurchase, dismiss | StoreKit purchase error |
| `purchaseVerificationFailed` | `ST-PUR-003` | recoverable | restorePurchase, retry, dismiss | JWS/receipt verification |
| `restoreFailed` | `ST-PUR-004` | recoverable | retry, dismiss | Restore flow |
| `exportUnavailable` | `ST-EXP-001` | recoverable | retry, dismiss | Export engine not wired |
| `exportRenderFailed` | `ST-EXP-002` | recoverable | retry, dismiss | Full-resolution render |
| `exportResolutionMismatch` | `ST-EXP-003` | recoverable | retry, dismiss | Proxy leaked into export |
| `exportEncodeFailed` | `ST-EXP-004` | recoverable | retry, dismiss | Encode/format/output |
| `exportShareUnavailable` | `ST-EXP-005` | recoverable | saveInstead, dismiss | Share sheet unavailable |
| `exportLibrarySaveFailed` | `ST-EXP-006` | recoverable | retry, shareInstead, dismiss | Photos rejected the file |
| `exportQuotaExhausted` | `ST-EXP-007` | recoverable | upgrade, dismiss | Free exports used |
| `exportQuotaUnavailable` | `ST-EXP-008` | recoverable | dismiss | Quota store unreadable |
| `exportInvalidImage` | `ST-EXP-009` | recoverable | chooseAnotherPhoto, dismiss | Invalid export image |
| `invalidImage` | `ST-IMG-001` | recoverable | chooseAnotherPhoto, dismiss | Import/decode |
| `unsupportedFormat` | `ST-IMG-002` | recoverable | chooseAnotherPhoto, dismiss | GIF/TIFF import |
| `imageTooSmall` | `ST-IMG-003` | recoverable | chooseAnotherPhoto, dismiss | Below minimum long edge |
| `analysisFailed` | `ST-ANL-001` | recoverable | retry, dismiss | Vision/quality analysis |
| `noFace` | `ST-ANL-002` | recoverable | useNaturalStyle, chooseAnotherPhoto, dismiss | No face detected |
| `noBody` | `ST-ANL-003` | recoverable | useNaturalStyle, chooseAnotherPhoto, dismiss | No body detected |
| `renderFailed` | `ST-RND-001` | recoverable | reduceStrength, retry, dismiss | Render/retouch/warp |
| `invalidMask` | `ST-RND-002` | recoverable | retry, dismiss | Bad subject mask |
| `invalidState` | `ST-STATE-001` | recoverable | retry, dismiss | Page state conflict |
| `persistenceFailed` | `ST-DATA-001` | recoverable | retry, dismiss | Local store/session |
| `schemaUnsupported` | `ST-DATA-002` | recoverable | recalibrate, dismiss | Newer style schema |
| `unknown` | `ST-UNKNOWN-001` | recoverable | retry, dismiss | Anything else |

## Files

| File | Purpose |
|---|---|
| `ErrorCode.swift` | `ErrorDomain`, `ErrorKind`, `DiagnosticCode`, default recoveries |
| `ErrorCopy.swift` | all `error.*` copy and action titles |
| `ErrorState.swift` | `ErrorState`, `ErrorSeverity`, `ErrorContext`, `RecoveryAction`, accessibility IDs |
| `ErrorMapping.swift` | total mapping from Core/Export/Pairing/network/file errors, plus purchase reasons and page adapters |
| `ErrorConditions.swift` | offline capability matrix, storage headroom, low-power/thermal/storage advisor |
| `ErrorInterruption.swift` | idempotent interruption/resume state machine |
| `ErrorPresenter.swift` | current card, toast, bounded history, recovery dispatch, path-free logging |
| `ErrorStateViews.swift` | shared `ErrorStateCard` and `.errorStatePresentation(_:)` overlay hook |

## Page hooks (PR proposals, not applied)

No page file is modified by WP-23. Each hook is a small PR for the owner.

### App shell (WP-03)

Own one `ErrorPresenter` at the shell level and inject it:

```swift
@State private var errorPresenter = ErrorPresenter()

RootView()
    .errorStatePresentation(errorPresenter)
    .environment(errorPresenter)
```

`ShellToastPresenter` can then forward to the shared presenter, or the shell can
keep a single toast sink and stop scheduling its own error timers.

### Editor (WP-17)

`EditorIssue` already carries an `AppError`; map it without changing the issue
model:

```swift
let state = ErrorState(issue.error, context: .editor)
presenter.present(state)
```

In `onRecovery`, map the canonical action back to `EditorIssue.Recovery`:
`.retry` → `retryRender` or `retryAnalysis` depending on the issue,
`.recalibrate` → `reloadStyle`, `.reduceStrength` → lower the strength or the
relevant slider, `.dismiss` → clear `issue`. Keep the last good preview visible;
the error card must not blank the canvas.

### Export (WP-19)

`ExportFailure` maps one-to-one and keeps the original recovery order:

```swift
if let failure = viewModel.failure {
    ErrorStateCard(state: ErrorState(failure)) { action in
        viewModel.handle(action) // retry / share / save / settings / upgrade / dismiss
    }
}
```

The export view model already deletes staged files on dismiss; keep that
behavior when replacing `ExportFailureCard`.

### Pairing (WP-09)

`PairingImportError`, `PairingSessionStoreError` and `PairingAssessmentFailure`
have adapters. The existing `PairingNoticeBanner` can stay for inline, per-pair
notices; present a shared card only when the error blocks the whole screen
(import failure, corrupted session, save failure). A per-pair failed assessment
is contextual and should remain inline.

### Settings (WP-21)

Deletion reports are partial by design. Map each failed component through
`ErrorState` storage copy and keep "retry" available; never show a success toast
for an incomplete report. The diagnostics log should store `ErrorRecord` codes,
not copy.

### Paywall / StoreKit (WP-20)

Map `StoreKit` and verification failures to `PurchaseFailureReason` before
presenting:

```swift
let state = ErrorMapper.state(for: reason, context: .paywall)
if state.kind == .offline {
    // Offer "Continue editing"; the editor is never blocked by the store.
}
```

Offline purchase/restore must not disable editing, export or saving to Photos.

### Onboarding (WP-22)

Use `ErrorCopy.message(.photoPermissionDenied)` and
`ErrorCopy.actionTitle(.openSettings)` for the permission education card, so the
same wording is used before and after a denial. Do not add an error when the
user declines; the out-of-process picker needs no permission.

## Interruption hook

```swift
let coordinator = InterruptionCoordinator(context: .export)

func startExport() {
    activeJob = coordinator.beginJob()
    // start the task
}

func handleScenePhase(_ phase: ScenePhase) {
    guard phase != .active else { return }
    if let state = coordinator.interrupt(.incomingCall) {
        task?.cancel()
        presenter.present(state)
    }
}

func resumeTapped() {
    guard coordinator.resume() else { return }
    // restart the same snapshot exactly once
}
```

The coordinator is synchronous and idempotent. Interrupting outside a job
returns `nil`; resuming twice returns `true` once. The page owns task
cancellation, so a cancelled render/export never writes a partial result.

## Advisory hook

```swift
let conditions = DeviceConditions(
    isOffline: network.isOffline,
    isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
    batteryLevel: device.batteryLevel,
    thermalState: hostThermalMapping, // map ProcessInfo.ThermalState in the host
    availableDiskBytes: volume.availableCapacity
)

for state in ErrorAdvisor.standard.advisories(for: conditions, context: .editor) {
    presenter.presentOnce(state) // one card per session per code
}
```

`DeviceConditions` is injected, so the advisor itself does not import
`ProcessInfo`, `UIDevice` or `Volume` APIs. Passive offline is intentionally not
an advisory: core work continues, and an offline error appears only when a
network action fails.

## Test checklist

The only shared file touched by WP-23 is the root `Package.swift`: it registers
the `EdgeCasesTests` target at `Tests/EdgeCases`. No app target, product or
screen target is changed.

Automated (`swift test --filter EdgeCasesTests`):

- [x] Every `ErrorKind` has copy, key validity, a unique stable code, actions
      and a primary action; cancellation is silent.
- [x] Every `StyleToneError`, `ExportFailure.Kind`, `ExportLibraryError`,
      `ExportPipelineError`, pairing error and purchase reason maps.
- [x] Cocoa out-of-space, POSIX `ENOSPC`, read-only/permission and unknown-write
      errors map to the right storage kind; a `NSFilePathErrorKey` path never
      appears in a code or copy.
- [x] Photo access denied/restricted/unavailable maps to an action that works.
- [x] Core features are available offline; only store calls require a link.
- [x] Low Power Mode, low battery, serious/critical thermal and low storage
      produce ordered, non-blocking, deduplicated notices.
- [x] Incoming call/Siri/background/memory-pressure interruptions resume once;
      repeated interruption/resume cycles stay consistent.
- [x] Presenter history is bounded and path-free; silent cancellation is not
      surfaced; rapid presentations do not trap.
- [x] Source audit: no platform imports, print logging, `localizedDescription`,
      CJK or URLs in the error unit.

Manual (simulator/device) once pages adopt the hooks:

- [ ] Airplane mode: pair, calibrate, edit, render, export to Photos, share.
      Purchase/restore show offline copy and "Continue editing".
- [ ] Deny add-only Photos permission: export offers Settings and Share
      instead; no crash and no duplicate export count.
- [ ] Fill the simulator volume (`simctl`/disk image): export fails with
      `ST-STOR-002`, staged file is cleaned up, retry after freeing space works.
- [ ] Low Power Mode + 10% battery: one advisory, editing remains available.
- [ ] Incoming call during full-resolution export: one interruption card;
      resume re-runs once; cancel leaves no temp file.
- [ ] Background/foreground during render: no partial image commit, no stuck
      spinner, editor sliders still respond.

## Localization

WP-26 must add these prefixes to `Localizable.xcstrings`:

`error.offline`, `error.networkUnavailable`, `error.lowBattery`,
`error.thermalPressure`, `error.interrupted`, `error.cancelled`,
`error.photoPermission`, `error.photoPermissionRestricted`,
`error.photoLibraryUnavailable`, `error.storageLow`, `error.storageFull`,
`error.storageUnavailable`, `error.storageWrite`, `error.purchaseUnavailable`,
`error.purchase`, `error.purchaseVerification`, `error.restore`,
`error.export.*`, `error.image`, `error.imageTooSmall`, `error.analysis`,
`error.noFace`, `error.noBody`, `error.render`, `error.mask`, `error.state`,
`error.storage`, `error.schema`, `error.unknown`, `error.diagnosticLabel`,
`error.action.*`.

Keys that already exist in `AppError.map` / `ExportCopy` are reused
deliberately; do not rename them during catalog creation.

## Known limits

- Page adoption is a PR for each owner; until then the old inline cards remain
  and the shared presenter is only used by the app shell or new code.
- `ErrorPresenter.perform` is synchronous by design. A page that starts async
  recovery must guard its own button while the task runs; the presenter does not
  invent a second "busy" state.
- The advisor accepts host-provided conditions. Reading battery/thermal/volume
  values, and requesting the optional photo permission, stay the host's job.
- StoreKit is not imported here. WP-20 owns `PurchaseFailureReason` mapping from
  StoreKit errors; the offline rules stay in this directory.
