#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

helper="./ci/wasmline/release-info.sh"
workspace="$(bash "$helper" workspace-version)"
tag="v${workspace}.7"

run_without_ref() {
  env -u WASMLINE_RELEASE_TAG -u GITHUB_REF_NAME -u GITHUB_REF bash "$helper" "$@"
}

run_with_tag() {
  env -u GITHUB_REF_NAME -u GITHUB_REF WASMLINE_RELEASE_TAG="$tag" bash "$helper" "$@"
}

run_with_github_ref_name() {
  env -u WASMLINE_RELEASE_TAG -u GITHUB_REF GITHUB_REF_NAME="$tag" bash "$helper" "$@"
}

run_with_github_ref() {
  env -u WASMLINE_RELEASE_TAG -u GITHUB_REF_NAME GITHUB_REF="refs/tags/$tag" bash "$helper" "$@"
}

assert_output() {
  local expected="$1"
  shift
  local actual
  actual="$("$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_output "$workspace" run_without_ref version
assert_output "$workspace" run_with_tag upstream-version
assert_output "${workspace}.7" run_with_tag release-version
assert_output "7" run_with_tag downstream-revision
assert_output "$tag" run_with_tag artifact-tag
assert_output "$tag" run_with_github_ref_name git-tag
assert_output "$tag" run_with_github_ref tag
run_with_tag assert-match

for invalid in \
  "release-v${workspace}" \
  "wasmline-v${workspace}.1" \
  "v${workspace}" \
  "v${workspace}.0" \
  "v${workspace}.01" \
  "v0${workspace}.1" \
  "v${workspace}.1-extra"; do
  if bash "$helper" validate-tag "$invalid" >/dev/null 2>&1; then
    echo "invalid tag was accepted: $invalid" >&2
    exit 1
  fi
done

IFS=. read -r major minor patch <<< "$workspace"
mismatch="v${major}.${minor}.$((patch + 1)).1"
if WASMLINE_RELEASE_TAG="$mismatch" bash "$helper" assert-match >/dev/null 2>&1; then
  echo "mismatched upstream version was accepted: $mismatch" >&2
  exit 1
fi

echo "release-info tests passed"
