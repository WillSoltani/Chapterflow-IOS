# Learning Progress Resume

Unify server-graded learning mutations and compose durable progress/resume.

## Packages

- [WP-LEARN-01/Unify server-graded quiz and durable review mutations](./WP-LEARN-01/SPEC.md) — Quiz and spaced review use server authority, a single durable mutation owner, explicit offline/pending grading, stable attempt identity, and truthful progress without optimistic local pass or duplicate submission.
- [WP-LOOP-01/Compose the complete learning loop and exact durable resume](./WP-LOOP-01/SPEC.md) — Read/listen, annotate/Ask, quiz/review, progress refresh, next chapter, relaunch, deep link, and exact resume are composed once through narrow owners with no stale or duplicate transition.

## Boundary

This workstream owns 2 outcome packages. Packages still obey their own paths, dependencies, decisions, locks, validation, merge, and rollback contracts; the directory is not a shared write claim.
