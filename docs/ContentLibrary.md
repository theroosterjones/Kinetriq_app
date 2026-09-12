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

## Decision: Everkinetic, unmodified, with visible attribution

**Kinetriq bundles nine Everkinetic exercise illustrations under CC BY-SA 4.0, used
byte-for-byte as published.** Decided 2026-09-12, after weighing the alternatives in
"What would unblock images" below.

The constraint that comes with that choice is not optional, so it is worth stating
plainly:

> **Never edit these files, and never render them altered.** No recolouring to the
> Kinetriq palette, no cropping, no compositing two into one frame, no drawing angle
> markers over them, no tracing. Any of those creates a derivative work that
> share-alike would require you to release under CC BY-SA 4.0.
>
> Fitting an image inside a frame, scaling it proportionally, and placing it on a
> background are presentation, not modification. Those are fine.
>
> If you need a different crop or size, that is a **new illustration** — commission it
> or license it. Do not open these in an editor.

### How it is set up

| Piece | Where |
|---|---|
| The files | `Resources/Everkinetic/` — original names (`0122-tension.png`), byte-identical |
| License | `Resources/Everkinetic/LICENSE.md`, shipped in the bundle |
| Bundling | `project.yml` folder reference, **not** an asset catalog |
| Mapping + credits | `Sources/Models/ExerciseIllustration.swift` |
| Credits screen | `Sources/Views/AttributionView.swift`, linked from Settings |

They live in a top-level `Resources/` folder rather than under `Sources/` so the
CC BY-SA material stays physically separate from Kinetriq's own code — which is the
distinction share-alike cares about. A folder reference is used instead of an asset
catalog because Xcode compiles catalogs into their own container format, and keeping
the originals as loose files makes "unmodified" verifiable at a glance.

### Where they appear, and where they deliberately do not

**Movement reference in the exercise library** (`ExerciseLibraryView`): start and end
position, side by side. This is where a reference image genuinely belongs — "what does
this movement look like" is the question someone browsing the library is asking.

**Position faults only** in technique lessons. `TechniqueLesson.illustratableFaults` is
`{inconsistentDepth, rangeBelowPersonalBest}`, and `withIllustration(for:)` refuses to
attach an image to anything else. A drawing cannot show tempo, so putting one beside a
"your eccentric was 0.8 seconds" lesson is decoration — and decoration next to a
measurement makes the measurement look like marketing. Rushed eccentric, accelerating
tempo, asymmetry, low tracking, and short sets all stay text-only on purpose.

**Not on assessments.** `ExerciseIllustration.forExercise(.shoulderAssessment)` returns
nil. A barbell drawing would misrepresent a range-of-motion screen.

### Attribution, which is a requirement and not a courtesy

CC BY-SA 4.0 requires attribution reasonable to the medium, a statement of whether the
work was modified, and a copy of or link to the license. All three are covered:

- **Every image carries its credit line wherever it is shown** — `creditLine` renders
  under the illustration in both the library card and the lesson card. It is never in
  a settings screen only.
- The line is `"Barbell Squat" by Everkinetic, CC BY-SA 4.0 — unmodified`, which is
  title, author, license, and modification status in one string. `ExerciseIllustrationTests`
  asserts all four parts are present for every illustration, and that a lesson can
  never carry an image without also carrying its credit.
- **Settings → Credits & licenses** names Everkinetic and Greg Priday, links to
  db.everkinetic.com and to the license, lists all nine illustrations with source
  URLs, and includes the full bundled license text.

### The mapping is approximate, on purpose

Everkinetic has no "hip hinge" drawing, so the Romanian deadlift stands in for the
pattern; a seated cable row stands in for the row Kinetriq films from the side. Note
also that `0097` (Wide Grip Lat Pull Down) has no file in Everkinetic's `dist/png`, so
vertical pull uses `0096` (V Bar Pull Down). These are reference images for a movement
pattern, not depictions of the exact setup being filmed.

### Revisiting this

The reason to revisit is not legal risk, it is that these are somebody else's drawings
of a barbell gym, and they will always look like an import. When there is budget,
commission the set or render diagrams from your own pose data — `ExerciseIllustration`
is the only file that needs to change, plus swapping the folder contents.

## What CC BY-SA 4.0 actually requires

This is the reasoning behind the constraints above, kept so nobody has to work it
out again. The obstacle was never attribution, which is easy, and it was never
commercial use. It is **share-alike**.

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

## What would let us stop using someone else's art

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

Option four is what shipped. The others remain open, and the plumbing does not care
which one you pick.

## Swapping or adding illustrations

To replace the set (commissioned art, a licensed set, or generated diagrams):

1. Drop the files into `Resources/Everkinetic/` — or a new sibling folder, adding a
   matching folder reference in `project.yml`. Keep original file names.
2. Update the catalog constants in `ExerciseIllustration`, and `creditLine` if the new
   art has different licensing terms. If it is fully owned, `creditLine` and the
   credits screen entry can go away entirely.
3. Run `xcodegen generate`.
4. `ExerciseIllustrationTests` will fail on anything unmapped, uncredited, or missing a
   frame. Run it before assuming the swap worked.

To add one for a movement that has none, add the constant, add it to
`ExerciseIllustration.all` so it reaches the credits screen, and map it in both
`forExercise(_:)` and `forFamily(_:)`.

Every render path degrades to text when an image is missing — `isAvailable`,
`startImage`, and `endImage` all return optionals that the views check — so a
misnamed file shows no illustration rather than an empty frame.

## Adding a new fault

1. Add the case to `MovementFault`.
2. Detect it in `TechniqueFaultDetector.faults(in:personalBestPeakAngle:)`, using a
   threshold that already exists in the scoring code where possible.
3. Add a `private static func` returning the lesson, and wire it into
   `TechniqueLibrary.lesson(for:family:)`.
4. Give it an icon and tint in `TechniqueLessonCard`.

Write the cues per `MovementFamily`, not per `ExerciseType`. A rushed eccentric in a
squat and in a lunge want the same correction; in a curl it does not.
