# Technique content: how it works, and the illustration question

## What shipped

`Sources/Models/TechniqueLibrary.swift` holds the technique instruction. It is not a
browsable encyclopedia. Every lesson is keyed to a **`MovementFault`**, and each fault
maps to a number the analysis pipeline already produces:

| Fault | Measured from | Threshold |
|---|---|---|
| `rushedEccentric` | `RepMetric.lacksEccentricControl` on ≥ half the reps | eccentric ≤ 1.0 s |
| `inconsistentDepth` | standard deviation of per-rep peak angle | ≥ 8° |
| `acceleratingTempo` | active time, first half of set vs second | ≥ 25% faster |
| `rangeBelowPersonalBest` | this set's mean peak angle vs the user's own deepest | ≥ 10° shallower |
| `asymmetry` | `AssessmentMetrics.asymmetryFlag` | analyzer's own flag |
| `lowTracking` | `poseDetectionRate` | < 70% |
| `tooFewReps` | completed rep count | < 3 |

Thresholds match the ones the scoring code uses, so a lesson never contradicts the
score printed next to it.

`rangeBelowPersonalBest` compares against **the user's own history**, never a
population norm. Kinetriq has no population data, and a library that told someone
their squat was "below average depth" would be asserting something the app cannot
support. This is also why the lesson text says "shallower than your own best" rather
than "shallow."

Lessons surface in two places, both after a measurement exists:

- `ExerciseView` — under the results, for the set just analyzed.
- `AnalysisRecordDetailView` — for any saved session, recomputed against the history
  that preceded it.

The browsable `ExerciseLibrary` still exists for discovery, and its detail screen now
lists *what Kinetriq checks for* on that pattern — titles only, no advice. The full
lesson stays behind the measurement.

`TechniqueLibrary.maximumLessons` is **2**. Three corrections is already more than
anyone acts on after a set.

## The illustration question — decide before adding assets

`TechniqueLesson` carries `illustrationAsset` and `attribution`, and
`TechniqueLessonCard` renders the image when the asset exists in the bundle. Both are
currently `nil` everywhere. That is deliberate.

The intended source is the **Everkinetic** anatomical illustration set, which is
licensed **CC BY-SA 4.0**. Share-alike is not a formality and it is not a decision to
make silently inside a code change:

- **Attribution is mandatory and must be visible**, not buried in a settings screen.
  Credit the source and name the license.
- **Share-alike applies to derivative works of the images.** Recolouring an
  illustration to match the Kinetriq palette, cropping it into a composite, or
  tracing it produces a derivative that must itself be released under CC BY-SA 4.0.
- **Unmodified display alongside your own content is generally mere aggregation**,
  which does not force the surrounding app under the license — but "generally" is
  doing real work in that sentence, and the answer depends on how the images are
  combined with app UI.
- A paid app can use CC BY-SA material; the license restricts licensing terms, not
  commerce. Selling the *illustrations* is a different question from selling an app
  that displays them.

**Get an actual answer on this before shipping any asset**, ideally from someone who
does licensing for a living. The plumbing is in place so that when the answer is yes,
it is a content change and not an engineering one.

## Adding illustrations once that is settled

1. Put the images in `Sources/Assets.xcassets` as image sets. Name them
   `TechniqueSquatDepth`, `TechniqueHingeNeutralSpine`, and so on.
2. Set `illustrationAsset:` on the relevant `TechniqueLesson`, and set `attribution:`
   to the exact required credit string, e.g.
   `"Illustration: Everkinetic, CC BY-SA 4.0"`.
3. Run `xcodegen generate`.
4. `TechniqueLessonCard` already guards with `UIImage(named:) != nil`, so a missing
   or misnamed asset degrades to text rather than showing an empty frame.

## Adding a new fault

1. Add the case to `MovementFault`.
2. Detect it in `TechniqueFaultDetector.faults(in:personalBestPeakAngle:)`, using a
   threshold that already exists in the scoring code where possible.
3. Add a `private static func` returning the lesson, and wire it into
   `TechniqueLibrary.lesson(for:family:)`.
4. Give it an icon and tint in `TechniqueLessonCard`.

Write the cues per `MovementFamily`, not per `ExerciseType`. A rushed eccentric in a
squat and in a lunge want the same correction; in a curl it does not.
