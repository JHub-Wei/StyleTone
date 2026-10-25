# Background protection acceptance (WP-15)

Status:

- **Automated synthetic proxy:** ✅ 100 deterministic cases, see below.
- **Manual review of 100 authorized real photos:** ⏳ **PENDING** — the
  repository deliberately contains no real photos (`Fixtures/samples/` is
  git-ignored and empty; see `Fixtures/README.md`). This is a release-gate item
  for the project owner, not something a CI session can satisfy.

Acceptance from `task-cards.md`:

| Criterion | Target | Current evidence |
|---|---|---|
| Obvious background distortion | `< 5 %` of samples | automated synthetic proxy: see results table |
| Switch effective | on/off changes the result | `BackgroundWarpConstraintTests/testPipelineToggleRunsConstraintOnlyWhenEnabled`, `testRiskAssessmentReportsDisabledSwitch` |
| Slimming effect not significantly reduced | subject retention ≈ 1 | `subjectRetention = 1.0` in the synthetic corpus and the face-pass test |
| Performance acceptable | no frame-budget regression | `PERFORMANCE.md` |
| Analysis module unchanged | no edits | `StyleToneVision` untouched |

## Automated proxy (100 deterministic synthetic cases)

Test: `BackgroundProtectionAcceptanceTests/testHundredSyntheticBackgrounds`.

Corpus: 100 cases, `240 × 180`→`160 × 120` synthetic edge masks, split across
door frames, floor-tile grids and table edges; 50 % include a synthetic subject
mask; four deterministic warp families (horizontal sine, vertical sine,
Gaussian bump, constant shift); amplitude `0.015...0.030`; warp grid `32 × 32`.

The corpus measures the same properties a human would rate:

- **Distortion** if any detected line bends more than `0.005` normalized width
  (`0.5 %` of the frame) **or** a structure core moves more than `0.006`.
- **Subject retention** = displacement ratio inside the subject support.
- **Detection success**: door frame → ≥ 3 lines + ≥ 1 rectangle; tiles → ≥ 4
  lines + ≥ 1 rectangle; table edge → ≥ 1 line.

Recorded result (CI run, fill after green):

| Metric | Value |
|---|---|
| Cases | 100 |
| Obvious distortion | `TBD` |
| Detection failures | `TBD` |
| Cases whose source field visibly bent a line | `TBD` |
| Max line deviation before | `TBD` |
| Max line deviation after | `TBD` |
| Max structure displacement after | `TBD` |
| Min subject retention | `TBD` |
| Mean background retention | `TBD` |

The proxy is **not** a substitute for human review. It cannot judge aesthetics,
text legibility, faces at the person silhouette, or real optical blur.

## Manual review protocol (100 authorized samples)

### Prerequisites

1. Written consent/license for every photo, recorded in
   `Fixtures/samples/manifest.json` (`license`, `authorizedBy`, `addedAt`) as
   described in `Fixtures/README.md`.
2. Photos stay outside version control; never paste them into an issue, CI
   artifact or log.
3. Test matrix: 25 photos per background class:

| Class | Examples | Count |
|---|---|---|
| A. Door/window frame | jambs, lintels, mullions, straight wall corners | 25 |
| B. Tiles | bathroom/kitchen floor, paving, brick grid | 25 |
| C. Table/desk/counter edge | tabletop, railing, shelf, horizon-like edge | 25 |
| D. Text/architecture | signage, posters, bookshelf, building façade | 25 |

Also include at least 10 close-up portraits, 10 half-body, 10 full-body, and
20 photos with a line within 5 % of the face/waist/leg silhouette.

### Steps per photo

1. Open the photo in the editor, choose the default “natural” preset and set
   face/body/leg strengths to the **maximum** the app allows (worst case).
2. Export at 100 % for four configurations:
   - background protection **on**;
   - background protection **off**;
   - the same two with skin retouch off (geometry only).
3. Compare at 100 % and at fit-to-screen. Look at:
   - lines: straight? parallel? corners intact?
   - text/signage: legible, not sheared?
   - subject: same slimming/leg-lengthening as the off case?
   - silhouette: halo, smear, tearing or black gaps?
4. Rate each photo on a 5-point scale:

| Score | Definition |
|---|---|
| 5 | no visible background distortion |
| 4 | only visible at 200 % zoom, not at fit-to-screen |
| 3 | visible at 100 % but not distracting |
| 2 | clearly visible; user would notice |
| 1 | unusable (bent architecture, torn subject silhouette) |

5. Record: `sampleId`, photo class, strength preset, score with protection on,
   score with protection off, whether slimming looks weaker (yes/no), artifacts,
   reviewer initials, date.

### Acceptance gate

- **Obvious distortion rate** = samples scoring `≤ 2` with protection on.
  Must be `< 5 %` (≤ 4 of 100).
- **Switch effectiveness**: for every sample scoring `≤ 3` with protection off,
  protection on must improve the score or keep it equal; count regressions.
  Target: `0` regressions.
- **Slimming preservation**: “slimming looks weaker” must be `0` at the natural
  preset; at maximum strength, a small visible difference is acceptable only if
  the subject outline is still natural (record the count; target `< 10 %`).
- Any score `1` blocks the release and must be filed with a cropped, consented
  example described in text (no photo attached to the ticket).

### Sign-off

| Field | Value |
|---|---|
| Date | |
| App build / commit | |
| Devices | |
| Reviewer | |
| Samples reviewed | /100 |
| Obvious distortion rate | |
| Switch regressions | |
| Weaker-slimming count | |
| Decision | pass / fail / re-run |

## Simulator/SwiftPM limitation

The 100-photo review needs the real app, Vision analysis and real camera files;
it cannot run in the SwiftPM test target. The synthetic corpus is the CI-side
guardrail; the table above must still be completed by a human before the WP is
marked `done`.
