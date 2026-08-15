# redeem-promo-code

Supabase Edge Function expected by `PromoRedemptionService`.

## Request

Authenticated user required.

```json
{ "code": "KINETRIQ-COMP" }
```

## Behavior

1. Read authenticated user from the Supabase JWT.
2. Normalize `code` to uppercase.
3. Find an active `promo_codes` row within `starts_at` / `expires_at`.
4. Enforce `max_redemptions` and one redemption per user/code.
5. Insert `promo_redemptions`.
6. Insert or update `account_entitlements`.
7. Increment `promo_codes.redemption_count`.

## Response

Return the shape decoded by the iOS app:

```json
{
  "entitlement": {
    "entitlement": "kinetriq_pro",
    "source": "manual_comp",
    "startsAt": "2026-06-10T00:00:00Z",
    "expiresAt": null,
    "active": true
  }
}
```

Use `source` values from `account_entitlements.source`: `promo_free_month`, `promo_discount`, or `manual_comp`.
