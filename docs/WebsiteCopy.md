# kinetriq.net — replacement copy and settings

The site is a Squarespace 7.1 build (template `5c5a519771c10ba3470d8101`) and is **not** in this
repo, so nothing here can be applied by a script. Everything below is paste-ready for the
Squarespace editor. Work top to bottom; each section names the page and the block to replace.

**Why this matters:** today the homepage runs a section titled *"Why We Do Not Use AI Form
Analysis"* while the App Store listing sells automated biomechanical feedback and `/terms` says
scores are *"estimates produced by on-device AI."* A visitor who reads two of those three comes
away thinking the product is either vaporware or dishonest. The position below keeps everything
that was right about the original section — skepticism of black-box verdicts, the coach's
judgment staying central — without denying the feature the app is sold on.

---

## 1. Home — hero

Replace the entire hero markdown block.

> # Kinetriq
>
> ## Measure the movement. Keep the judgment.
>
> Kinetriq turns a phone video of a lift into numbers you can actually use: joint angles, rep
> count, four-phase tempo, and a repeatability score — measured automatically, on your device,
> in about the time it takes to watch the clip back.
>
> It does not tell you whether the rep was "good." That is still your call. It gives you the
> measurements your eye cannot hold steady across twelve reps and six weeks.
>
> Built for trainers, physical therapists, coaches, and lifters who want their feedback grounded
> in something more repeatable than a hunch.

**Call to action:** replace the plain-text `Iphone Download: https://...` line with a real App
Store badge image linked to `https://apps.apple.com/us/app/kinetriq/id6782692673`. Official
badge artwork: <https://developer.apple.com/app-store/marketing/guidelines/#downloadOnAppstore>.

Keep the `Android: Coming Soon!` line only if Android is genuinely planned; otherwise delete it.
It currently reads as a stalled roadmap rather than a promise.

---

## 2. Home — replace "Why We Do Not Use AI Form Analysis"

Delete that section in full. Replace with this one, same position.

> ## What the measurement does, and what it does not
>
> Kinetriq uses on-device computer vision to track 33 body landmarks through your video. From
> those it calculates joint angles, counts reps, times each phase of every rep, and scores how
> consistent the set was from first rep to last. That part is automatic, and it is the same
> every time — which is the whole point of a measurement.
>
> What it does not do is hand down a verdict. It will not tell you the squat was "wrong," name a
> diagnosis, or prescribe a fix. Movement is contextual: a rounded back means one thing under a
> heavy deadlift and another thing in a warm-up. The software measures. You interpret.
>
> That division is deliberate. A coach with objective numbers is better than a coach without
> them, and far better than an app that replaces the coach with a confident guess.
>
> **Everything runs on your device.** Your video is never uploaded, never stored on a server, and
> never seen by anyone but you.

---

## 3. Home — new section: how it works

Add below the section above. The site currently has no explanation of the actual workflow.

> ## How it works
>
> **1. Film one set.** Phone on a tripod or leaned against a water bottle. Side-on for squats,
> deadlifts, rows, and curls; straight-on for presses and pulldowns. One person in frame.
>
> **2. Pick the movement.** Eleven analyzed lifts and three graded assessments, each with its own
> joint model and rep logic. Or run it live and watch the skeleton track in real time.
>
> **3. Read the numbers.** Rep count, per-rep tempo as four phases, peak joint angle for every
> rep, and a 0–100 consistency score. Plus plain-language notes on what moved and what drifted.
>
> **4. Share what's useful.** Export the analyzed clip with the overlay burned in, or a summary
> card. Crop to 9:16 if it's going on social.

---

## 4. Home — new section: what it measures

The site never lists a single exercise. A trainer cannot tell whether their lifts are covered.

> ## What it measures
>
> **Exercises** — Squat · Deadlift · Lunge · Hip Hinge (side and rear) · Row · Dips · Lat
> Pulldown / Chin-Up (side and front) · Overhead Press · Bicep and Tricep curls
>
> For each: rep count, peak joint angle per rep, four-phase tempo (eccentric – pause – concentric
> – pause), and a 0–100 consistency score combining range-of-motion repeatability with tempo
> repeatability.
>
> **Assessments** — Shoulder Flexion · Squat Screen · Hip Hinge Screen, each filmed from the
> front or the side
>
> Each returns a letter grade with a breakdown, left-versus-right range of motion, and a flag
> when the two sides differ enough to be worth a look.

---

## 5. Home — social proof

Add above the footer. The App Store rating is 5.0 and the written reviews are strong; none of
this appears on the site.

> ## From the App Store
>
> > "As a trainer, I am frequently using video playback to show my clients areas that can improve
> > their movements. Using Kinetriq makes it so much easier to analyze video and show the clients
> > more precise data. This also helps me appear more professional in the feedback I'm giving
> > them."
> >
> > — Personal trainer, App Store review

Pair with the App Store rating badge. Do not invent additional testimonials.

---

## 6. Home — pricing (new section; the site currently shows none)

> ## Pricing
>
> **Kinetriq Pro — $4.99/month or $34.99/year**
>
> Free trial for new subscribers. Every analysis feature is included in Pro; there is no limited
> free tier and no per-video charge. Cancel any time in your Apple ID settings.
>
> Annual works out to under $3 a month.

Update the trial length here to match whatever is live in App Store Connect — see
`docs/SubscriptionExperiments.md`, which proposes moving from 7 days to 14.

---

## 7. `/about` — replace entirely

This page is currently unedited Squarespace agency boilerplate ("custom app, seamless system
integration, or smart automation," "our friendly team"), it is not in the nav, and it **is** in
`sitemap.xml`, so search engines can land people on it. Either delete the page outright or
replace with the following, and add it to the nav.

> # About
>
> Kinetriq is built and maintained by one person.
>
> It started from a practical problem: video is the best coaching tool there is, and also the
> most tedious. Scrubbing back and forth to judge whether rep eight was as deep as rep two, or
> whether the eccentric really slowed down, takes longer than the set did — and the answer is
> still a guess.
>
> Computers are good at exactly that kind of measurement and bad at the judgment around it. So
> Kinetriq does the measuring and leaves the judgment alone. Everything runs on the device, which
> keeps it fast, works without a signal, and means client video never lands on someone else's
> server.
>
> Questions, bug reports, and requests for movements to support all go to the same inbox, and I
> read them: **kevin@kinetriq.net**

---

## 8. `/contact` — fix the waitlist framing

The form currently says *"We can notify you once app becomes available to the public."* The app
has been on the App Store since 3.5.0. Replace the intro with:

> Kinetriq is available on the App Store now. If you hit a problem, want a movement supported
> that isn't yet, or are a trainer or clinician with questions about using it with clients, send
> a note — it's a one-person project and I answer these myself.

---

## 9. SEO and metadata

All under **Settings → SEO** and **Pages → [page] → SEO** in Squarespace.

| Setting | Current | Change to |
|---|---|---|
| Site title / homepage `<title>` | `Kinetriq` | `Kinetriq — On-device movement analysis for trainers and clinicians` |
| Homepage meta description | **empty** | `Turn a phone video of any lift into joint angles, rep counts, four-phase tempo, and a 0–100 consistency score. Runs entirely on your iPhone — video never leaves the device.` |
| `og:description` | **missing** | Same as the meta description above |
| `og:image` | **missing** | A 1200×630 image showing the skeleton overlay on a real lift |
| `twitter:card` | `summary` | `summary_large_image` |
| Image `alt` text | all empty | Describe each: wordmark, overlay screenshot, etc. |

**Also reconsider the AI-crawler blocklist.** Squarespace's default `robots.txt` disallows
`GPTBot`, `ClaudeBot`, `anthropic-ai`, `Google-Extended`, and `PerplexityBot`. A growing share of
"best movement assessment app for trainers" queries are now answered by assistants reading those
crawls. Blocking them is a defensible choice for a content business protecting its archive; for a
six-page brochure site trying to get discovered it costs more than it protects.

---

## 10. Add a demo clip

The homepage has two images and no video, for a product whose entire value is visual. A 15–30
second screen recording of the skeleton overlay tracking a real squat — with the rep counter and
tempo readout visible — will do more than any of the copy above. Put it directly under the hero.

---

## 11. Smaller inconsistencies worth fixing

- `/delete-account` gives Google Play cancellation instructions for an iOS-only app.
- Footer contact is `support@kinetriq.net`; Terms and Privacy use `kevin@kinetriq.net`. Pick one.
- Terms and Privacy still describe promo/comp code redemption, which was removed from the app for
  App Store Guideline 3.1.1 compliance.
- The Privacy Policy says no analytics SDKs are used, but the App Store privacy label declares
  Payment Info and Email Address collected for Analytics. Reconcile these — a mismatch here is
  exactly what App Review flags.
- Brand capitalization alternates between "Kinetriq" and "kinetriq" within the same paragraph.
- **Once metrics sync ships** (see `SyncService`), the "nothing is uploaded" claim needs the
  narrower wording used in the app: *your video never leaves your device; your measurements sync
  so you can see progress over time.* Update Home, `/privacy`, and the App Store description
  together, in the same release.
