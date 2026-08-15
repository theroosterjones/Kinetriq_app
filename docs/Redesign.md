# Kinetriq UI Redesign — "Premium" v2 (beta)

> **Branch:** `feature/premium-ui-redesign`
> **Status:** Beta — for TestFlight evaluation alongside the current shipping UI.
> **Safety net:** The current, working design/UX is preserved on
> `fix/saved-video-loading` (and tagged history). Nothing in this branch alters
> the on-device analysis pipeline, analyzers, video I/O, MediaPipe handling, or
> the subscription/auth services. If anything feels off in beta, we can switch
> back to the previous branch with **zero data or pipeline risk**.

This document is the senior-product-designer brief: per-screen problems,
rationale, wireframe structure, visual direction, and interaction notes, plus
the underlying UI system. It maps 1:1 to what was implemented in code.

---

## Design north star

Make Kinetriq feel like an **Apple-featured, clinic-grade movement platform** —
in the company of Apple Fitness, Whoop, Oura, Levels, Strava, and Tonal — while
staying fast and legible for trainers, PTs, chiropractors, and coaches.

Five operating principles drove every decision:

1. **Clarity first** — one obvious primary action per screen.
2. **Premium minimalism** — strong spacing, restrained color, confident type.
3. **Faster flow** — fewer taps from "open app" to "analysis done."
4. **Hierarchy** — the score/grade is the hero; raw numbers are progressive.
5. **Data as insight** — rings, grades, trends, and pass/fail over raw text.

---

## UI System

### Typography hierarchy (`KFont`)
SF Rounded for a friendly-premium voice; monospaced digits for stable numerals.

| Token | Use |
|------|-----|
| `display(34–40)` | Brand / dashboard title |
| `title` / `title2` | Screen + section titles |
| `headline` / `callout` | Card titles, buttons, controls |
| `body` / `subheadline` | Reading copy |
| `caption` / `micro` | Metadata, helper text |
| `eyebrow` | All-caps section labels (tracked +0.8) |
| `numeral(size)` | Scores, reps, angles (rounded, monospaced) |

### Color system (`KColor`)
Adaptive light/dark. Signature "kinetic" blue brand with teal (positive/movement)
and violet (assessments) supports; semantic success/warning/danger.

- Brand: `accent #3D7BFF` → gradient to `#6E5CFF`.
- Movement/positive: `teal #21D0B2`. Assessments: `violet #8B5CF6`.
- Surfaces: `background / surface / surfaceElevated / surfaceSunken / separator`.
- Text: `textPrimary / textSecondary / textTertiary`.
- `KColor.grade(_:)` and `KColor.score(_:)` give a single source of truth for
  grade/score coloring across the app.

### Spacing system (`KSpacing`)
8pt-based scale: `xxs 4 · xs 8 · sm 12 · md 16 · lg 20 · xl 28 · xxl 40`, with a
standard `screenH = 20` horizontal inset so every screen aligns.

### Corner radius (`KRadius`)
`sm 12 · md 18 · lg 24 · xl 32 · pill`. Continuous curves throughout.

### Cards (`KCard`)
A single elevated surface primitive: surface fill, hairline separator border,
soft shadow, continuous 18pt radius. Used everywhere for visual consistency.

### Buttons
- `KPrimaryButtonStyle` — full-width 54pt, brand (or contextual) gradient,
  spring press animation. One per screen.
- `KSecondaryButtonStyle` — tinted, low-emphasis (export, replace).

### Navigation patterns
- 4-tab bar relabeled to outcomes: **Home · Analyze · Progress · Settings**
  with filled, confident SF Symbols and brand tint.
- Cross-tab `AppRouter` lets Home/Library deep-link **straight into Analyze**
  (and preselect the exercise/assessment) — removing taps.
- FAQ relocated from Home into a dedicated **Help & FAQ** screen.

### Icons
SF Symbols, weighted `semibold`, tinted by domain (brand/teal/violet).

### Charts & analytics components
Dependency-free, lightweight, screenshot-friendly:
- `ScoreRing` — gradient circular score 0–100.
- `GradeBadge` — A–F badge with grade-colored gradient.
- `Sparkline` — trend line + gradient fill.
- `ProgressTrack` — ROM / progress bars.
- `StatTile`, `MetricChip`, `KPill`, `InfoBanner`, `KEmptyState`.

---

## Screen-by-screen

### 1) Home → **Dashboard**
**Current problems**
- A giant logo + tagline pushed real content below the fold.
- The two "quick action" cards weren't tappable (decorative only).
- A 12-item FAQ dominated the screen — high noise, low daily value.
- No sense of progress, recency, or "what should I do now."

**Rationale**
A pro dashboard should answer "what do I do, and how am I trending?" instantly.
Lead with one primary action, then surface trend/summary, tools, and the
library; demote help to a link.

**Wireframe**
```
Eyebrow + "Kinetriq"                         (?) Help
┌──────────────────────────────────────────┐
│  Analyze a movement        [Record][Upload]│  ← hero gradient CTA
└──────────────────────────────────────────┘
THIS WEEK   ·Preview
[Analyses] [Avg score] [Assessments]            ← stat tiles
┌ Assessment trend ───────────── Sample ┐
│  ∿ sparkline                          │
└───────────────────────────────────────┘
[Assessment]            [Live Camera]           ← tool tiles
EXERCISE LIBRARY                     See all →
[Squat][Deadlift][Shoulder][Row][Pulldown] →    ← horizontal chips
[ Tips, camera setup & FAQ → ]
```
**Visual** — Hero uses the brand gradient with glow shadow. Sample/preview data
is explicitly tagged (`Preview` / `Sample`) so it's honest pre-backend.
**Interactions** — Record/Upload jump directly into Analyze in the right mode;
library chips deep-link with the exercise preselected.

---

### 2) Workout → **Analyze**
**Current problems**
- A long vertical stack of raw segmented/menu pickers = high cognitive load.
- Video sat mid-page at 300pt, not the hero.
- Results were a plain gray text block ("Reps: 5", "Score: 80/100", "Avg knee: …")
  with weak hierarchy.

**Rationale**
Collapse configuration into one calm "setup" card, make the **video the hero**
(or a clear upload dropzone), and turn results into a **score-led** card.

**Wireframe**
```
[ Saved Video | Live Camera ]                   ← mode
┌ Setup ─────────────────────────────────┐
│ CATEGORY [Exercises|Assessments]        │
│ EXERCISE                     Squat ▾    │
│ WORKING SIDE [Left|Right]               │
│ OVERLAY [Simple|Full HUD]               │
│ ▸ Alignment overlays (2)                │
└─────────────────────────────────────────┘
ⓘ Camera setup tip
┌ Video (hero, 320pt) ──────────  •Analyzed ┐
└──── [Replace]              [Full screen] ─┘
[ Analyze form ]                                ← single green CTA
┌ Results ───────────────────────────────┐
│ ◯ 86   [Reps 5][Duration 12.4s]         │  ← ScoreRing + tiles
│ AVG JOINT ANGLES  (knee 92°)(hip 78°)   │
│ ✓ Pose tracked 94% of frames            │
└─────────────────────────────────────────┘
[ Export analyzed video ]
```
**Visual** — Dropzone uses a dashed brand border; the Analyze CTA is a
success-gradient primary; processing shows an inline percentage + progress bar.
**Interactions** — Animated mode/category switches; press-spring on the CTA.

---

### 3) Movement Assessments → **Clinical report card**
**Current problems**
- The big letter grade was good, but sub-grades, ROM, asymmetry, and details
  were an undifferentiated text list — not "clinical."

**Rationale**
Clinicians scan for **verdict → breakdown → ROM → asymmetry → recommendations**.
Give each its own labeled block with pass/fail affordances.

**Wireframe**
```
┌ Assessment report ─────────────────────┐
│ [ A ]  Excellent                        │  ← GradeBadge + verdict
│        Movement meets quality standards │
│ BREAKDOWN                               │
│  ✓ Depth            [A]                  │  ← pass/fail rows + grade pill
│  ! Knee control     [C]                  │
│ RANGE OF MOTION                         │
│  Left  ▮▮▮▮▮▮▯  152°                     │  ← ROM bars L/R
│  Right ▮▮▮▮▮▯▯  141°                     │
│  ⚠ Asymmetry detected — 11° difference  │
│ RECOMMENDATIONS                         │
│  → actionable cue …                     │
│ ✓ Pose tracked 91% of frames            │
└─────────────────────────────────────────┘
```
**Visual** — Grade color drives badge, pills, and check/warn icons. Asymmetry
escalates to a warning banner only when flagged.

---

### 4) **Exercise Library** (new browse experience)
**Current problems**
- No library existed; exercises were buried in the Analyze picker; "coming soon"
  with no value.

**Rationale**
A searchable, filterable, visual catalog is both educational and a fast path to
analysis — great for screenshots and onboarding.

**Wireframe**
```
🔍 Search movements
[All][Lower Body][Upper Body][Assessments]      ← filter chips
┌ Squat ───────┐ ┌ Deadlift ────┐
│ icon         │ │ icon         │              ← 2-col cards
│ Side view    │ │ 15–30° off   │
└──────────────┘ └──────────────┘
  → tap → detail sheet → [ Analyze this movement ]
```
**Visual/Interaction** — Category filter animates; detail sheet shows what's
measured + camera/coaching cues, then deep-links into Analyze with the movement
preselected.

---

### 5) History → **Progress**
**Current problems**
- A bare "Coming Soon" SF Symbol — dead screen, no value, no aspiration.

**Rationale**
Show the *shape* of the upcoming progress dashboard (clearly labeled preview),
plus an honest empty state and a CTA, so the tab earns its place now and sells
the roadmap.

**Wireframe**
```
ⓘ Progress sync is coming (preview)
┌ Form score — last 8 sessions ·Sample ┐
│ ∿ sparkline   [+22][Best 86][Avg 74]  │
└────────────────────────────────────────┘
┌ Consistency ·Sample ┐  (14-bar activity)
└──────────────────────┘
RECENT ANALYSES
┌ empty state + [ Analyze a movement ] ┐
```

---

### 6) Settings & system
- Branded header (logo + version) atop the native `Form` (kept for familiarity
  and accessibility); accent unified to brand blue; added a Help & FAQ link.
- App loading screen and tab bar restyled to the brand.
- **Paywall** logic untouched; it already presents a strong RevenueCat paywall
  with a polished fallback.

---

## What was intentionally NOT changed
- Analyzers, `VideoProcessor`/`VideoReader`/`VideoWriter`, MediaPipe handling,
  overlay rendering, tempo/rep logic — **untouched**.
- `AuthService`, `PurchaseService`, `PromoRedemptionService`, paywall flow.
- All Photos import/compatibility logic in `ExerciseView` (verbatim).

## New files
```
Sources/DesignSystem/KinetriqTheme.swift       — tokens
Sources/DesignSystem/KinetriqComponents.swift  — components
Sources/App/AppRouter.swift                     — cross-tab deep links
Sources/Models/ExerciseLibrary.swift            — educational catalog
Sources/Views/ExerciseLibraryView.swift         — library browse + detail
Sources/Views/HelpView.swift                     — relocated FAQ
docs/Redesign.md                                 — this brief
```

## Verification
- `xcodegen generate` + `xcodebuild … -destination 'iPhone 16'` → **BUILD SUCCEEDED**.

## Reverting
```
git checkout fix/saved-video-loading   # the known-good, shipping UX
```
The redesign lives entirely on `feature/premium-ui-redesign`; switching branches
restores the prior experience instantly.
