# delete-account

Supabase Edge Function for App Store account deletion compliance.

## Behavior

1. Require an authenticated user.
2. Delete or anonymize app-owned rows for the user.
3. Delete the Supabase Auth user through the admin API.
4. Preserve anonymized purchase/webhook audit records only if required for financial compliance.

The iOS app calls this function through `AuthService.requestAccountDeletion()`.

## Required secrets

- `SUPABASE_SERVICE_ROLE_KEY`
