#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

workspace_version() {
  awk '
    $0 == "[workspace.package]" { in_ws = 1; next }
    /^\[/ { in_ws = 0 }
    in_ws && $1 == "version" {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' Cargo.toml
}

ref_name() {
  if [[ -n "${WASMLINE_RELEASE_TAG:-}" ]]; then
    printf '%s\n' "$WASMLINE_RELEASE_TAG"
    return 0
  fi

  if [[ -n "${GITHUB_REF_NAME:-}" ]]; then
    printf '%s\n' "$GITHUB_REF_NAME"
    return 0
  fi

  case "${GITHUB_REF:-}" in
    refs/tags/*|refs/heads/*)
      printf '%s\n' "${GITHUB_REF##*/}"
      return 0
      ;;
  esac

  return 1
}

parse_release_tag() {
  local tag="$1" component

  if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)\.([1-9][0-9]*)$ ]]; then
    for component in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; do
      if [[ ${#component} -gt 1 && "$component" == 0* ]]; then
        return 1
      fi
    done
    upstream_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    downstream_revision="${BASH_REMATCH[4]}"
    release_version="$upstream_version.$downstream_revision"
    return 0
  fi

  return 1
}

release_tag() {
  local tag
  tag="$(ref_name 2>/dev/null || true)"
  if ! parse_release_tag "$tag"; then
    echo "invalid Wasmline release tag: '${tag:-<none>}'" >&2
    echo "expected: vX.Y.Z.N (numeric components have no leading zero; N starts at 1)" >&2
    return 1
  fi
  printf '%s\n' "$tag"
}

upstream_version_from_ref() {
  local tag
  tag="$(release_tag)" || return 1
  parse_release_tag "$tag"
  printf '%s\n' "$upstream_version"
}

resolved_upstream_version() {
  upstream_version_from_ref 2>/dev/null || workspace_version
}

release_version_from_ref() {
  local tag
  tag="$(release_tag)" || return 1
  parse_release_tag "$tag"
  printf '%s\n' "$release_version"
}

downstream_revision_from_ref() {
  local tag
  tag="$(release_tag)" || return 1
  parse_release_tag "$tag"
  printf '%s\n' "$downstream_revision"
}

validate_tag() {
  if [[ $# -eq 1 ]]; then
    WASMLINE_RELEASE_TAG="$1" release_tag >/dev/null
  else
    release_tag >/dev/null
  fi
}

assert_match() {
  local version workspace
  version="$(upstream_version_from_ref)"
  workspace="$(workspace_version)"

  if [[ "$version" != "$workspace" ]]; then
    echo "release version mismatch: tag is based on Wasmtime '$version' but Cargo.toml has '$workspace'" >&2
    exit 1
  fi
}

assert_capi_match() {
  local version major minor patch
  version="$(workspace_version)"
  IFS=. read -r major minor patch <<< "$version"

  grep -q "^#define WASMTIME_VERSION \"$version\"$" crates/c-api/include/wasmtime.h || {
    echo "WASMTIME_VERSION in crates/c-api/include/wasmtime.h does not match Cargo.toml ($version)" >&2
    exit 1
  }
  grep -q "^#define WASMTIME_VERSION_MAJOR $major$" crates/c-api/include/wasmtime.h || {
    echo "WASMTIME_VERSION_MAJOR in crates/c-api/include/wasmtime.h does not match Cargo.toml ($major)" >&2
    exit 1
  }
  grep -q "^#define WASMTIME_VERSION_MINOR $minor$" crates/c-api/include/wasmtime.h || {
    echo "WASMTIME_VERSION_MINOR in crates/c-api/include/wasmtime.h does not match Cargo.toml ($minor)" >&2
    exit 1
  }
  grep -q "^#define WASMTIME_VERSION_PATCH $patch$" crates/c-api/include/wasmtime.h || {
    echo "WASMTIME_VERSION_PATCH in crates/c-api/include/wasmtime.h does not match Cargo.toml ($patch)" >&2
    exit 1
  }
}

assert_workspace_deps_match() {
  python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path('Cargo.toml')
text = root.read_text()

workspace_version = None
section = None
for line in text.splitlines():
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        section = stripped
    if section == '[workspace.package]' and stripped.startswith('version = '):
        workspace_version = re.search(r'"([^"]+)"', stripped).group(1)
        break

assert workspace_version is not None

def manifest_version(manifest: Path) -> str:
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

errors = []
section = None
for line in text.splitlines():
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        section = stripped
        continue
    if section != '[workspace.dependencies]' or 'path =' not in line or 'version =' not in line:
        continue
    path_match = re.search(r'path\s*=\s*["\']([^"\']+)["\']', line)
    ver_match = re.search(r'version\s*=\s*["\'](=?)([^"\']+)["\']', line)
    if not path_match or not ver_match:
        continue
    manifest = Path(path_match.group(1)) / 'Cargo.toml'
    expected = manifest_version(manifest)
    actual = ver_match.group(2)
    if actual != expected:
        errors.append(f'{path_match.group(1)} -> version {actual} should be {expected}')

if errors:
    print('workspace dependency version mismatches detected:', file=sys.stderr)
    for err in errors:
        print(f'  - {err}', file=sys.stderr)
    sys.exit(1)
PY
}

case "${1:-}" in
  version|upstream-version)
    resolved_upstream_version
    ;;
  workspace-version)
    workspace_version
    ;;
  release-version)
    release_version_from_ref
    ;;
  revision|downstream-revision)
    downstream_revision_from_ref
    ;;
  artifact-tag|git-tag|tag)
    release_tag
    ;;
  validate-tag)
    shift
    if [[ $# -gt 1 ]]; then
      echo "usage: $0 validate-tag [vX.Y.Z.N]" >&2
      exit 1
    fi
    validate_tag "$@"
    ;;
  is-release)
    release_tag >/dev/null 2>&1
    ;;
  assert-match)
    assert_match
    ;;
  assert-capi-match)
    assert_capi_match
    ;;
  assert-workspace-deps-match)
    assert_workspace_deps_match
    ;;
  *)
    echo "usage: $0 {version|upstream-version|workspace-version|release-version|revision|artifact-tag|git-tag|validate-tag|is-release|assert-match|assert-capi-match|assert-workspace-deps-match}" >&2
    exit 1
    ;;
esac
