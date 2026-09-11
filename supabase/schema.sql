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

-- Auto-provision a profile row whenever a new auth user is created (email/
-- password, Sign in with Apple, etc.). Sign-in only creates an `auth.users`
-- row; this keeps `profiles` in sync without app-side writes.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name'
    )
  )
  on conflict (id) do update
    set email = excluded.email,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

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


-- ===========================================================================
-- Analysis history (metrics only)
-- ===========================================================================
--
-- MEASUREMENTS SYNC. VIDEO DOES NOT.
--
-- There is deliberately no video column here and no storage bucket behind it.
-- Analyzed clips stay in the app's own container on the device. The app's privacy
-- claim, the App Store listing, and the HelpView copy all depend on that staying
-- true, and for physical therapists it is also what keeps Kinetriq out of
-- business-associate territory under HIPAA: a clinic deploying an app that holds
-- patient video is a materially different conversation from one that holds a
-- column of joint angles.
--
-- If a future release needs coach-visible video, it belongs in a separate,
-- explicitly opt-in table with its own retention policy — not a column added here.
--
-- Unlike the subscription tables above, these are written directly from the app
-- with the user's JWT rather than through an Edge Function, so they need INSERT
-- and UPDATE policies, not just SELECT.

create table if not exists analysis_records (
  -- Client-generated so an upload can be retried safely: the device already knows
  -- the id before the first attempt, and the sync path upserts on it.
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  recorded_at timestamptz not null,

  kind text not null check (kind in ('exercise', 'assessment')),
  -- Enum raw value (e.g. 'Squat'), stable across display-name changes.
  movement_key text not null,
  movement_name text not null,
  side text,
  plane text,
  source text check (source in ('savedVideo', 'liveCamera')),

  duration_seconds double precision,
  pose_detection_rate double precision,

  -- Exercise columns
  total_reps integer not null default 0,
  score integer check (score is null or (score between 0 and 100)),
  mean_peak_angle_deg double precision,
  mean_eccentric_seconds double precision,
  mean_concentric_seconds double precision,

  -- Assessment columns
  grade text check (grade is null or grade in ('A', 'B', 'C', 'D', 'F')),
  left_rom_deg double precision,
  right_rom_deg double precision,
  asymmetry_deg double precision,
  asymmetry_flag boolean not null default false,

  -- Structured payload mirroring `AnalysisPayload` on the client.
  average_angles jsonb not null default '[]'::jsonb,
  tempo_breakdown jsonb not null default '{}'::jsonb,
  sub_grades jsonb not null default '[]'::jsonb,
  details jsonb not null default '[]'::jsonb,
  insights jsonb not null default '[]'::jsonb,

  app_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists analysis_reps (
  record_id uuid not null references analysis_records(id) on delete cascade,
  -- Denormalized so row-level security can be evaluated without a join.
  user_id uuid not null references auth.users(id) on delete cascade,
  rep_number integer not null,
  peak_flexion_angle_deg double precision,
  eccentric_seconds double precision,
  pause_bottom_seconds double precision,
  concentric_seconds double precision,
  pause_top_seconds double precision,
  primary key (record_id, rep_number)
);

alter table analysis_records enable row level security;
alter table analysis_reps enable row level security;

drop policy if exists "Users can read their analyses" on analysis_records;
create policy "Users can read their analyses"
on analysis_records for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert their analyses" on analysis_records;
create policy "Users can insert their analyses"
on analysis_records for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their analyses" on analysis_records;
create policy "Users can update their analyses"
on analysis_records for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their analyses" on analysis_records;
create policy "Users can delete their analyses"
on analysis_records for delete
using (auth.uid() = user_id);

drop policy if exists "Users can read their reps" on analysis_reps;
create policy "Users can read their reps"
on analysis_reps for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert their reps" on analysis_reps;
create policy "Users can insert their reps"
on analysis_reps for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their reps" on analysis_reps;
create policy "Users can update their reps"
on analysis_reps for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their reps" on analysis_reps;
create policy "Users can delete their reps"
on analysis_reps for delete
using (auth.uid() = user_id);

-- The Progress tab and the coach roster both read "this user's movement X, newest
-- first", so index for exactly that.
create index if not exists analysis_records_user_recorded_idx
  on analysis_records (user_id, recorded_at desc);
create index if not exists analysis_records_user_movement_idx
  on analysis_records (user_id, movement_key, recorded_at desc);
create index if not exists analysis_reps_user_idx
  on analysis_reps (user_id);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists analysis_records_touch_updated_at on analysis_records;
create trigger analysis_records_touch_updated_at
  before update on analysis_records
  for each row execute function public.touch_updated_at();


-- ===========================================================================
-- Coaching (coach ↔ client links)
-- ===========================================================================
--
-- A coach sees their clients' MEASUREMENTS. They never see client video, because
-- video is not in this database at all — see the note above `analysis_records`.
-- Do not add a video column or bucket to satisfy a coach feature request; the
-- privacy claim in the app, on the website, and in the App Store listing all rest
-- on video being device-only, and for clinicians it is also what keeps a Kinetriq
-- coach account outside HIPAA business-associate scope.
--
-- Linking is invite-code based and always initiated by the coach, accepted by the
-- client. A client can revoke at any time by deleting their own `coach_clients`
-- row, which the RLS policies below permit.

create table if not exists coaches (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  business_name text,
  -- Mirrors the coach subscription tier. Kept here rather than read from
  -- RevenueCat at query time so the limit can be enforced inside
  -- `create_coach_invite` without a network call; the RevenueCat webhook is the
  -- intended writer.
  client_limit integer not null default 15,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists coach_invites (
  -- Short, human-typeable, uppercase. Generated server-side by
  -- `create_coach_invite` so a coach cannot mint codes past their client limit.
  code text primary key,
  coach_user_id uuid not null references coaches(user_id) on delete cascade,
  -- Optional note so a coach can tell unredeemed codes apart ("Jamie – knee rehab").
  label text,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null,
  redeemed_at timestamptz
);

create table if not exists coach_clients (
  coach_user_id uuid not null references coaches(user_id) on delete cascade,
  client_user_id uuid not null references auth.users(id) on delete cascade,
  display_name text,
  status text not null default 'active' check (status in ('active', 'paused', 'removed')),
  linked_at timestamptz not null default now(),
  primary key (coach_user_id, client_user_id)
);

alter table coaches enable row level security;
alter table coach_invites enable row level security;
alter table coach_clients enable row level security;

-- Coaches manage their own coach row.
drop policy if exists "Coaches read their own record" on coaches;
create policy "Coaches read their own record"
on coaches for select
using (auth.uid() = user_id);

drop policy if exists "Coaches create their own record" on coaches;
create policy "Coaches create their own record"
on coaches for insert
with check (auth.uid() = user_id);

drop policy if exists "Coaches update their own record" on coaches;
create policy "Coaches update their own record"
on coaches for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Invites are readable and revocable by the coach who owns them. Creation goes
-- through `create_coach_invite` so the client limit is actually enforced; there is
-- deliberately no INSERT policy here.
drop policy if exists "Coaches read their invites" on coach_invites;
create policy "Coaches read their invites"
on coach_invites for select
using (auth.uid() = coach_user_id);

drop policy if exists "Coaches delete their invites" on coach_invites;
create policy "Coaches delete their invites"
on coach_invites for delete
using (auth.uid() = coach_user_id);

-- Both sides of a link can see it. Only the two parties involved can end it.
drop policy if exists "Coach and client read their link" on coach_clients;
create policy "Coach and client read their link"
on coach_clients for select
using (auth.uid() = coach_user_id or auth.uid() = client_user_id);

drop policy if exists "Coach updates their link" on coach_clients;
create policy "Coach updates their link"
on coach_clients for update
using (auth.uid() = coach_user_id)
with check (auth.uid() = coach_user_id);

drop policy if exists "Coach or client ends the link" on coach_clients;
create policy "Coach or client ends the link"
on coach_clients for delete
using (auth.uid() = coach_user_id or auth.uid() = client_user_id);

-- The cross-account read. A coach can see an actively linked client's measurements
-- and nothing else; `paused` and `removed` links stop granting access immediately.
drop policy if exists "Coaches read linked client analyses" on analysis_records;
create policy "Coaches read linked client analyses"
on analysis_records for select
using (
  exists (
    select 1 from coach_clients cc
    where cc.coach_user_id = auth.uid()
      and cc.client_user_id = analysis_records.user_id
      and cc.status = 'active'
  )
);

drop policy if exists "Coaches read linked client reps" on analysis_reps;
create policy "Coaches read linked client reps"
on analysis_reps for select
using (
  exists (
    select 1 from coach_clients cc
    where cc.coach_user_id = auth.uid()
      and cc.client_user_id = analysis_reps.user_id
      and cc.status = 'active'
  )
);

create index if not exists coach_clients_coach_idx on coach_clients (coach_user_id);
create index if not exists coach_clients_client_idx on coach_clients (client_user_id);
create index if not exists coach_invites_coach_idx on coach_invites (coach_user_id);

drop trigger if exists coaches_touch_updated_at on coaches;
create trigger coaches_touch_updated_at
  before update on coaches
  for each row execute function public.touch_updated_at();


-- ---------------------------------------------------------------------------
-- create_coach_invite(label)
-- ---------------------------------------------------------------------------
-- Security definer so the client-limit check cannot be bypassed by writing to
-- `coach_invites` directly (which is why that table has no INSERT policy).
-- Counts active clients plus outstanding unredeemed invites, so a coach cannot
-- oversubscribe by generating codes ahead of time.

create or replace function public.create_coach_invite(label text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  limit_for_coach integer;
  committed integer;
  new_code text;
  attempts integer := 0;
begin
  if caller is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select c.client_limit into limit_for_coach from coaches c where c.user_id = caller;
  if limit_for_coach is null then
    raise exception 'NOT_A_COACH';
  end if;

  select
    (select count(*) from coach_clients cc
      where cc.coach_user_id = caller and cc.status <> 'removed')
    + (select count(*) from coach_invites ci
        where ci.coach_user_id = caller
          and ci.redeemed_by is null
          and (ci.expires_at is null or ci.expires_at > now()))
  into committed;

  if committed >= limit_for_coach then
    raise exception 'CLIENT_LIMIT_REACHED';
  end if;

  -- Crockford-style alphabet: no I, L, O, U, so a code read aloud or typed from a
  -- screenshot is unambiguous.
  loop
    attempts := attempts + 1;
    select string_agg(
      substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', (floor(random() * 32) + 1)::integer, 1),
      ''
    )
    from generate_series(1, 8)
    into new_code;

    exit when not exists (select 1 from coach_invites where code = new_code);
    if attempts > 10 then
      raise exception 'CODE_GENERATION_FAILED';
    end if;
  end loop;

  insert into coach_invites (code, coach_user_id, label, expires_at)
  values (new_code, caller, label, now() + interval '30 days');

  return new_code;
end;
$$;


-- ---------------------------------------------------------------------------
-- redeem_coach_invite(invite_code)
-- ---------------------------------------------------------------------------
-- The client half of linking. Security definer because the redeemer has no read
-- access to `coach_invites` — they know only the code, not who issued it.

create or replace function public.redeem_coach_invite(invite_code text)
returns table (coach_user_id uuid, coach_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  inv coach_invites%rowtype;
begin
  if caller is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into inv
  from coach_invites
  where code = upper(btrim(invite_code))
  for update;

  if not found then
    raise exception 'INVITE_NOT_FOUND';
  end if;
  if inv.redeemed_by is not null then
    raise exception 'INVITE_ALREADY_USED';
  end if;
  if inv.expires_at is not null and inv.expires_at < now() then
    raise exception 'INVITE_EXPIRED';
  end if;
  if inv.coach_user_id = caller then
    raise exception 'INVITE_SELF';
  end if;

  insert into coach_clients (coach_user_id, client_user_id, display_name)
  values (inv.coach_user_id, caller, inv.label)
  on conflict (coach_user_id, client_user_id)
    do update set status = 'active';

  update coach_invites
  set redeemed_by = caller, redeemed_at = now()
  where code = inv.code;

  return query
    select c.user_id, coalesce(c.business_name, c.display_name, 'Your coach')
    from coaches c
    where c.user_id = inv.coach_user_id;
end;
$$;


-- ---------------------------------------------------------------------------
-- coach_roster()
-- ---------------------------------------------------------------------------
-- Powers the roster screen's triage ordering in one round trip.
--
-- The roster is a triage queue, not a video inbox: what a coach needs first is
-- which of their clients to look at this week. So this returns the adherence gap
-- (`last_session_at`, `sessions_last_14_days`), the score direction
-- (`latest_score` vs `previous_score`), and any recent asymmetry flag — the three
-- signals the app sorts on — rather than a flat list of sessions.
--
-- Security definer, scoped by `cc.coach_user_id = auth.uid()`.

create or replace function public.coach_roster()
returns table (
  client_user_id uuid,
  display_name text,
  status text,
  linked_at timestamptz,
  last_session_at timestamptz,
  sessions_last_14_days integer,
  latest_score integer,
  previous_score integer,
  latest_movement text,
  open_asymmetry_flag boolean
)
language sql
security definer
set search_path = public
as $$
  select
    cc.client_user_id,
    coalesce(cc.display_name, p.display_name, p.email, 'Client') as display_name,
    cc.status,
    cc.linked_at,
    agg.last_session_at,
    coalesce(agg.sessions_last_14_days, 0)::integer,
    scores.latest_score,
    scores.previous_score,
    agg.latest_movement,
    coalesce(asym.open_asymmetry_flag, false)
  from coach_clients cc
  left join profiles p on p.id = cc.client_user_id
  left join lateral (
    select
      max(r.recorded_at) as last_session_at,
      count(*) filter (where r.recorded_at > now() - interval '14 days') as sessions_last_14_days,
      (select r2.movement_name
         from analysis_records r2
        where r2.user_id = cc.client_user_id
        order by r2.recorded_at desc
        limit 1) as latest_movement
    from analysis_records r
    where r.user_id = cc.client_user_id
  ) agg on true
  left join lateral (
    select
      (array_agg(r.score order by r.recorded_at desc))[1] as latest_score,
      (array_agg(r.score order by r.recorded_at desc))[2] as previous_score
    from analysis_records r
    where r.user_id = cc.client_user_id and r.score is not null
  ) scores on true
  left join lateral (
    select bool_or(r.asymmetry_flag) as open_asymmetry_flag
    from analysis_records r
    where r.user_id = cc.client_user_id
      and r.kind = 'assessment'
      and r.recorded_at > now() - interval '30 days'
  ) asym on true
  where cc.coach_user_id = auth.uid()
    and cc.status <> 'removed'
  order by cc.linked_at;
$$;

revoke all on function public.create_coach_invite(text) from public;
revoke all on function public.redeem_coach_invite(text) from public;
revoke all on function public.coach_roster() from public;
grant execute on function public.create_coach_invite(text) to authenticated;
grant execute on function public.redeem_coach_invite(text) to authenticated;
grant execute on function public.coach_roster() to authenticated;
