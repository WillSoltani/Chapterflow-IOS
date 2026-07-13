#!/usr/bin/env bash
# Verifies that an iOS contract bundle points at the correct backend commit and
# uses a phase consistent with backend main. Exact blob-history matching makes
# the branch phase fail closed after GitHub squash-merges the backend PR.

set -euo pipefail

backend_repo=${CHAPTERFLOW_BACKEND_REPO:?CHAPTERFLOW_BACKEND_REPO is required}
source_revision=${CONTRACT_SOURCE_REVISION:?CONTRACT_SOURCE_REVISION is required}
source_phase=${CONTRACT_SOURCE_REVISION_PHASE:?CONTRACT_SOURCE_REVISION_PHASE is required}
main_ref=${CONTRACT_MAIN_REF:-origin/main}
contract_path=contracts/native-ios/v1/contract-bundle.json

if [[ ! "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: CONTRACT_SOURCE_REVISION must be a full lowercase Git SHA" >&2
  exit 1
fi
case "$source_phase" in
  committed_backend_branch|merged_backend) ;;
  *)
    echo "error: unsupported CONTRACT_SOURCE_REVISION_PHASE: $source_phase" >&2
    exit 1
    ;;
esac

actual_revision=$(git -C "$backend_repo" rev-parse HEAD)
if [[ "$actual_revision" != "$source_revision" ]]; then
  echo "error: backend checkout resolved $actual_revision instead of $source_revision" >&2
  exit 1
fi

contract_revision=$(git -C "$backend_repo" log -1 --format=%H -- "$contract_path")
if [[ "$contract_revision" != "$source_revision" ]]; then
  echo "error: pinned revision is not the exact commit that last changed the backend contract bundle" >&2
  exit 1
fi
if ! git -C "$backend_repo" rev-parse --verify "$main_ref^{commit}" >/dev/null 2>&1; then
  echo "error: backend main ref is missing or is not a commit: $main_ref" >&2
  exit 1
fi

is_ancestor=false
if git -C "$backend_repo" merge-base --is-ancestor "$source_revision" "$main_ref"; then
  is_ancestor=true
fi

# GitHub normally squash-merges this repository. A squash commit does not retain
# the topic SHA as an ancestor, so also search main's contract history for the
# exact pinned bundle blob. Searching history (not only the current main tree)
# keeps the gate truthful if a later contract change lands before this check.
is_integrated=$is_ancestor
if [[ "$is_integrated" == false ]]; then
  source_blob=$(git -C "$backend_repo" rev-parse "$source_revision:$contract_path")
  while IFS= read -r main_revision; do
    main_blob=$(git -C "$backend_repo" rev-parse "$main_revision:$contract_path" 2>/dev/null || true)
    if [[ "$main_blob" == "$source_blob" ]]; then
      is_integrated=true
      break
    fi
  done < <(git -C "$backend_repo" rev-list "$main_ref" -- "$contract_path")
fi

if [[ "$source_phase" == "committed_backend_branch" && "$is_integrated" == true ]]; then
  echo "error: pinned backend contract is integrated into main; refresh provenance as merged_backend" >&2
  exit 1
fi
if [[ "$source_phase" == "merged_backend" && "$is_ancestor" == false ]]; then
  echo "error: merged_backend provenance must pin an exact revision reachable from backend main" >&2
  exit 1
fi
