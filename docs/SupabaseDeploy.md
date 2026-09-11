# Supabase deploy for 3.6.0

Everything here is done in the Supabase dashboard for the **Kinetriq** project. Do it
**before** installing the TestFlight build, or the app's Sync Now will fail with a
PostgREST `404` and the coach screens will error on `coach_roster()`.

Local history, the Progress tab, trends, and CSV export all work without any of
this — they are SwiftData on the device. Only sync and coaching need the backend.

Total time is a few minutes. Steps 1 and 2 are required; 3 onward are verification.

---

## 1. Apply the schema

**Dashboard → SQL Editor → New query.** Paste the entire contents of
`supabase/schema.sql` and run it.

The whole file is safe to re-run. Every statement is idempotent — tables are
`create table if not exists`, every `create policy` is preceded by
`drop policy if exists`, indexes are `if not exists`, functions are
`create or replace`, and triggers are dropped before creation. There is no
top-level seed data, so nothing duplicates. Pasting the whole file avoids
line-number archaeology and guarantees you cannot half-apply it.

New in 3.6.0, for reference:

| Object | Purpose |
|---|---|
| `analysis_records` | One row per analyzed session. **Measurements only — no video column.** |
| `analysis_reps` | One row per rep. `user_id` denormalized so RLS needs no join. |
| `coaches` | Coach profile + `client_limit` (the roster cap) |
| `coach_invites` | Server-generated 8-character codes |
| `coach_clients` | The coach ↔ client link, with `status` |
| `create_coach_invite(label)` | Mints a code, enforces `client_limit` |
| `redeem_coach_invite(code)` | Client accepts; raises named errors the app maps to plain language |
| `coach_roster()` | One round trip powering the roster's triage ordering |
| `public.touch_updated_at()` | Shared `updated_at` trigger |

It also adds two cross-account RLS policies — `"Coaches read linked client analyses"`
and `"Coaches read linked client reps"` — both gated on
`coach_clients.status = 'active'`. That is the only path by which one user's rows are
visible to another, and it grants **measurements only**.

If `create_coach_invite` errors on `profiles` not existing, the base schema was never
applied; run the file from the top rather than pasting a fragment.

## 2. Redeploy the RevenueCat webhook

The webhook changed in this release: it now mirrors the coach entitlement and writes
`coaches.client_limit`. Without this redeploy, every coach lands on the column
default of 15 regardless of which tier they bought — a Studio subscriber would be
capped at 15 clients and a Starter subscriber would get 15 instead of 5.

```bash
supabase functions deploy revenuecat-webhook
```

Nothing else changed, so the other functions do not need redeploying. If the CLI is
not linked yet: `supabase link --project-ref <your-project-ref>`.

No new secrets are needed. It still uses `REVENUECAT_WEBHOOK_SECRET`,
`SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY`.

## 3. Confirm the tables are live

**SQL Editor:**

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('analysis_records', 'analysis_reps',
                     'coaches', 'coach_invites', 'coach_clients')
order by table_name;
```

Expect five rows. Then confirm RLS is actually on — the tables are useless and unsafe
without it:

```sql
select relname, relrowsecurity
from pg_class
where relname in ('analysis_records', 'analysis_reps',
                  'coaches', 'coach_invites', 'coach_clients');
```

All five must show `relrowsecurity = true`.

And that the RPCs are callable by signed-in users:

```sql
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('create_coach_invite', 'redeem_coach_invite', 'coach_roster');
```

## 4. Verify sync end to end

On the TestFlight build, signed in:

1. Analyze any set.
2. **Settings → Progress Sync** should be on. Tap **Sync Now**.
3. In SQL Editor:

```sql
select recorded_at, movement_name, kind, total_reps, score, mean_peak_angle_deg
from analysis_records
order by recorded_at desc
limit 5;
```

Your session should be there within a second or two of the tap. If the list is empty,
check for an error under the Sync Now row in Settings — the app maps failures to
`SYNC-*` and `NET-*` codes rather than swallowing them.

**Then confirm the privacy claim holds.** This should return zero rows, now and after
every future migration:

```sql
select column_name, table_name
from information_schema.columns
where table_schema = 'public'
  and (column_name ilike '%video%' or column_name ilike '%thumbnail%'
       or column_name ilike '%media%' or column_name ilike '%file%');
```

There should also be no Storage buckets. The app tells users in writing that video
never leaves the device; this query is how you keep that honest.

## 5. Verify the coach flow

Needs two accounts. Use a second Apple ID or a throwaway email signup.

1. Sign in as the coach. **Settings → Coach → My Clients.** Because no coach products
   exist in App Store Connect yet, you will see the tier cards with a "not yet
   available for purchase" banner. That is expected.
2. To test the roster before the products exist, grant yourself the entitlement by
   hand:

```sql
-- Find your user id
select id, email from auth.users order by created_at desc limit 10;

-- Give yourself a coach record with a real limit
insert into coaches (user_id, display_name, client_limit)
values ('<your-uuid>', 'Test Coach', 15)
on conflict (user_id) do update set client_limit = 15;
```

That covers the Postgres side. The **app-side** gate is a RevenueCat entitlement, so
also grant `Kinetriq Coach` to that user in **RevenueCat → Customers → your app user
ID → Grant entitlement** (see `docs/CoachSubscriptionSetup.md`). Both are needed:
Postgres controls the roster cap, RevenueCat controls whether the app shows the
screens at all.

3. Create an invite in the app. Confirm a row appears:

```sql
select code, label, created_at, expires_at, redeemed_by from coach_invites;
```

4. Sign in as the client on a second device or after signing out. **Settings → Coach
   → Connect to a Coach.** Enter the code.
5. Back as the coach, pull to refresh the roster. The client should appear with
   "Hasn't started" until they analyze something.

Useful checks while testing:

```sql
-- The link
select * from coach_clients;

-- What the roster query returns (run as the coach via the app; this bypasses RLS)
select * from coach_roster();
```

`coach_roster()` reads `auth.uid()`, so running it in the SQL Editor as the dashboard
owner returns nothing. Test it through the app.

## Rollback

The schema is additive — no existing table or policy is modified — so a rollback is
just dropping the new objects. Note that this destroys synced history and all coach
links; device-local history is unaffected.

```sql
drop function if exists public.coach_roster();
drop function if exists public.redeem_coach_invite(text);
drop function if exists public.create_coach_invite(text);
drop table if exists coach_invites cascade;
drop table if exists coach_clients cascade;
drop table if exists coaches cascade;
drop table if exists analysis_reps cascade;
drop table if exists analysis_records cascade;
```

## Things worth knowing

- **`analysis_records.id` is client-generated.** The device knows the UUID before the
  first upload attempt, and sync upserts on it with
  `Prefer: resolution=merge-duplicates`. Retries are therefore safe and cannot
  duplicate a session.
- **Sync is one-way today.** The app pushes; it never pulls. A user who deletes and
  reinstalls gets an empty Progress tab even though their rows are in Postgres.
  Restore-on-reinstall is a deliberate follow-up, not an oversight.
- **`coaches.client_limit` is the only cap that matters.** It is enforced inside
  `create_coach_invite`, which counts active clients plus outstanding invites. Client
  limits are not enforced anywhere in the app, so they cannot be bypassed by patching
  the binary.
- **Never delete a `coaches` row to revoke access.** `coach_invites` and
  `coach_clients` cascade from it, so deleting it destroys the roster. The webhook
  sets `client_limit = 0` on a lapse instead, which blocks new invites while leaving
  existing clients linked so a renewal restores everything.
