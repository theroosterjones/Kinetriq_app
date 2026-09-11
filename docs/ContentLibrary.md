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

## Decision: text-only for now

**Kinetriq ships technique lessons as text and cues, with no illustrations.** Taken
2026-09-11. The plumbing (`illustrationAsset`, `attribution`, and the image branch in
`TechniqueLessonCard`) stays in place so adding art later is a content change rather
than an engineering one, but nothing is vendored today.

This costs less than it sounds like. The lessons are triggered by a measurement from
the user's own set and describe what they specifically did, and that specificity is
what makes them worth reading — a generic anatomical drawing adds polish, not
understanding. Shipping text is not a placeholder for a real feature; it is the
feature, slightly plainer.

## Why CC BY-SA 4.0 is the blocker

The obvious source is the **Everkinetic** exercise illustration set, which is
**CC BY-SA 4.0**. The problem is not attribution, which is easy. It is **share-alike**.

Creative Commons licenses with `SA` require that if you distribute an *adapted*
version of the work, you license your adaptation under the same terms. Three things
follow, in increasing order of how much they matter:

1. **Attribution must be visible and specific.** Not a line buried in Settings.
   Author, license name, a link to the license, and an indication of whether you
   modified the work. Annoying but solvable.

2. **Almost anything you would want to do to the art is an adaptation.** Recolouring
   to match the Kinetriq palette, cropping to a square, overlaying your own angle
   markers, compositing two images into a before/after, or tracing to redraw are all
   derivative works. Each one would have to be released under CC BY-SA 4.0 — meaning
   your competitor can take your version and use it. Shipping the images *pixel for
   pixel unmodified* avoids this, but pixel-for-pixel unmodified art in a designed app
   tends to look exactly like what it is.

3. **The uncertain part is the boundary.** Displaying an unmodified image next to your
   own text is normally "mere aggregation" — a collection, not an adaptation — and does
   not pull the app under the license. That is the standard reading, and it is probably
   right. But "probably" is doing real work in that sentence, and the failure mode is
   an argument about whether your app UI is a derivative work, which is not an argument
   worth having over decorative art. Note that CC explicitly discourages using their
   licenses for software, and offers no guidance on the app-bundling case.

To be clear about what is *not* the problem: **commercial use is fine.** CC BY-SA
permits it. A paid app can display CC BY-SA images. Selling the illustrations
themselves would be a different question; bundling them in an app you charge for is
not prohibited.

## What would actually unblock images

In rough order of how much I would recommend them:

**Commission original art.** A set covering the seven faults across nine movement
families is not a large illustration job, and the fault list is short and stable. You
own the result outright, it matches the app's visual language, and the licensing
question disappears permanently. This is the option I would take.

**Buy a properly licensed stock set.** Several medical-illustration libraries sell
royalty-free anatomical and exercise art with a commercial license that permits
modification. Costs money once, no share-alike, no attribution UI to build.

**Generate diagrams from your own pose data.** You already have MediaPipe landmarks
for every rep. A stick-figure or skeleton diagram rendered from a real recorded rep —
the user's own, or a reference take — would be original work, uniquely yours, and more
honest than a generic drawing because it would show *their* movement. More engineering
than the other options, but it is the one no competitor can copy, and it fits how the
rest of the product works.

**Use Everkinetic unmodified, with visible attribution.** Viable if you accept the
constraints: no recolouring, no cropping, no overlays, no compositing, and an
attribution line in the lesson card plus a credits screen. Cheapest and fastest. If
you go this way, get a lawyer's sign-off on the aggregation reading first, and
document it here so the next person does not relitigate it.

**Ask a licensing attorney about the aggregation boundary.** Worth an hour of someone's
time if any of the above is going to hinge on it. The specific question: does bundling
unmodified CC BY-SA images in a proprietary iOS app, displayed alongside original text,
constitute a collection rather than an adaptation?

Until one of those lands, leave `illustrationAsset` nil. The lessons work without it.

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
