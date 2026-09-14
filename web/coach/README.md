# Kinetriq coach dashboard

A static site. No build step, no bundler, no npm dependencies — `index.html`, one
stylesheet, and a handful of ES modules that talk to Supabase over REST.

Coaches sign in with the same Kinetriq account they use on the phone and see the same
roster, because both read the same Postgres tables through the same row-level security
policies. Nothing here is a second copy of the data.

**No video, anywhere.** `analysis_records` has no video column and the project has no
storage bucket, so the dashboard cannot show client footage even if a feature request
asked for it. That is the point: the privacy claim in the app, on the website, and in
the App Store listing all rest on video being device-only, and for clinicians it is
also what keeps a Kinetriq coach account outside HIPAA business-associate scope.

## Why no framework

The dashboard reads other people's health measurements and keeps a session token in
`localStorage`. A zero-dependency static folder has no supply chain to compromise, no
CDN in the request path, and nothing to keep patched. The Supabase surface it needs is
four auth endpoints and three table reads, which is roughly the same amount of code
`AuthService` and `CoachService` already hand-roll on iOS.

Practical consequence: **there is no HTML-string path in this app.** Everything renders
through `js/dom.js`, which only ever sets `textContent`. A client's display name or a
coaching note cannot become markup. Keep it that way — one `innerHTML` with a roster
value in it would be enough to read a coach's session token.

## Local development

```bash
cd web/coach
cp config.example.js config.js     # fill in your Supabase URL + anon key
python3 -m http.server 8765        # any static server will do
open http://127.0.0.1:8765/
```

`file://` will not work — ES modules require a real origin.

Add `http://127.0.0.1:8765` to **Supabase → Authentication → URL Configuration →
Redirect URLs** or email sign-in links will refuse to come back to your dev server.

## Tests

```bash
cd web/coach
npm test        # or: node --test
```

`package.json` has no dependencies. It exists so Node treats these files as ES modules
when running the tests.

The tests cover the logic that is **duplicated from Swift** and would otherwise drift
apart silently:

| File | Pins | Swift original |
|------|------|-----------------|
| `tests/triage.test.js` | Triage reasons, thresholds, queue order | `CoachTriage` |
| `tests/format.test.js` | Tempo 0.6-second rounding, score ramp | `TempoDurationFormatter`, `KColor.score` |
| `tests/csv.test.js` | Column names, RFC 4180 escaping, CRLF | `CSVExporter` |
| `tests/session.test.js` | Token refresh and "expired ≠ signed out" | `AuthService`, `AuthSession` |
| `tests/render.test.js` | The roster and client views rendering real Supabase shapes | — |

`render.test.js` stubs `globalThis.fetch` and supplies a ~50-line fake DOM, so it
exercises the whole stack the browser runs — transport, queries, triage ordering, and
view construction — including the entitlement states, the explicit `user_id` scoping,
and the fact that no client surface produces a `<video>` element. It cannot check
layout; that needs a browser.

If you change a threshold on one side, change it on the other and update both test
suites. A coach who sees a different client at the top of the queue on their phone than
in the browser has no reason to trust either ordering.

## Deploying

Any static host. There is nothing to build, so "deploy" means "upload this folder".

1. `cp config.example.js config.js` and fill in the project URL and anon key.
2. Upload the folder contents (including `config.js`).
3. Point a subdomain at it — `app.kinetriq.com` or `coach.kinetriq.com`. The
   Squarespace marketing site stays on the apex domain; see `docs/WebBackend.md`.
4. Add that origin to **Supabase → Authentication → URL Configuration**, as both the
   Site URL and a Redirect URL. Email sign-in links land on
   `https://your-host/path/#access_token=…`, and GoTrue will only redirect to an
   allow-listed origin.

`package.json` and `tests/` are harmless to upload but are not needed in production.

### Response headers worth setting

The page ships a strict `Content-Security-Policy` in a `<meta>` tag, which covers
scripts, styles, and connections. Two things can only be set as real headers, so
configure them on your host:

```
X-Frame-Options: DENY
Content-Security-Policy: frame-ancestors 'none'
Referrer-Policy: no-referrer
```

Browsers ignore `frame-ancestors` when it arrives via `<meta>`, which is why the meta
policy deliberately omits it rather than pretending.

## What gates access

There is no RevenueCat SDK in the browser and there should not be one. The gate is the
coach's own `coaches` row:

- **No row** → "this account isn't a coach account", with a pointer to the iOS app,
  which is where coach plans are sold.
- **`client_limit = 0`** → the subscription has lapsed. Existing clients stay visible
  and no new invites can be created.
- **`client_limit > 0`** → full dashboard.

That column is written by the `revenuecat-webhook` Edge Function and is the same value
Postgres enforces inside `create_coach_invite`. Gating on it means the dashboard cannot
be more permissive than the database — which is exactly what a client-side entitlement
check tends to become.

## Files

| Path | Purpose |
|------|---------|
| `index.html` | Shell, CSP, script tags |
| `styles.css` | Design tokens copied from `KinetriqTheme.swift` |
| `config.example.js` | Template for the gitignored `config.js` |
| `js/api.js` | GoTrue + PostgREST transport, token refresh, error wording |
| `js/session.js` | Token storage; "renewable ≠ signed out" |
| `js/coach.js` | Roster, invites, client sessions |
| `js/triage.js` | Port of `CoachTriage` |
| `js/format.js` | Port of `TempoDurationFormatter` and the score ramp |
| `js/csv.js` | Port of `CSVExporter` |
| `js/dom.js` | `textContent`-only element helpers |
| `js/views/` | Login, roster, client detail |
| `js/app.js` | Boot and hash routing |
