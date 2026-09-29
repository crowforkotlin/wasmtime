#!/bin/bash
set -euo pipefail
shopt -s nullglob

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

rm -rf dist
mkdir -p dist

echo ">>> Moving standalone files..."
for file in bins-*/*.msi bins-*/*.wasm; do
  mv "$file" dist/
done

if [[ -d "wasmtime-platform-header" ]]; then
  for file in wasmtime-platform-header/*; do
    mv "$file" dist/
  done
fi

echo ">>> Collecting all artifact packages..."
# All packages (CLI and C-API, all build modes) are already independent
# tarballs/zip archives. Just move them to dist/.
for file in bins-*/*.tar.* bins-*/*.zip; do
  mv "$file" dist/
done

echo ">>> Final dist/ contents:"
ls -l dist/
