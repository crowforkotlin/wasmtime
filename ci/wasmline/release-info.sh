#!/bin/bash
set -euo pipefail

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
  if [[ -n "${WASMTIME_RELEASE_TAG:-}" ]]; then
    printf '%s\n' "$WASMTIME_RELEASE_TAG"
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

version_from_ref() {
  local name
  name="$(ref_name 2>/dev/null || true)"

  case "$name" in
    release-v*)
      printf '%s\n' "${name#release-v}"
      return 0
      ;;
    v*)
      printf '%s\n' "${name#v}"
      return 0
      ;;
    release-*)
      printf '%s\n' "${name#release-}"
      return 0
      ;;
  esac

  return 1
}

resolved_version() {
  version_from_ref || workspace_version
}

artifact_tag() {
  printf 'v%s\n' "$(resolved_version)"
}

git_release_tag() {
  local name
  name="$(ref_name 2>/dev/null || true)"

  case "$name" in
    release-v*)
      printf '%s\n' "$name"
      return 0
      ;;
    v*)
      printf 'release-v%s\n' "${name#v}"
      return 0
      ;;
    release-*)
      printf 'release-v%s\n' "${name#release-}"
      return 0
      ;;
  esac

  printf 'release-v%s\n' "$(workspace_version)"
}

assert_match() {
  local version workspace
  version="$(resolved_version)"
  workspace="$(workspace_version)"

  if [[ "$version" != "$workspace" ]]; then
    echo "release version mismatch: ref resolves to '$version' but Cargo.toml has '$workspace'" >&2
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
  version)
    resolved_version
    ;;
  workspace-version)
    workspace_version
    ;;
  artifact-tag|tag)
    artifact_tag
    ;;
  git-tag)
    git_release_tag
    ;;
  is-release)
    version_from_ref >/dev/null
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
    echo "usage: $0 {version|workspace-version|artifact-tag|git-tag|is-release|assert-match|assert-capi-match|assert-workspace-deps-match}" >&2
    exit 1
    ;;
esac
