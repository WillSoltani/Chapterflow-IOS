# Routing Notifications Extensions

Preserve exact destination and account identity across external processes.

## Packages

- [WP-EXT-01/Make extension process data owner-safe and transactional](./WP-EXT-01/SPEC.md) — Inbound capture remains import-before-clear while outbound shared snapshots are versioned, explicitly owner-bound, and recoverable.
- [WP-NOTIFY-01/Complete exact notification, widget, and Live Activity routing](./WP-NOTIFY-01/SPEC.md) — APNs registration state remains acknowledged and retryable; notification actions, widgets, Spotlight/Handoff, and Live Activities carry complete owner/destination identity and replay exactly once after auth.

## Boundary

This workstream owns 2 outcome packages. Packages still obey their own paths, dependencies, decisions, locks, validation, merge, and rollback contracts; the directory is not a shared write claim.
