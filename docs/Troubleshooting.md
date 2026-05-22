# Troubleshooting & active goals

Companion to [VideoOrientation.md](VideoOrientation.md) (decode/export) and [AGENTS.md](../AGENTS.md).

## Reading analysis logs (no performance impact)

Saved-video analysis uses unified logging only (`os.Logger`, subsystem **`com.kevinjones.KevLines2-0`** — **no disk writes** on the hot path). In **Console.app** or Xcode's debug console, filter by subsystem or category:

| Category | Typical messages |
|----------|------------------|
| **Pipeline** | Analyze start/end: analyzer type, file names, `poseHits` / `poseMiss` / `poseOkEmptyOverlay`, write failures |
| **Pose** | Model path, init failures; **first 3** MPImage / `detect()` errors per run (timestamped) |
| **VideoReader** / **VideoWriter** | Decode/composition failures, append failures |
| **ExerciseUI** | Thrown errors from `analyzeVideo` (domain/code/description) |

Use **`poseMiss`** vs **`poseOkEmptyOverlay`** to tell "MediaPipe saw no person" from "pose OK but analyzer returned no overlay instructions" (strict landmark guards).

## "Pose tracked: X%" diagnostic row — added in v3.3.2

`AnalysisSummary.poseDetectionRate` (Float 0–1) is now computed by `VideoProcessor` and shown directly in the exercise and assessment results cards in `ExerciseView`, so the detection rate is visible in the app without needing Console:

- **≥ 70%** — green checkmark, tracking acceptable
- **40–69%** — yellow warning, partial tracking
- **< 40%** — red warning + "improve framing or lighting" hint

Check this first before deeper investigation when overlays or rep counts are missing.

---

## Current focus — **v3.3.2** (marketing / build per `project.yml`)

### Squat & hip-hinge assessment — overlays missing on exported video

**Symptom:** MP4 shows correct orientation but no skeleton/grading overlay.

**Root cause confirmed by code review:**
The guard in each assessment analyzer only returns `.empty` when `PoseLandmarkerService.detect()` returns `nil` — i.e. MediaPipe's person detector got no result (`poseMiss`). Since MediaPipe returns **all 33 landmarks** whenever it detects a person, the bilateral landmark guards cannot fail if detection succeeds.

Therefore: **overlays are missing because `poseMiss` is high on those specific clips.**

**Likely video conditions:**
- Camera too far, person too small in frame
- Poor lighting reducing person-detector confidence
- Mismatched plane: frontal assessment (default for squat) filmed from a side angle. MediaPipe should still detect from the side, but verify the plane picker matches the filming angle (select Sagittal if the clip is a side profile)
- Assessment sagittal variants (`SquatSagittalAssessment`, `HipHingeAssessmentAnalyzer`) require strict side profile with full body visible

**Next steps:** Check the "Pose tracked: X%" row in the results card. If < 40%, the video clip needs better framing. Film in a well-lit area with the full body visible from head to ankle.

---

### Deadlift — no overlays, reps, or tempo on exported video

**Symptom:** Analysis completes without crash, output MP4 has correct orientation, but is a blank re-encode with no skeleton and zero reps/tempo.

**Root cause:** Same as assessments — `poseMiss` is high. `DeadliftAnalyzer` **always** builds and returns overlay instructions when its guard passes (shoulder + hip + knee + ankle in detection dict). Blank overlay = no detection at all, not a confidence threshold issue.

**Primary cause:** The barbell running across the hip/torso area breaks MediaPipe's person detector entirely, not just individual landmark confidence scores. This is a detection-pipeline failure; lowering `minVertexVisibility` has no effect.

**Practical fix — camera angle:** Film at **15–30° off true side profile** (slight forward or backward angle). This prevents the bar from lining up over the hip and gives MediaPipe a clear torso silhouette. The setup tip in the app now states this explicitly (`Exercise.swift` → `cameraSetupTip` for `.deadlift`).

**Alternative exercises for the hinge pattern:**
- `Hip Hinge (Side)` tracks the same movement with a lighter load and usually better detection
- For loaded bar work, adjust camera angle before re-trying deadlift analysis

**If detection still fails after re-framing:** Lower `minPoseDetectionConfidence` in `AnalysisConfig` (default 0.35 → try 0.2), but note this risks false-positive detections on complex gym backgrounds.

---

### Saved video — Row & Deadlift crash — **Resolved**

**Fix:** `AngleCalculator.displayDegrees(_:)` guards against `Int(Float.nan)`. Hardened `angle3D` and `extendLineToFrame` for degenerate inputs. Row and Deadlift now complete without crashing.

---

## Resolved (historical)

- **Export orientation** — Upside-down / mirrored exports: use `AVMutableVideoComposition` + `AVAssetReaderVideoCompositionOutput` ([VideoOrientation.md](VideoOrientation.md)).
- **Row/Deadlift crashes** — `Int(Float.nan)` traps. Fixed via `AngleCalculator.displayDegrees`.

---

*Update this file when closing an item or changing the shipping version.*
