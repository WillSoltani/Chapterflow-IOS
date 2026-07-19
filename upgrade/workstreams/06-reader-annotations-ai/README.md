# Reader Annotations Ai

Make reading, annotations, bookmarks, notes, and Ask coherent and contract-correct.

## Packages

- [WP-READER-01/Make reading controls, chapter navigation, and preferences coherent](./WP-READER-01/SPEC.md) — Reader state has one owner; chapter/tone/depth/preference work cancels safely; controls remain reachable and accessible; chapter navigation preserves exact context across background, relaunch, and size changes.
- [WP-ANNOTATE-01/Align notes, highlights, and bookmarks with one durable contract](./WP-ANNOTATE-01/SPEC.md) — Notes, highlights, and bookmarks use one account-scoped mutation owner and a verified backend-compatible contract; offline writes remain recoverable and UI reports queued/syncing/failed/synced truthfully.
- [WP-ASK-01/Make Ask streaming, privacy, and citations exact](./WP-ASK-01/SPEC.md) — Ask uses the verified canonical transport and intended book/chapter/selection context, streams cancellation-safely, exposes quota/offline/error states, and routes each citation to an exact valid source.

## Boundary

This workstream owns 3 outcome packages. Packages still obey their own paths, dependencies, decisions, locks, validation, merge, and rollback contracts; the directory is not a shared write claim.
