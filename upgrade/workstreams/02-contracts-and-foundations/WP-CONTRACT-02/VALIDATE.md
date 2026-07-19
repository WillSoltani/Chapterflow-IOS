# Validate WP-CONTRACT-02

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-CONTRACT-02-01 | CONTRACT-01-DELETE-01 | `python3 -m unittest scripts.contracts.tests.UpgradeContractBundleTests.test_account_delete_body_and_reauth_shapes` | canonical confirmation/recent-auth request, errors, and idempotency facts are source-derived and exact | `results/contracts/account-delete.json` with iOS/backend source SHAs and match/pass counts |
| AC-CONTRACT-02-02 | CONTRACT-02-ASK-01 | `python3 -m unittest scripts.contracts.tests.UpgradeContractBundleTests.test_ask_sse_history_terminal_error_and_cancel` | request history plus SSE framing/error/terminal/cancellation shapes are complete and reject old JSON assumption | `results/contracts/ask.json` |
| AC-CONTRACT-02-03 | CONTRACT-03-AUDIO-01 | `python3 -m unittest scripts.contracts.tests.UpgradeContractBundleTests.test_narration_discriminator_rejects_invented_envelope` | raw narration-plan discriminator/segments/unknown policy match serializer source | `results/contracts/narration.json` |
| AC-CONTRACT-02-04 | CONTRACT-04-NOTEBOOK-01 | `python3 -m unittest scripts.contracts.tests.UpgradeContractBundleTests.test_notebook_capability_matrix_never_invents_crud` | verified capability matrix distinguishes supported operations from absent backend routes | `results/contracts/notebook.json` |
| AC-CONTRACT-02-05 | CONTRACT-05-PROVENANCE-01 | `python3 -m unittest scripts.contracts.tests.UpgradeContractBundleTests.test_regeneration_is_byte_identical_and_provenance_separate` | same sources regenerate byte-identically; source/deployed/evidence-type fields remain distinct | `results/contracts/provenance.json` plus fixture digests |
| AC-CONTRACT-02-05 | CONTRACT-05-BACKEND-HEAD-02 | `git -C /private/tmp/ChapterFlow-wp-contract-02-inspect rev-parse HEAD` | output is exactly `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; detached/read-only acquisition metadata names source and observation time | `results/contracts/backend-head.txt` |
| AC-CONTRACT-02-05 | CONTRACT-05-BACKEND-CHECK-03 | `npm --prefix /private/tmp/ChapterFlow-wp-contract-02-inspect run contract:native:check` | the repository-native contract check passes at the independently verified exact backend source SHA; deployed revision is still unknown | `results/contracts/backend-native-check.json` with command, backend SHA, exit status, match/pass/skip counts |

Each selector must match exactly one declared test and report zero failures/skips/waivers. Fixtures contain no secrets/private data and bind exact backend route/validator/serializer/storage anchors.

## Supporting gates

- `python3 -m unittest discover -s scripts/contracts/tests`
- `swift test --package-path Packages/Models --parallel`
- `swift test --package-path Packages/Networking --parallel`
- generator idempotence, candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any invented alias/route, authority-softening decode, nondeterministic generation, provenance conflation, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
