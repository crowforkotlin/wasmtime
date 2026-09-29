#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
usage: ci/wasmline/build-local-release.sh [<build-name> <target> [<wasmline-tag>]]

Build the full local Wasmline release bundle for one target, then merge the
normal and minimal artifacts into dist/.

Defaults:
  build-name: x86_64-windows
  target:     x86_64-pc-windows-msvc

Without a tag the packages use the development label. Pass a tag such as
v47.0.3.1 to reproduce release asset names locally.
EOF
}

if [[ $# -eq 1 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

build_name="${1:-x86_64-windows}"
target="${2:-x86_64-pc-windows-msvc}"
release_tag="${3:-${WASMLINE_RELEASE_TAG:-}}"

if [[ -n "$release_tag" ]]; then
  export WASMLINE_RELEASE_TAG="$release_tag"
  bash ./ci/wasmline/release-info.sh validate-tag
  bash ./ci/wasmline/release-info.sh assert-match
fi

echo ">>> Cleaning previous Wasmline release outputs..."
rm -rf dist bins-* target/c-api-build target/c-api-install "target/$target/release"

echo ">>> Building staged artifacts for $build_name ($target)..."
bash "$script_dir/build-target-release.sh" "$build_name" "$target"

echo ">>> Merging staged artifacts..."
bash "$script_dir/merge-artifacts.sh"

echo ">>> Done"
ls -l dist/
