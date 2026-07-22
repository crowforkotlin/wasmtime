#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
usage: ci/wasmline/build-local-release.sh [<build-name> <target>]

Build the full local Wasmline release bundle for one target, then merge the
normal and minimal artifacts into dist/.

Defaults:
  build-name: x86_64-windows
  target:     x86_64-pc-windows-msvc
EOF
}

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

build_name="${1:-x86_64-windows}"
target="${2:-x86_64-pc-windows-msvc}"

export WASMTIME_RELEASE_TAG="release-v$(bash ./ci/release-info.sh workspace-version)"

echo ">>> Cleaning previous Wasmline release outputs..."
rm -rf dist bins-* target/c-api-build target/c-api-install "target/$target/release"

echo ">>> Building staged artifacts for $build_name ($target)..."
bash "$script_dir/build-target-release.sh" "$build_name" "$target"

echo ">>> Merging staged artifacts..."
bash "$script_dir/merge-artifacts.sh"

echo ">>> Done"
ls -l dist/
