# Upgrade Results

This directory stores only the bounded planning checkpoint. It is not a mutable orchestration ledger
and package lanes never write here.

- [PLANNING_CHECKPOINT.md](PLANNING_CHECKPOINT.md) — resumable planning state and preservation proof.
- Future package evidence lives outside source worktrees under the `CHAPTERFLOW_EVIDENCE_ROOT`
  contract in [VALIDATION_POLICY.md](../VALIDATION_POLICY.md). The WP-REC-01 runner binds package ID,
  canonical repository head set, commands/environment, AC mapping, artifacts/digests, and outcomes.
- Do not copy build logs, private content, identifiers, credentials, receipts, or mutable event
  chains into `upgrade/`. Durable CI/PR records remain in their authoritative systems.
