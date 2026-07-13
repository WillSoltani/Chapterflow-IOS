#!/usr/bin/env bash
# Regression canaries for branch, normal-merge, squash-merge, missing-ref, and
# shallow-history provenance handling.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
verifier="$script_dir/verify-backend-contract-provenance.sh"
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/chapterflow-contract-provenance.XXXXXX")
contract_path=contracts/native-ios/v1/contract-bundle.json
trusted_main_ref=refs/remotes/origin/main
trap 'rm -rf "$tmp_root"' EXIT

fixture_repo=""
fixture_source=""

create_fixture() {
  local name=$1
  fixture_repo="$tmp_root/$name"
  git init -q "$fixture_repo"
  git -C "$fixture_repo" config user.email "contract-canary@example.invalid"
  git -C "$fixture_repo" config user.name "Contract Canary"
  mkdir -p "$fixture_repo/$(dirname "$contract_path")"
  printf '{"revision":"base"}\n' > "$fixture_repo/$contract_path"
  git -C "$fixture_repo" add "$contract_path"
  git -C "$fixture_repo" commit -q -m "base contract"
  git -C "$fixture_repo" branch -M main
  git -C "$fixture_repo" update-ref "$trusted_main_ref" HEAD

  git -C "$fixture_repo" switch -q -c contract-branch
  printf '{"revision":"branch"}\n' > "$fixture_repo/$contract_path"
  git -C "$fixture_repo" add "$contract_path"
  git -C "$fixture_repo" commit -q -m "contract branch"
  fixture_source=$(git -C "$fixture_repo" rev-parse HEAD)
}

run_verifier() {
  local repo=$1
  local revision=$2
  local phase=$3
  local main_ref=${4:-$trusted_main_ref}
  CHAPTERFLOW_BACKEND_REPO="$repo" \
    CONTRACT_SOURCE_REVISION="$revision" \
    CONTRACT_SOURCE_REVISION_PHASE="$phase" \
    CONTRACT_TRUSTED_MAIN_REF="$main_ref" \
    bash "$verifier"
}

expect_failure() {
  local label=$1
  shift
  if "$@" >"$tmp_root/$label.log" 2>&1; then
    echo "error: expected provenance canary to fail: $label" >&2
    exit 1
  fi
}

# Exact branch provenance succeeds only before either its commit or artifact is
# integrated. Missing refs and a false merged phase fail closed.
create_fixture branch
branch_repo=$fixture_repo
branch_source=$fixture_source
expect_failure missing-main run_verifier \
  "$branch_repo" "$branch_source" committed_backend_branch refs/remotes/origin/missing
expect_failure false-merged run_verifier \
  "$branch_repo" "$branch_source" merged_backend
run_verifier "$branch_repo" "$branch_source" committed_backend_branch

# A normal merge makes the exact branch revision reachable. It is valid merged
# provenance and invalid branch provenance.
create_fixture normal
normal_repo=$fixture_repo
normal_source=$fixture_source
git -C "$normal_repo" switch -q main
git -C "$normal_repo" merge -q --no-ff contract-branch -m "merge contract branch"
git -C "$normal_repo" update-ref "$trusted_main_ref" HEAD
git -C "$normal_repo" switch -q contract-branch
expect_failure normal-still-branch run_verifier \
  "$normal_repo" "$normal_source" committed_backend_branch
run_verifier "$normal_repo" "$normal_source" merged_backend

# A squash merge integrates the artifact without making the topic revision
# reachable. The old topic SHA is valid for neither phase; merged provenance
# must pin the actual reachable squash commit.
create_fixture squash
squash_repo=$fixture_repo
squash_topic_source=$fixture_source
git -C "$squash_repo" switch -q main
git -C "$squash_repo" merge -q --squash contract-branch >/dev/null
git -C "$squash_repo" commit -q -m "squash contract branch"
squash_source=$(git -C "$squash_repo" rev-parse HEAD)
git -C "$squash_repo" update-ref "$trusted_main_ref" "$squash_source"
git -C "$squash_repo" switch -q contract-branch
expect_failure squash-still-branch run_verifier \
  "$squash_repo" "$squash_topic_source" committed_backend_branch
expect_failure squash-topic-false-merged run_verifier \
  "$squash_repo" "$squash_topic_source" merged_backend
git -C "$squash_repo" switch -q main
run_verifier "$squash_repo" "$squash_source" merged_backend

# Blob-history evidence remains authoritative after a later main contract
# change; the old topic branch cannot become valid branch provenance again.
printf '{"revision":"later-main"}\n' > "$squash_repo/$contract_path"
git -C "$squash_repo" add "$contract_path"
git -C "$squash_repo" commit -q -m "later main contract"
git -C "$squash_repo" update-ref "$trusted_main_ref" HEAD
git -C "$squash_repo" switch -q contract-branch
expect_failure squash-history-still-integrated run_verifier \
  "$squash_repo" "$squash_topic_source" committed_backend_branch

# A shallow checkout cannot certify absence from main and must fail before any
# ancestry inference is accepted.
shallow_repo="$tmp_root/shallow"
git clone -q --depth 1 --branch contract-branch "file://$branch_repo" "$shallow_repo"
shallow_source=$(git -C "$shallow_repo" rev-parse HEAD)
git -C "$shallow_repo" update-ref "$trusted_main_ref" "$shallow_source"
expect_failure shallow-history run_verifier \
  "$shallow_repo" "$shallow_source" committed_backend_branch

echo "Backend contract provenance canaries passed."
