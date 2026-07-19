# Current Work Recovery

Reconcile active work without inheriting stale branches or touching owner state.

## Packages

- [WP-REC-01/Reconcile live work and establish a current-main recovery baseline](./WP-REC-01/SPEC.md) — Every active or dirty ChapterFlow worktree, branch, and open PR is classified against current main without touching owner work; only novel, non-stale work receives an explicit successor package.

## Boundary

This workstream owns 1 outcome package. Packages still obey their own paths, dependencies, decisions, locks, validation, merge, and rollback contracts; the directory is not a shared write claim.
