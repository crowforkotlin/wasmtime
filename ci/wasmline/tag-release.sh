#!/bin/bash
set -euo pipefail

remote=origin
push=no
tag=

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

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
usage: ci/wasmline/tag-release.sh <vX.Y.Z.N> [--push] [--remote <name>]

Validate and create an immutable Wasmline downstream release tag on the current
support/wasmline-X branch. The release tag must be provided explicitly.

Examples:
  bash ./ci/wasmline/tag-release.sh v47.0.3.1
  bash ./ci/wasmline/tag-release.sh v47.0.3.1 --push
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      push=yes
      shift
      ;;
    --remote)
      if [[ $# -lt 2 ]]; then
        echo "--remote requires a remote name" >&2
        exit 1
      fi
      remote="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$tag" ]]; then
        echo "only one release tag may be specified" >&2
        usage >&2
        exit 1
      fi
      tag="$1"
      shift
      ;;
  esac
done

if [[ -z "$tag" ]]; then
  echo "a Wasmline release tag is required" >&2
  usage >&2
  exit 1
fi

export WASMLINE_RELEASE_TAG="$tag"
bash ./ci/wasmline/release-info.sh validate-tag

ensure_clean_checkout

version="$(bash ./ci/wasmline/release-info.sh upstream-version)"
revision="$(bash ./ci/wasmline/release-info.sh downstream-revision)"
bash ./ci/wasmline/release-info.sh assert-match
bash ./ci/wasmline/release-info.sh assert-capi-match
bash ./ci/wasmline/release-info.sh assert-workspace-deps-match

branch="$(git symbolic-ref --quiet --short HEAD || true)"
expected_branch="support/wasmline-${version%%.*}"
if [[ "$branch" != "$expected_branch" ]]; then
  echo "refusing to tag branch '${branch:-<detached HEAD>}'; expected '$expected_branch'" >&2
  exit 1
fi

upstream_tag="v$version"
if ! git rev-parse --quiet --verify "refs/tags/${upstream_tag}^{commit}" >/dev/null; then
  echo "official base tag is not available locally: $upstream_tag" >&2
  echo "run 'git fetch upstream --tags' and try again" >&2
  exit 1
fi
if ! git merge-base --is-ancestor "$upstream_tag" HEAD; then
  echo "current HEAD is not based on official tag $upstream_tag" >&2
  exit 1
fi

if ! remote_url="$(git remote get-url --push "$remote" 2>/dev/null)"; then
  echo "unknown Git remote: $remote" >&2
  exit 1
fi
case "$remote_url" in
  *github.com/bytecodealliance/wasmtime|*github.com/bytecodealliance/wasmtime.git|\
  *github.com:bytecodealliance/wasmtime|*github.com:bytecodealliance/wasmtime.git)
    echo "refusing to publish a Wasmline downstream tag to the official Wasmtime repository" >&2
    exit 1
    ;;
esac

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "refusing to reuse existing local tag: $tag" >&2
  exit 1
fi

if ! remote_tags="$(git ls-remote --tags "$remote" \
  "refs/tags/v${version}.*" \
  "refs/tags/wasmline-v${version}.*")"; then
  echo "unable to inspect release tags on remote '$remote'" >&2
  exit 1
fi
if awk -v ref="refs/tags/$tag" '$2 == ref || $2 == ref "^{}" { found = 1 } END { exit !found }' <<< "$remote_tags"; then
  echo "refusing to reuse existing remote tag: $tag" >&2
  exit 1
fi

highest_revision=0
existing_tags="$(awk '{print $2}' <<< "$remote_tags" | sed 's/\^{}$//; s#refs/tags/##' | sort -u)"
while IFS= read -r existing_tag; do
  if [[ "$existing_tag" =~ ^(wasmline-)?v[0-9]+\.[0-9]+\.[0-9]+\.([1-9][0-9]*)$ ]]; then
    existing_revision="${BASH_REMATCH[2]}"
    if (( existing_revision > highest_revision )); then
      highest_revision="$existing_revision"
    fi
  fi
done <<< "$existing_tags"

expected_revision=$((highest_revision + 1))
if (( revision != expected_revision )); then
  echo "invalid downstream revision for Wasmtime $version: got $revision, expected $expected_revision" >&2
  exit 1
fi

if [[ "$push" == yes ]]; then
  if ! remote_branch="$(git ls-remote --heads "$remote" "refs/heads/$branch")"; then
    echo "unable to inspect branch '$branch' on remote '$remote'" >&2
    exit 1
  fi
  remote_commit="$(awk 'NR == 1 {print $1}' <<< "$remote_branch")"
  if [[ -z "$remote_commit" ]]; then
    echo "branch '$branch' does not exist on '$remote'; push the branch before publishing a tag" >&2
    exit 1
  fi
  if [[ "$remote_commit" != "$(git rev-parse HEAD)" ]]; then
    echo "remote branch '$remote/$branch' does not point to the current HEAD" >&2
    echo "push the branch before publishing a tag" >&2
    exit 1
  fi
fi

git tag --annotate "$tag" --message "Wasmline Wasmtime $tag"
echo "created local tag: $tag"
echo "upstream Wasmtime version: $version"
echo "downstream revision: $revision"
echo "release tag: $tag"
echo "tag commit: $(git rev-parse HEAD)"

if [[ "$push" == yes ]]; then
  git push "$remote" "$tag"
  echo "pushed $tag to $remote"
else
  echo "tag not pushed; publish this existing tag with: git push $remote refs/tags/$tag"
fi
