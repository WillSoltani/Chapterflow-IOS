#!/usr/bin/env bash
# Regression canaries for branch, merge, and squash-merge provenance handling.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
verifier="$script_dir/verify-backend-contract-provenance.sh"
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/chapterflow-contract-provenance.XXXXXX")
backend_repo="$tmp_root/backend"
contract_path=contracts/native-ios/v1/contract-bundle.json
trap 'rm -rf "$tmp_root"' EXIT

git init -q "$backend_repo"
git -C "$backend_repo" config user.email "contract-canary@example.invalid"
git -C "$backend_repo" config user.name "Contract Canary"
mkdir -p "$backend_repo/$(dirname "$contract_path")"
printf '{"revision":"base"}\n' > "$backend_repo/$contract_path"
git -C "$backend_repo" add "$contract_path"
git -C "$backend_repo" commit -q -m "base contract"
git -C "$backend_repo" branch -M main
base_revision=$(git -C "$backend_repo" rev-parse HEAD)
git -C "$backend_repo" update-ref refs/remotes/origin/main "$base_revision"

git -C "$backend_repo" switch -q -c contract-branch
printf '{"revision":"branch"}\n' > "$backend_repo/$contract_path"
git -C "$backend_repo" add "$contract_path"
git -C "$backend_repo" commit -q -m "contract branch"
source_revision=$(git -C "$backend_repo" rev-parse HEAD)

run_verifier() {
  local phase=$1
  local main_ref=${2:-origin/main}
  CHAPTERFLOW_BACKEND_REPO="$backend_repo" \
    CONTRACT_SOURCE_REVISION="$source_revision" \
    CONTRACT_SOURCE_REVISION_PHASE="$phase" \
    CONTRACT_MAIN_REF="$main_ref" \
    bash "$verifier"
}

expect_failure() {
  local phase=$1
  local main_ref=${2:-origin/main}
  if run_verifier "$phase" "$main_ref" >"$tmp_root/verifier.log" 2>&1; then
    echo "error: expected $phase provenance verification to fail" >&2
    exit 1
  fi
}

# Missing main evidence must fail closed rather than leaking through process substitution.
expect_failure committed_backend_branch refs/remotes/origin/missing

# The topic revision is valid while its contract content is absent from main.
run_verifier committed_backend_branch

# A squash merge has equivalent contract content but no topic-commit ancestry.
git -C "$backend_repo" switch -q main
git -C "$backend_repo" merge -q --squash contract-branch >/dev/null
git -C "$backend_repo" commit -q -m "squash contract branch"
squash_revision=$(git -C "$backend_repo" rev-parse HEAD)
git -C "$backend_repo" update-ref refs/remotes/origin/main "$squash_revision"
git -C "$backend_repo" switch -q contract-branch
expect_failure committed_backend_branch
expect_failure merged_backend

# The squash evidence remains discoverable after a later main contract change.
git -C "$backend_repo" switch -q main
printf '{"revision":"later-main"}\n' > "$backend_repo/$contract_path"
git -C "$backend_repo" add "$contract_path"
git -C "$backend_repo" commit -q -m "later main contract"
later_main_revision=$(git -C "$backend_repo" rev-parse HEAD)
git -C "$backend_repo" update-ref refs/remotes/origin/main "$later_main_revision"
git -C "$backend_repo" switch -q contract-branch
expect_failure committed_backend_branch

# A true merged phase must pin the reachable main revision exactly.
git -C "$backend_repo" update-ref refs/remotes/origin/main "$source_revision"
run_verifier merged_backend

echo "Backend contract provenance canaries passed."
