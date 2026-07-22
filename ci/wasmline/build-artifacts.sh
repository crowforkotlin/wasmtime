#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
usage: ci/wasmline/build-artifacts.sh <build-mode> [<build-name>] <target> [cli|capi|all]

Build the Wasmline-specific Wasmtime CLI and/or C API artifacts for one target.

Build modes:
  cranelift       Full build with Cranelift + Pulley
  cranelift-min   Optimised build with Cranelift + Pulley
  pulley          Full build with Pulley only (no Cranelift)
  pulley-min      Optimised build with Pulley only (no Cranelift)

Components:
  cli    Build only the wasmtime CLI binary
  capi   Build only the C API static library + headers
  all    Build both (default)

Examples:
  bash ./ci/wasmline/build-artifacts.sh cranelift x86_64-linux x86_64-unknown-linux-gnu all
  bash ./ci/wasmline/build-artifacts.sh pulley-min armv7-android armv7-linux-androideabi capi
EOF
}

if [[ $# -lt 2 || $# -gt 4 ]]; then
  usage >&2
  exit 1
fi

build="$1"
if [[ $# -ge 3 ]]; then
  build_name="$2"
  target="$3"
  component="${4:-all}"
else
  build_name=""
  target="$2"
  component="all"
fi

echo "Building Wasmline artifacts"
echo "  mode:      $build"
if [[ -n "$build_name" ]]; then
  echo "  build:     $build_name"
fi
echo "  target:    $target"
echo "  component: $component"

export CARGO_PROFILE_RELEASE_STRIP=debuginfo
export CARGO_PROFILE_RELEASE_PANIC=abort

flags=""
cmake_flags=""
build_std=""

if [[ "$build" == *-min ]]; then
  export CARGO_PROFILE_RELEASE_OPT_LEVEL=s
  export RUSTFLAGS="-Zlocation-detail=none ${RUSTFLAGS:-}"
  export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
  export CARGO_PROFILE_RELEASE_LTO=true

  build_std="-Zbuild-std=std,panic_abort"
  cmake_flags="-DWASMTIME_DISABLE_ALL_FEATURES=ON"
  cmake_flags="$cmake_flags -DWASMTIME_FEATURE_DISABLE_LOGGING=ON"
  cmake_flags="$cmake_flags -DWASMTIME_USER_CARGO_BUILD_OPTIONS:LIST=$build_std"

  cli_base_features="--no-default-features --features disable-logging"

  if [[ "$build" == "cranelift-min" ]]; then
    cli_feat_list="all-arch,run,pulley,compile,gc,gc-drc,pooling-allocator,component-model,component-model-async"
    flags="$cli_base_features --features $cli_feat_list"

    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_ALL_ARCH=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PULLEY=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_CRANELIFT=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PARALLEL_COMPILATION=OFF"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC_DRC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_ASYNC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_WASI=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL_ASYNC=ON"
  elif [[ "$build" == "pulley-min" ]]; then
    cli_feat_list="all-arch,run,pulley,gc,gc-drc,pooling-allocator,component-model,component-model-async"
    flags="$cli_base_features --features $cli_feat_list"

    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_ALL_ARCH=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PULLEY=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC_DRC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_ASYNC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_WASI=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL_ASYNC=ON"
  else
    echo "unknown minimal build mode: $build" >&2
    exit 1
  fi

  flags="$build_std $flags"
else
  if [[ "$build" == "pulley" ]]; then
    flags="--features all-arch,component-model,pulley"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PULLEY=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL=ON"
  else
    flags="--features all-arch,component-model"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL=ON"
  fi
fi

if [[ "$target" == "x86_64-pc-windows-msvc" ]]; then
  export CC=clang
  export CXX=clang++
elif [[ "$target" == "aarch64-unknown-linux-gnu" ]]; then
  export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER:-aarch64-linux-gnu-gcc}"
  export CC="${CC:-${CC_aarch64_unknown_linux_gnu:-aarch64-linux-gnu-gcc}}"
  export CXX="${CXX:-${CXX_aarch64_unknown_linux_gnu:-aarch64-linux-gnu-g++}}"
elif [[ "$target" == "x86_64-pc-windows-gnu" ]]; then
  export CC="${CC:-gcc}"
  export CXX="${CXX:-g++}"
fi

# ── CLI build ──────────────────────────────────────────────────────────────
if [[ "$component" == "cli" || "$component" == "all" ]]; then
  echo "Running Cargo build for Wasmtime CLI..."

  # Skip CLI for pulley-min on 32-bit Android: listenfd doesn't compile there.
  skip_cli=false
  if [[ "$build" == "pulley-min" ]]; then
    case "$target" in
    armv7-*-android* | i686-*-android*)
      skip_cli=true
      echo "  (skipping CLI build: listenfd incompatible with 32-bit Android)"
      ;;
    esac
  fi

  if [[ "$skip_cli" == false ]]; then
    cargo build --release --target "$target" -p wasmtime-cli $flags
  fi
fi

# ── C API build ────────────────────────────────────────────────────────────
if [[ "$component" == "capi" || "$component" == "all" ]]; then
  echo "Running CMake build for Wasmtime C API..."
  export RUSTFLAGS="${RUSTFLAGS:-} -C force-unwind-tables"

  if [[ "$build" != *-min ]]; then
    case "$target" in
    *-pc-windows-msvc | *-pc-windows-gnu)
      export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
      ;;
    *)
      export CARGO_PROFILE_RELEASE_LTO=true
      ;;
    esac
  fi

  # Clean stale CMake cache to avoid feature flags leaking between build modes
  rm -rf target/c-api-build target/c-api-install
  mkdir -p target/c-api-build
  cd target/c-api-build

  cmake \
    -G Ninja \
    ../../crates/c-api \
    $cmake_flags \
    -DCMAKE_BUILD_TYPE=Release \
    -DWASMTIME_TARGET="$target" \
    -DCMAKE_INSTALL_PREFIX=../c-api-install \
    -DCMAKE_INSTALL_LIBDIR=../c-api-install/lib

  cmake --build . --target install
fi
