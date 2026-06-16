# revenuecat-webhook

Supabase Edge Function for RevenueCat webhooks.

## Behavior

1. Verify RevenueCat webhook authorization with a shared secret.
2. Store the raw event in `revenuecat_events`.
3. Resolve RevenueCat `app_user_id` to `auth.users.id`. Kinetriq uses the Supabase user UUID as the RevenueCat app user ID after login.
4. Upsert `subscriptions` for entitlement `kinetriq_pro`.
5. Mark entitlement active/inactive based on RevenueCat event type and entitlement state.

RevenueCat remains the source of truth for purchases. Supabase mirrors state so the future web UI can render subscription status quickly.

## Required secrets

- `SUPABASE_SERVICE_ROLE_KEY`
- `REVENUECAT_WEBHOOK_SECRET`
