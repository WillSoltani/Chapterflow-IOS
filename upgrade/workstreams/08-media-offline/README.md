# Media Offline

Make narration, downloads, storage, and offline/reconnect behavior recoverable.

## Packages

- [WP-AUDIO-01/Align narration and harden background playback](./WP-AUDIO-01/SPEC.md) — Narration plans decode the verified contract; one media-state owner handles streaming, expired URLs, interruption, route change, backgrounding, cancellation, progress, and text-reading fallback truthfully.
- [WP-OFFLINE-01/Make downloads and offline synchronization restorable](./WP-OFFLINE-01/SPEC.md) — Book assets, progress, and eligible mutations download/sync with stable identities, truthful state, bounded storage, resume/relaunch recovery, safe eviction, and no premature completion or silent loss.

## Boundary

This workstream owns 2 outcome packages. Packages still obey their own paths, dependencies, decisions, locks, validation, merge, and rollback contracts; the directory is not a shared write claim.
