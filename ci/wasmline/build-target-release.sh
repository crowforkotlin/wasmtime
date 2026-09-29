#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
usage: ci/wasmline/build-target-release.sh <build-name> <target>

Build and stage all Wasmline artifact variants for one target.

64-bit desktop/server: 4 stages (cranelift + pulley, each full + min)
iOS (no JIT allowed):  2 stages (pulley only, full + min)
32-bit (no Cranelift):  2 stages (pulley only, full + min)

Outputs are staged into bins-<build-name>[-suffix]/ directories.
EOF
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

build_name="$1"
target="$2"

stage_dist() {
  local suffix="$1"
  local out_dir="bins-${build_name}${suffix}"

  mkdir -p "$out_dir"
  if compgen -G "dist/*" >/dev/null; then
    mv dist/* "$out_dir/"
  fi
  rm -rf dist
}

# Detect platform constraints
is_32bit=false
is_ios=false
case "$target" in
  armv7-*|i686-*|thumbv7*|riscv32*)
    is_32bit=true
    ;;
esac
case "$target" in
  *-apple-ios*)
    is_ios=true
    ;;
esac

echo ">>> Building all artifact variants for $build_name ($target)"
echo "    32-bit: $is_32bit, iOS: $is_ios"

# ── Helper: build + package one (mode, suffix, component) combo ──────────
build_stage() {
  local mode="$1"
  local suffix="$2"
  local component="$3"
  local label="$4"

  echo ">>> Building: $label"
  RUSTC_BOOTSTRAP=1 \
    bash "$script_dir/build-artifacts.sh" "$mode" "$build_name$suffix" "$target" "$component"
  bash "$script_dir/package-artifacts.sh" "$build_name$suffix" "$target" "$component"
  stage_dist "$suffix"
}

if [[ "$is_32bit" == true ]]; then
  # ── 32-bit: Pulley only (Cranelift has no 32-bit backend) ──────────────
  build_stage pulley     ""           capi  "pulley C-API"
  build_stage pulley-min "-pulley-min" capi  "pulley-min C-API"
elif [[ "$is_ios" == true ]]; then
  # ── iOS: Pulley only (iOS prohibits runtime code generation / JIT) ──────
  build_stage pulley     ""           capi  "pulley C-API"
  build_stage pulley-min "-pulley-min" capi  "pulley-min C-API"
else
  # ── 64-bit desktop/server: Cranelift (includes Pulley) + Pulley-only ──
  build_stage cranelift     ""            all   "cranelift CLI + C-API"
  build_stage cranelift-min "-min"        all   "cranelift-min CLI + C-API"
  build_stage pulley        "-pulley"     all   "pulley CLI + C-API"
  build_stage pulley-min    "-pulley-min" capi  "pulley-min C-API"
fi
