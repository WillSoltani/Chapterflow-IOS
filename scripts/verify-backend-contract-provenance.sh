#!/usr/bin/env bash
# Verifies the Git-graph portion of a committed backend contract overlay.
# Exact input-byte fencing is performed by the backend generator itself.

set -euo pipefail

backend_repo=${CHAPTERFLOW_BACKEND_REPO:?CHAPTERFLOW_BACKEND_REPO is required}
source_revision=${CONTRACT_SOURCE_REVISION:?CONTRACT_SOURCE_REVISION is required}
source_phase=${CONTRACT_SOURCE_REVISION_PHASE:?CONTRACT_SOURCE_REVISION_PHASE is required}
trusted_main_ref=${CONTRACT_TRUSTED_MAIN_REF:?CONTRACT_TRUSTED_MAIN_REF is required}
contract_path=contracts/native-ios/v1/contract-bundle.json

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] \
  || fail "CONTRACT_SOURCE_REVISION must be a full lowercase Git SHA"
case "$source_phase" in
  committed_backend_branch|merged_backend) ;;
  *) fail "unsupported CONTRACT_SOURCE_REVISION_PHASE: $source_phase" ;;
esac
[[ "$trusted_main_ref" =~ ^refs/(heads|remotes)/[A-Za-z0-9._/-]+$ ]] \
  || fail "CONTRACT_TRUSTED_MAIN_REF must be an explicit refs/heads/... or refs/remotes/... ref"

shallow=$(git -C "$backend_repo" rev-parse --is-shallow-repository) \
  || fail "unable to determine whether backend history is complete"
[[ "$shallow" == "false" ]] \
  || fail "backend contract provenance requires complete non-shallow Git history"

resolved_revision=$(git -C "$backend_repo" rev-parse --verify "$source_revision^{commit}" 2>/dev/null) \
  || fail "backend source revision does not exist: $source_revision"
[[ "$resolved_revision" == "$source_revision" ]] \
  || fail "backend source revision did not resolve exactly"

backend_head=$(git -C "$backend_repo" rev-parse --verify 'HEAD^{commit}') \
  || fail "backend HEAD is not a commit"
[[ "$backend_head" == "$source_revision" ]] \
  || fail "backend HEAD $backend_head does not match CONTRACT_SOURCE_REVISION $source_revision"

git -C "$backend_repo" show-ref --verify --quiet "$trusted_main_ref" \
  || fail "trusted backend-main ref is missing: $trusted_main_ref"
trusted_main_revision=$(git -C "$backend_repo" rev-parse --verify "$trusted_main_ref^{commit}") \
  || fail "trusted backend-main ref is not a commit: $trusted_main_ref"

git -C "$backend_repo" cat-file -e "$source_revision:$contract_path" 2>/dev/null \
  || fail "source revision does not contain the canonical contract artifact"
[[ "$(git -C "$backend_repo" cat-file -t "$source_revision:$contract_path")" == "blob" ]] \
  || fail "canonical contract artifact is not a Git blob"

contract_revision=$(git -C "$backend_repo" log -1 --format=%H "$source_revision" -- "$contract_path") \
  || fail "unable to resolve the exact contract-changing revision"
[[ "$contract_revision" == "$source_revision" ]] \
  || fail "pinned revision is stale; it is not the exact commit that last changed the contract artifact"

source_is_in_main=false
if git -C "$backend_repo" merge-base --is-ancestor "$source_revision" "$trusted_main_revision"; then
  source_is_in_main=true
else
  ancestry_status=$?
  [[ "$ancestry_status" -eq 1 ]] \
    || fail "unable to establish ancestry against trusted backend main"
fi

source_blob=$(git -C "$backend_repo" rev-parse --verify "$source_revision:$contract_path") \
  || fail "unable to resolve source contract artifact blob"
history=$(git -C "$backend_repo" rev-list "$trusted_main_revision" -- "$contract_path") \
  || fail "unable to inspect trusted-main contract artifact history"
artifact_is_in_main=false
while IFS= read -r main_revision; do
  [[ -n "$main_revision" ]] || continue
  main_blob=$(git -C "$backend_repo" rev-parse --verify "$main_revision:$contract_path" 2>/dev/null || true)
  if [[ "$main_blob" == "$source_blob" ]]; then
    artifact_is_in_main=true
    break
  fi
done <<< "$history"

if [[ "$source_phase" == "committed_backend_branch" ]]; then
  [[ "$source_is_in_main" == "false" ]] \
    || fail "branch provenance is false; the exact source revision is reachable from trusted main"
  [[ "$artifact_is_in_main" == "false" ]] \
    || fail "branch provenance is false; the contract artifact is already integrated into trusted main"
else
  [[ "$source_is_in_main" == "true" ]] \
    || fail "merged_backend provenance must pin an exact revision reachable from trusted main"
fi

echo "Backend contract Git provenance passed ($source_revision; $source_phase; $trusted_main_ref@$trusted_main_revision)."
