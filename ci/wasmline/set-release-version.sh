#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <X.Y.Z|vX.Y.Z|release-vX.Y.Z>" >&2
  exit 1
fi

raw="$1"
version="$raw"
version="${version#release-v}"
version="${version#v}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid version: $raw" >&2
  exit 1
fi

python3 - <<'PY' "$version"
from pathlib import Path
import re
import sys

version = sys.argv[1]
major, minor, patch = version.split('.')

cargo = Path('Cargo.toml')
text = cargo.read_text()

def manifest_version(manifest: Path, workspace_version: str) -> str:
    section = None
    version = None
    for line in manifest.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            section = stripped
        if section == '[package]' and stripped.startswith('version = '):
            version = re.search(r'"([^"]+)"', stripped).group(1)
            break
        if section == '[package]' and stripped == 'version.workspace = true':
            version = workspace_version
            break
    if version is None:
        raise SystemExit(f'failed to determine package version for {manifest}')
    return version

section = None
new_lines = []
for line in text.splitlines():
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        section = stripped
    if section == '[workspace.package]' and stripped.startswith('version = '):
        line = re.sub(r'version\s*=\s*"[^"]+"', f'version = "{version}"', line)
    elif section == '[workspace.dependencies]' and 'path =' in line and 'version =' in line:
        path_match = re.search(r'path\s*=\s*["\']([^"\']+)["\']', line)
        ver_match = re.search(r'version\s*=\s*["\'](=?)([^"\']+)["\']', line)
        if path_match and ver_match:
            manifest = Path(path_match.group(1)) / 'Cargo.toml'
            dep_version = manifest_version(manifest, version)
            prefix = ver_match.group(1) or ''
            line = re.sub(r'version\s*=\s*["\']=?[^"\']+["\']', f'version = "{prefix}{dep_version}"', line)
    new_lines.append(line)
cargo.write_text('\n'.join(new_lines) + '\n')

header = Path('crates/c-api/include/wasmtime.h')
text = header.read_text()
text = re.sub(r'^#define WASMTIME_VERSION ".*"$', f'#define WASMTIME_VERSION "{version}"', text, flags=re.M)
text = re.sub(r'^#define WASMTIME_VERSION_MAJOR .*$', f'#define WASMTIME_VERSION_MAJOR {major}', text, flags=re.M)
text = re.sub(r'^#define WASMTIME_VERSION_MINOR .*$', f'#define WASMTIME_VERSION_MINOR {minor}', text, flags=re.M)
text = re.sub(r'^#define WASMTIME_VERSION_PATCH .*$', f'#define WASMTIME_VERSION_PATCH {patch}', text, flags=re.M)
header.write_text(text)
PY

echo "updated workspace release version to $version"
echo "- Cargo.toml [workspace.package]"
echo "- Cargo.toml [workspace.dependencies] path versions (synchronized to each local crate manifest)"
echo "- crates/c-api/include/wasmtime.h"

bash ./ci/wasmline/release-info.sh assert-match
bash ./ci/wasmline/release-info.sh assert-capi-match
bash ./ci/wasmline/release-info.sh assert-workspace-deps-match
