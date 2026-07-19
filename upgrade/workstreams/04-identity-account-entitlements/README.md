# Identity Account Entitlements

Protect session, Keychain, account status, deletion, and authority boundaries.

## Packages

- [WP-AUTH-02/Align Keychain scope and reauthentication truth](./WP-AUTH-02/SPEC.md) — Main entitlements, AuthKit, and Persistence share one fail-closed Keychain contract; simulator/static proof completes here and signed runtime proof remains in final device qualification.
- [WP-ACCOUNT-02/Make account deletion and backend account status fail closed](./WP-ACCOUNT-02/SPEC.md) — Deletion sends the exact confirmed recent-auth contract, produces truthful lifecycle states, and backend account-status lookup failure cannot authorize a deleted or disabled account.
- [WP-ENTRY-01/Make onboarding durable, adaptive, and localized](./WP-ENTRY-01/SPEC.md) — First-use step/permission recovery closes compact/iPad, localization, accessibility, and account-transition states.
- [WP-PAYWALL-01/Make paywall and entitlement reconciliation truthful](./WP-PAYWALL-01/SPEC.md) — Purchase/restore states remain distinct and only verified server entitlement grants access.

## Boundary

This workstream owns 4 outcome packages. Packages still obey their own paths, dependencies, decisions, locks, validation, merge, and rollback contracts; the directory is not a shared write claim.
