#!/bin/bash
set -euo pipefail

remote=origin
push=no
explicit_tag=

ensure_clean_checkout() {
  if [[ -n "$(git status --porcelain)" ]]; then
    cat >&2 <<'EOF'
refusing to create a release tag from a dirty checkout.

`ci/wasmline/tag-release.sh` tags the current HEAD commit only; uncommitted or untracked
files are NOT included in the tag that GitHub Actions will build.

Please commit, stash, or clean your changes first, then rerun this script.
EOF
    git status --short >&2
    exit 1
  fi
}

usage() {
  cat <<'EOF'
usage: ci/wasmline/tag-release.sh [--push] [--remote <name>] [release-vX.Y.Z]

Create the release tag for the current checkout based on Cargo.toml's
[workspace.package].version, or verify an explicitly provided tag.

Examples:
  bash ./ci/wasmline/tag-release.sh
  bash ./ci/wasmline/tag-release.sh --push
  bash ./ci/wasmline/tag-release.sh release-v43.0.0 --push
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      push=yes
      shift
      ;;
    --remote)
      remote="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    release-v*|v*)
      explicit_tag="$1"
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$explicit_tag" ]]; then
  export WASMTIME_RELEASE_TAG="$explicit_tag"
fi

ensure_clean_checkout

tag="$(bash ./ci/wasmline/release-info.sh git-tag)"
version="$(bash ./ci/wasmline/release-info.sh version)"
bash ./ci/wasmline/release-info.sh assert-match
bash ./ci/wasmline/release-info.sh assert-capi-match
bash ./ci/wasmline/release-info.sh assert-workspace-deps-match

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "tag already exists locally: $tag"
else
  git tag "$tag"
  echo "created local tag: $tag"
fi

echo "release version: $version"
echo "release tag: $tag"
echo "tag commit: $(git rev-parse HEAD)"

if [[ "$push" == yes ]]; then
  git push "$remote" "$tag"
  echo "pushed $tag to $remote"
else
  echo "tag not pushed; run with --push to publish it"
fi
