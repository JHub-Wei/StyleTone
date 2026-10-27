# Edge-case tests (WP-23)

Run:

```bash
swift test --filter EdgeCasesTests
```

The target depends only on `StyleToneUI` + `StyleToneCore` and is registered in
the root `Package.swift` as `EdgeCasesTests`. It contains no fixtures, network
or platform APIs, so it runs on the same macOS CI job as the module tests.

| File | Covers |
|---|---|
| `ErrorMatrixTests` | every kind, copy/action/code invariants, all Core/Export/Pairing mappings, cancellation, unknown/PII |
| `OfflineCapabilityTests` | core-offline contract, network-only store calls, `URLError` offline vs transient, purchase reasons |
| `PermissionAndStorageTests` | Photos denied/restricted/unavailable, Cocoa/POSIX full/read-only/write, storage headroom, path-free source codes |
| `LowPowerAndThermalTests` | low power/battery, thermal, ordering, dedup, notice-only behaviour, clamping |
| `InterruptionTests` | incoming call/Siri/background/memory pressure, idempotent resume, user cancellation, 200 cycles |
| `ErrorPresenterTests` | card/toast/history/dedup/recovery dispatch/logging, 500 rapid presentations |
| `ErrorCopyTests` | key validity, prefix, ASCII fallbacks, no path/URL/PII, diagnostic format |
| `ErrorStateViewTests` | card/modifier construction, accessibility identifiers |
| `ErrorPrivacyAuditTests` | source audit: no platform imports, print logs, `localizedDescription`, CJK or URLs |

`ErrorStateViewTests` and the source audit resolve the repository from
`#filePath`. They `XCTSkip` when the checkout is not available rather than
failing in a copied test bundle.
