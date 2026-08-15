# Kinetriq Supabase backend

Database schema and Edge Functions for accounts, subscriptions, and promo codes.
See `docs/WebBackend.md` for the design and `docs/Subscriptions.md` for the
end-to-end subscription flow.

## Layout

```text
supabase/
├── config.toml                    # per-function JWT settings
├── schema.sql                     # tables, RLS, indexes
└── functions/
    ├── _shared/utils.ts           # shared helpers (CORS, ISO dates, admin client)
    ├── redeem-promo-code/         # called by the iOS app (auth required)
    ├── revenuecat-webhook/        # called by RevenueCat (shared-secret auth)
    └── delete-account/            # called by the iOS app (auth required)
```

## 1. Apply the schema

In the Supabase SQL editor (or `psql`), run `schema.sql`. It is idempotent
(`create table if not exists`, `create index if not exists`).

## 2. Configure secrets

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically into
Edge Functions. Set the webhook secret manually:

```bash
supabase secrets set REVENUECAT_WEBHOOK_SECRET="<a-long-random-string>"
```

## 3. Deploy the functions

```bash
supabase link --project-ref gxurelxripxupcnmavef
supabase functions deploy redeem-promo-code
supabase functions deploy delete-account
supabase functions deploy revenuecat-webhook   # verify_jwt=false via config.toml
```

## 4. Wire RevenueCat

In RevenueCat → Project → Integrations → Webhooks:

- URL: `https://gxurelxripxupcnmavef.supabase.co/functions/v1/revenuecat-webhook`
- Authorization header: the same value as `REVENUECAT_WEBHOOK_SECRET`
  (the function accepts the raw value or a `Bearer <value>` form).

## Contracts (must stay in sync with the iOS app)

### `redeem-promo-code`
- Auth: `Authorization: Bearer <supabase access token>`
- Request: `{ "code": "KINETRIQ-COMP" }`
- Success: `{ "entitlement": { "entitlement", "source", "startsAt", "expiresAt", "active" } }`
- Decoded by `PromoRedemptionService`. Dates are **second-precision ISO-8601**
  (no milliseconds) because Swift's `.iso8601` decoder rejects fractional seconds.

### `delete-account`
- Auth: `Authorization: Bearer <supabase access token>`
- Request body: `{ "user_id": "<uuid>" }` (the function trusts the JWT, not the body)
- Removes app-owned rows, anonymizes `revenuecat_events`, deletes the auth user.

### `revenuecat-webhook`
- Auth: shared secret in the `Authorization` header.
- Stores the raw event in `revenuecat_events`, then mirrors `kinetriq_pro`
  state into `subscriptions` (RevenueCat stays the source of truth).
- Only events whose RevenueCat app user ID is a Supabase UUID are mirrored
  (the app sets the RevenueCat app user ID to the Supabase user UUID after login).
