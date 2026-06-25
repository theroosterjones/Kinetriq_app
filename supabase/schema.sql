-- Kinetriq subscription/account backend baseline.
-- Apply in Supabase after reviewing project-specific policies.

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists subscriptions (
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

create table if not exists revenuecat_events (
  id uuid primary key default gen_random_uuid(),
  event_id text unique,
  app_user_id text,
  event_type text,
  payload jsonb not null,
  received_at timestamptz not null default now()
);

create table if not exists promo_codes (
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

create table if not exists promo_redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  code_id uuid not null references promo_codes(id),
  platform text,
  app_version text,
  redeemed_at timestamptz not null default now(),
  unique (user_id, code_id)
);

create table if not exists account_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entitlement text not null,
  source text not null check (source in ('revenuecat', 'promo_free_month', 'promo_discount', 'manual_comp')),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table profiles enable row level security;
alter table subscriptions enable row level security;
alter table revenuecat_events enable row level security;
alter table promo_codes enable row level security;
alter table promo_redemptions enable row level security;
alter table account_entitlements enable row level security;

drop policy if exists "Users can read their profile" on profiles;
create policy "Users can read their profile"
on profiles for select
using (auth.uid() = id);

drop policy if exists "Users can read their subscriptions" on subscriptions;
create policy "Users can read their subscriptions"
on subscriptions for select
using (auth.uid() = user_id);

drop policy if exists "Users can read their promo redemptions" on promo_redemptions;
create policy "Users can read their promo redemptions"
on promo_redemptions for select
using (auth.uid() = user_id);

drop policy if exists "Users can read their account entitlements" on account_entitlements;
create policy "Users can read their account entitlements"
on account_entitlements for select
using (auth.uid() = user_id);

-- Helpful indexes for the Edge Functions.
-- One subscription mirror row per user + entitlement (supports webhook upsert).
create unique index if not exists subscriptions_user_entitlement_idx
  on subscriptions (user_id, entitlement);
create index if not exists revenuecat_events_app_user_id_idx
  on revenuecat_events (app_user_id);
create index if not exists account_entitlements_user_active_idx
  on account_entitlements (user_id, active);

-- Mutations for subscription, promo, and account_entitlement tables should be
-- performed by Supabase Edge Functions using the service-role key only.
