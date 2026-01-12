#!/bin/bash

# Arguments:
# $1: Build Configuration (e.g., cranelift-min, cranelift)
# $2: Build Name (e.g. x86_64-windows)
# $3: Target Triple (e.g. x86_64-pc-windows-msvc)

set -ex

build=$1
if [ -n "$3" ]; then
  target=$3
else
  target=$2
fi

if [ -z "$target" ]; then
  echo "Error: Target architecture must be provided."
  exit 1
fi

echo "Building Mode: $build"
echo "Target Triple: $target"

# Default flags
export CARGO_PROFILE_RELEASE_STRIP=debuginfo
export CARGO_PROFILE_RELEASE_PANIC=abort

flags=""
cmake_flags=""
build_std=""
build_std_features=""

# --- Configuration Logic ---

if [[ "$build" == *-min ]]; then
  # === Minimal Build ===
  export CARGO_PROFILE_RELEASE_OPT_LEVEL=s
  export RUSTFLAGS="-Zlocation-detail=none $RUSTFLAGS"
  export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
  export CARGO_PROFILE_RELEASE_LTO=true

  build_std="-Zbuild-std=std,panic_abort"
  build_std_features="-Zbuild-std-features=std_detect_dlsym_getauxval"

  cmake_flags="-DWASMTIME_DISABLE_ALL_FEATURES=ON"
  cmake_flags="$cmake_flags -DWASMTIME_FEATURE_DISABLE_LOGGING=ON"
  cmake_flags="$cmake_flags -DWASMTIME_USER_CARGO_BUILD_OPTIONS:LIST=$build_std;$build_std_features"

  cli_base_features="--no-default-features --features disable-logging"

  if [[ "$build" == "cranelift-min" ]]; then
    # Cranelift Min
    cli_feat_list="run,compile,gc,gc-drc,pooling-allocator"
    flags="$cli_base_features --features $cli_feat_list"

    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_CRANELIFT=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_GC_DRC=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_PARALLEL_COMPILATION=OFF"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_POOLING_ALLOCATOR=ON"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_COMPONENT_MODEL=OFF"
    cmake_flags="$cmake_flags -DWASMTIME_FEATURE_ASYNC=OFF"
  else
    echo "Unknown min configuration: $build"
    exit 1
  fi

  flags="$build_std $build_std_features $flags"

else
  # === Full Build (Cranelift) ===
  # 包含 all-arch，意味着包含 pulley 支持
  flags="--features all-arch"
fi

# --- Platform Specific ---

if [[ "$target" = "x86_64-pc-windows-msvc" ]]; then
  export CC=clang
  export CXX=clang++
fi

# === Android NDK Setup ===
if [[ "$target" == *android* ]]; then
  if [ -z "$ANDROID_NDK_HOME" ]; then
    if [ -d "$ANDROID_SDK_ROOT/ndk-bundle" ]; then
      export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk-bundle"
    elif [ -d "$ANDROID_HOME/ndk-bundle" ]; then
      export ANDROID_NDK_HOME="$ANDROID_HOME/ndk-bundle"
    fi
  fi

  if [ -n "$ANDROID_NDK_HOME" ]; then
    case $target in
      aarch64-linux-android) android_abi="arm64-v8a" ;;
      x86_64-linux-android)  android_abi="x86_64" ;;
      armv7-linux-androideabi) android_abi="armeabi-v7a" ;;
      i686-linux-android)    android_abi="x86" ;;
      *) echo "Unknown android target: $target"; exit 1 ;;
    esac

    echo "Configuring CMake for Android NDK ($android_abi)..."
    cmake_flags="$cmake_flags -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
    cmake_flags="$cmake_flags -DANDROID_ABI=$android_abi"
    cmake_flags="$cmake_flags -DANDROID_PLATFORM=android-24"
  fi
fi

# --- Build CLI ---
echo "Running Cargo Build for CLI..."
cargo build --release --target "$target" -p wasmtime-cli $flags

# --- Build C API ---
echo "Running CMake Build for C-API..."
export RUSTFLAGS="$RUSTFLAGS -C force-unwind-tables"

if [[ "$build" != *-min ]]; then
  case $target in
    *-pc-windows-msvc | *-pc-windows-gnu) ;;
    *) export CARGO_PROFILE_RELEASE_LTO=true ;;
  esac
fi

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