#!/bin/bash

# A script to build the release artifacts of Wasmtime into the `target`
# directory.
#
# Arguments:
# $1: Build Configuration (e.g., cranelift-min, pulley-min, cranelift, pulley)
# $2: [Optional] OS Tag (e.g., windows) - ignored by logic, but used in CI
# $3: [Optional] Rust Target Triple. If $3 is empty, $2 is treated as the target.

set -ex

# === Argument Parsing Logic ===
build=$1
if [ -n "$3" ]; then
  # 3 arguments provided: build_mode os_tag target
  target=$3
else
  # 2 arguments provided: build_mode target
  target=$2
fi

if [ -z "$target" ]; then
  echo "Error: Target architecture must be provided."
  exit 1
fi

echo "Building with mode: $build"
echo "Target architecture: $target"

# Default build flags for release artifacts.
export CARGO_PROFILE_RELEASE_STRIP=debuginfo
export CARGO_PROFILE_RELEASE_PANIC=abort

# Initialize variables
flags=""
cmake_flags=""
build_std=""
build_std_features=""

# --- Configuration Logic ---

if [[ "$build" == *-min ]]; then
  # === Minimal Build Configuration ===
  
  # Optimization flags for size and speed
  export CARGO_PROFILE_RELEASE_OPT_LEVEL=s
  export RUSTFLAGS="-Zlocation-detail=none $RUSTFLAGS"
  export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
  export CARGO_PROFILE_RELEASE_LTO=true
  
  # Build standard library from source for size reduction
  build_std="-Zbuild-std=std,panic_abort"
  build_std_features="-Zbuild-std-features=std_detect_dlsym_getauxval"
  
  # Base CMake flags: Disable all features first
  # Note: This automatically adds `--no-default-features` to the C-API cargo build
  cmake_flags="-DWASMTIME_DISABLE_ALL_FEATURES=ON"
  cmake_flags="$cmake_flags -DWASMTIME_FEATURE_DISABLE_LOGGING=ON"
  
  # Pass build-std flags to C-API via USER_CARGO_BUILD_OPTIONS
  # We use semicolons for the CMake list.
  cmake_flags="$cmake_flags -DWASMTIME_USER_CARGO_BUILD_OPTIONS:LIST=$build_std;$build_std_features"

  # Base features for CLI
  cli_base_features="--no-default-features --features disable-logging"

  if [[ "$build" == "cranelift-min" ]]; then
    # --- Cranelift Min ---
    
    # 1. CLI Flags: Pass the exact features you requested
    # run, compile, gc, gc-drc, parallel-compilation, stack-switching, pooling-allocator, component-model, component-model-async
    cli_feat_list="run,compile,gc,gc-drc,parallel-compilation,stack-switching,pooling-allocator,component-model,component-model-async"
    flags="$cli_base_features --features $cli_feat_list"

    # 2. C-API Flags (CMake): Map CLI features to C-API equivalents
    # Note: 'run' is not a C-API feature.
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_CRANELIFT=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC_DRC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PARALLEL_COMPILATION=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_POOLING_ALLOCATOR=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_ASYNC=ON" 

  elif [[ "$build" == "pulley-min" ]]; then
    # --- Pulley Min ---
    f
    # 1. CLI Flags
    cli_feat_list="run,pulley,gc,gc-drc,stack-switching,pooling-allocator,component-model,component-model-async"
    flags="$cli_base_features --features $cli_feat_list"

    # 2. C-API Flags (CMake)
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PULLEY=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC_DRC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_POOLING_ALLOCATOR=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_ASYNC=ON"
    
  else
    echo "Unknown min configuration: $build"
    exit 1
  fi

  # Add build-std to CLI flags
  flags="$build_std $build_std_features $flags"

else
  # === Full Build Configuration ===
  
  if [[ "$build" == "pulley" ]]; then
    flags="--features all-arch,component-model,pulley"
    # Ensure Pulley is enabled in C-API
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PULLEY=ON"
  else
    # Default / cranelift full
    flags="--features all-arch,component-model"
  fi
fi

# --- Platform Specific Overrides ---

if [[ "$target" = "x86_64-pc-windows-msvc" ]]; then
  # Avoid emitting `/DEFAULTLIB:MSVCRT` into the static library by using clang.
  export CC=clang
  export CXX=clang++
fi

# --- Build CLI ---
echo "Running Cargo Build for CLI..."
cargo build --release --target "$target" -p wasmtime-cli $flags

# --- Build C API ---
echo "Running CMake Build for C-API..."

# For the C API force unwind tables to be emitted
export RUSTFLAGS="$RUSTFLAGS -C force-unwind-tables"

# Shrink the size of `*.a` artifacts for non-min builds
if [[ "$build" != *-min ]]; then
  case $target in
    *-pc-windows-msvc | *-pc-windows-gnu)
      export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
      ;;
    *)
      export CARGO_PROFILE_RELEASE_LTO=true
      ;;
  esac
fi

mkdir -p target/c-api-build
cd target/c-api-build

# Invoke CMake
cmake \
  -G Ninja \
  ../../crates/c-api \
  $cmake_flags \
  -DCMAKE_BUILD_TYPE=Release \
  -DWASMTIME_TARGET="$target" \
  -DCMAKE_INSTALL_PREFIX=../c-api-install \
  -DCMAKE_INSTALL_LIBDIR=../c-api-install/lib

cmake --build . --target install
