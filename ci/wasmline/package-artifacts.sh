#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
usage: ci/wasmline/package-artifacts.sh <build-name> <target> [cli|capi|all]

Package the already-built Wasmline CLI and/or C API outputs into dist/.
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

build="$1"
target="$2"
component="${3:-all}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/wasmline-package.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p dist

tag=dev
if bash ./ci/wasmline/release-info.sh is-release; then
  bash ./ci/wasmline/release-info.sh assert-match
  bash ./ci/wasmline/release-info.sh assert-capi-match
  tag="$(bash ./ci/wasmline/release-info.sh artifact-tag)"
fi

# Derive package name parts from build name.
# build_name e.g. "aarch64-android", "aarch64-android-min", "aarch64-android-pulley-min"
base_pkgname="wasmtime-$tag-$build"
api_install="target/c-api-install"

# Determine archive format
case "$build" in
  *windows*) fmt=zip ;;
  *)         fmt=tar ;;
esac

mktarball() {
  local dir="$1"
  if [[ "$fmt" == "tar" ]]; then
    tar -czf "dist/$dir.tar.gz" -C "$tmp_dir" "$dir"
  else
    if command -v 7z >/dev/null 2>&1; then
      (cd "$tmp_dir" && 7z a "$repo_root/dist/$dir.zip" "$dir/" >/dev/null)
    elif command -v zip >/dev/null 2>&1; then
      (cd "$tmp_dir" && zip -rq "$repo_root/dist/$dir.zip" "$dir/")
    else
      echo "warning: no zip tool found; falling back to tar.gz" >&2
      tar -czf "dist/$dir.tar.gz" -C "$tmp_dir" "$dir"
    fi
  fi
}

# ── Package C API ─────────────────────────────────────────────────────────
if [[ "$component" == "capi" || "$component" == "all" ]]; then
  if [[ -d "$api_install/include" && -d "$api_install/lib" ]]; then
    api_pkgname="${base_pkgname}-c-api"
    mkdir -p "$tmp_dir/$api_pkgname"
    cp LICENSE README.md "$tmp_dir/$api_pkgname"

    if [[ "$build" == *-min ]]; then
      mkdir -p "$tmp_dir/$api_pkgname/min"
      cp -r "$api_install/include" "$tmp_dir/$api_pkgname/min"
      cp -r "$api_install/lib" "$tmp_dir/$api_pkgname/min"
    else
      cp -r "$api_install/include" "$tmp_dir/$api_pkgname"
      cp -r "$api_install/lib" "$tmp_dir/$api_pkgname"
    fi

    mktarball "$api_pkgname"
    echo "  packaged: $api_pkgname"
  else
    echo "  warning: C API install dir not found, skipping" >&2
  fi
fi

# ── Package CLI ───────────────────────────────────────────────────────────
if [[ "$component" == "cli" || "$component" == "all" ]]; then
  cli_pkgname="$base_pkgname"
  mkdir -p "$tmp_dir/$cli_pkgname"
  cp LICENSE README.md "$tmp_dir/$cli_pkgname"

  has_cli=false
  case "$fmt" in
    zip)
      if [[ -f "target/$target/release/wasmtime.exe" ]]; then
        cp "target/$target/release/wasmtime.exe" "$tmp_dir/$cli_pkgname/wasmtime.exe"
        has_cli=true
      fi
      ;;
    *)
      if [[ -f "target/$target/release/wasmtime" ]]; then
        cp "target/$target/release/wasmtime" "$tmp_dir/$cli_pkgname/wasmtime"
        has_cli=true
      fi
      ;;
  esac

  if [[ "$has_cli" == true ]]; then
    mktarball "$cli_pkgname"
    echo "  packaged: $cli_pkgname"
  else
    echo "  note: no CLI binary found, skipping CLI package"
  fi
fi
