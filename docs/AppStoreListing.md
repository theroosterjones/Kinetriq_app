# Kinetriq — App Store listing & privacy answers (first pass)

Copy/paste source for the App Store Connect listing. Edit the marketing voice to
taste; the **App Privacy** section is the important accuracy-sensitive part.

> Data reality (verified in code): the app sends only **account info** (email,
> optional name), a **user ID**, and **purchase state** (RevenueCat) off device.
> All video and pose/movement analysis runs **on-device** and is never uploaded.
> There are no analytics, crash, ad, or tracking SDKs.

---

## 1. Listing metadata

| Field | Value |
|-------|-------|
| App name | **Kinetriq** |
| Subtitle (≤30 chars) | **On-device form analysis** (29) |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Age rating | 4+ (no objectionable content; not medical — see review notes) |
| Price | Free (with Kinetriq Pro subscription) |
| Bundle ID | `com.kevinjones.Kinetriq` |

Alternate subtitle options (≤30):
- "Movement coach, on device" (29)
- "Analyze your lifting form" (25)

---

## 2. Promotional text (≤170 chars, updatable anytime)

> Get instant, private feedback on your lifting form. Kinetriq analyzes joint
> angles, reps, and tempo entirely on your device — no video ever leaves your phone.

---

## 3. Description (first pass)

> **Kinetriq turns your iPhone into an on-device movement coach.**
>
> Point your camera at yourself or pick a saved video, and Kinetriq analyzes your
> exercise form in real time — skeleton overlay, joint angles, rep counts, and
> tempo phases — all processed privately on your device. Nothing is uploaded.
>
> **Train smarter**
> • Real-time form analysis with live skeleton and joint-angle overlays
> • Automatic rep counting and 4-phase tempo tracking (eccentric, pause,
>   concentric, pause)
> • Saved-video analysis with per-rep breakdowns and average tempo
> • Plain-language coaching insights after every set
> • Letter-graded movement assessments for shoulder, squat, and hip-hinge screens
>
> **Built for real workouts**
> • Squat, Deadlift, Lunge, Hip Hinge, Row, Dips, Lat Pulldown / Chin-Up,
>   Overhead Press, and Bicep/Tricep work
> • Simple or full-HUD overlay modes
> • Share a clean summary card or export a 9:16 clip for socials
>
> **Private by design**
> • All movement analysis runs on-device using Apple-silicon-accelerated AI
> • Your videos never leave your phone
>
> **Kinetriq Pro**
> Unlock unlimited analysis with Kinetriq Pro (monthly or annual). Subscriptions
> are billed through your Apple ID; manage or cancel anytime in Settings.
>
> Kinetriq provides general fitness and educational feedback only and is not
> medical advice. Consult a qualified professional for diagnosis or treatment.

---

## 4. Keywords (≤100 chars, comma-separated, no spaces)

```
form,lifting,squat,deadlift,workout,gym,rep counter,tempo,pose,posture,mobility,coach,technique
```
(99 chars — trim/replace as needed. Don't repeat words already in the app name/subtitle.)

---

## 5. What's New (version notes)

### 3.5.5

> Fixes a bug that could leave the app flipping between the loading screen and
> the subscription screen after signing in. Sign in with Apple now completes
> reliably after the account is created, and Row analysis counts reps through a
> full hang-to-squeeze range.

### 3.5.4

> Sign in with Apple now completes reliably after the account is created. Row
> analysis counts reps through a full hang-to-squeeze range.

### 3.5.3

> Form score now grades depth consistency in finer bands, no longer penalizes a
> concentric that slows as the set gets hard, and deducts for eccentrics of 1
> second or faster. Coaching notes call out a challenging set versus reps that
> lack control. Custom alignment overlays are smoother and no longer snap when
> pose tracking flickers.

### First public release

> First public release of Kinetriq. On-device exercise form analysis, movement
> assessments, per-rep breakdowns, coaching insights, shareable summaries, and
> Kinetriq Pro.

---

## 6. App Privacy ("nutrition labels") answers

In App Store Connect → App Privacy, declare the following. Everything below is
**linked to the user's identity** and used only for **App Functionality** (no
tracking, no third-party advertising).

**Tracking:** No — the app does not track users across apps or websites owned by
other companies. (Do not present the ATT prompt; none is used.)

**Data collected:**

| Data type | Category | Purpose | Linked to user | Notes |
|-----------|----------|---------|----------------|-------|
| Email address | Contact Info | App Functionality | Yes | Supabase account login |
| Name | Contact Info | App Functionality | Yes | Optional, only if provided via Sign in with Apple |
| User ID | Identifiers | App Functionality | Yes | Supabase user UUID = RevenueCat app user ID |
| Purchase history | Purchases | App Functionality | Yes | Subscription state via RevenueCat |

**Data explicitly NOT collected (call out for reviewer clarity):**
- Photos/Videos — used on-device for analysis, **never uploaded or transmitted**.
- Health & Fitness data — movement/pose analysis is computed and stored on-device only.
- Location, Contacts, Browsing/Search history, Usage data, Diagnostics — none.

> ⚠️ Verify RevenueCat's current published App Privacy guidance before submitting —
> if you later enable any RevenueCat attribution/analytics features, you may need
> to add "Product Interaction" (Usage Data) or "Device ID" (Identifiers). With the
> default SDK config, Purchases + User ID is the accurate set.

---

## 7. Age rating questionnaire

- Made for Kids: **No**
- Medical/Treatment information: **No** (fitness/education only; not medical advice)
- All other content descriptors: **None**
- Result: **4+**

---

## 8. App Review information

- **Sign-in required:** Yes. Provide a working demo account:
  - Email: `<reviewer demo email>`
  - Password: `<reviewer demo password>`
- **How to test Pro features without paying:** either
  (a) attach a sandbox tester and let them start the free trial, or
  (b) provide a comp promo code redeemable in-app (Settings → redeem code),
      backed by the Supabase `redeem-promo-code` function with an `unlimited` code.
- **Notes to reviewer (suggested):**
  > Kinetriq analyzes exercise form entirely on-device using the camera or a saved
  > video; no video or movement data is uploaded. Account login (Supabase / Sign in
  > with Apple) and subscriptions (RevenueCat) are the only networked features.
  > Account deletion is available in Settings → Account. Use the demo account above;
  > redeem code `<CODE>` to unlock Kinetriq Pro for review.

---

## 9. URLs still needed (blockers)

- [ ] Privacy Policy URL (public, reachable) — also goes in `Config/KinetriqSecrets.xcconfig`
- [ ] Terms of Use / EULA URL — Apple's standard EULA is acceptable if you don't have a custom one
- [ ] Marketing/Support URL — `https://kinetriq.net` + support email `kevin@kinetriq.net`

---

## 10. Screenshots checklist

Required iPhone sizes (one set can be uploaded and reused where allowed):
- [ ] 6.9" / 6.7" display (e.g. iPhone 16 Pro Max / 15 Pro Max)
- [ ] 6.5" display (e.g. iPhone 11 Pro Max / XS Max)

Suggested shots: live analysis with skeleton overlay, saved-video per-rep
breakdown, a movement-assessment grade, the coaching insights card, and the
shareable summary card.
