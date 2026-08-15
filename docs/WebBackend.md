# Kinetriq web backend plan

Squarespace remains the marketing website. The product web app should live separately, for example:

```text
kinetriq.com          -> Squarespace marketing site
app.kinetriq.com      -> Kinetriq web app
```

The web app should use the same Supabase project and RevenueCat project as the iOS app.

## Supabase tables

Recommended baseline schema:

The checked-in starter schema lives at `supabase/schema.sql`.

```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  revenuecat_app_user_id text not null,
  entitlement text not null,
  product_id text,
  store text,
  active boolean not null default false,
  trial boolean not null default false,
  current_period_ends_at timestamptz,
  last_event_at timestamptz,
  updated_at timestamptz not null default now()
);

create table revenuecat_events (
  id uuid primary key default gen_random_uuid(),
  event_id text unique,
  app_user_id text,
  event_type text,
  payload jsonb not null,
  received_at timestamptz not null default now()
);

create table promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  type text not null check (type in ('free_month', 'discount', 'unlimited')),
  active boolean not null default true,
  max_redemptions integer,
  redemption_count integer not null default 0,
  starts_at timestamptz,
  expires_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create table promo_redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  code_id uuid not null references promo_codes(id),
  platform text,
  app_version text,
  redeemed_at timestamptz not null default now(),
  unique (user_id, code_id)
);

create table account_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entitlement text not null,
  source text not null,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
```

## Row-level security

Enable RLS on user-facing tables.

- Users can select their own `profiles`, `subscriptions`, `promo_redemptions`, and `account_entitlements`.
- Users should not directly insert/update entitlement tables.
- Edge Functions should use the service role key server-side only.
- `promo_codes` should not be publicly selectable unless you create a restricted admin dashboard.

## Edge Functions

Function contracts are scaffolded under `supabase/functions/`.

### `redeem-promo-code`

Input:

```json
{ "code": "KINETRIQ-COMP" }
```

Behavior:

1. Require an authenticated Supabase user.
2. Normalize the code to uppercase.
3. Verify code is active, within date window, and under redemption limit.
4. Reject repeat redemption when not allowed.
5. Insert `promo_redemptions`.
6. Insert or update `account_entitlements`.
7. Return the active entitlement in the shape expected by `PromoRedemptionService`.

### `revenuecat-webhook`

Behavior:

1. Verify the RevenueCat webhook authorization header or shared secret.
2. Store raw event in `revenuecat_events`.
3. Resolve RevenueCat `app_user_id` to Supabase `auth.users.id`.
4. Upsert `subscriptions`.
5. Keep RevenueCat as the source of truth and Supabase as the query mirror.

### `delete-account`

Behavior:

1. Require an authenticated user.
2. Delete or anonymize user-owned application data.
3. Delete the Supabase auth user with the service-role admin API.
4. Optionally leave revenue events anonymized for financial audit records.

## Web app MVP

Recommended stack:

- Next.js or React app hosted on Vercel, Netlify, or Supabase hosting.
- Supabase Auth for login.
- Subscription/account status queried from Supabase.
- RevenueCat Web Billing or Stripe through RevenueCat for web purchases later.

MVP pages:

- Login/signup.
- Account settings.
- Subscription status.
- Promo-code redemption.
- Manage billing link.
- Download iOS app link.

Later pages:

- Workout/session history.
- Exported analysis summaries.
- Trainer/client dashboard.
- Web upload/analysis if product direction supports it.
