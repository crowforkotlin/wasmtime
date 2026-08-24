#!/bin/bash

# Source this file to configure a local Android toolchain for the
# Wasmline release scripts. Supports aarch64, x86_64, and armv7.
#
# Examples:
#   export ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/29.0.13599879"
#   source ./ci/wasmline/android-env.example.sh
#   bash ./ci/wasmline/build-target-release.sh aarch64-android aarch64-linux-android
#   bash ./ci/wasmline/build-target-release.sh x86_64-android x86_64-linux-android
#   bash ./ci/wasmline/build-target-release.sh armv7-android armv7-linux-androideabi
#   bash ./ci/wasmline/build-target-release.sh x86-android i686-linux-android

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "source this file instead of executing it:" >&2
  echo "  source ./ci/wasmline/android-env.example.sh" >&2
  exit 1
fi

: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to your Android NDK path first}"

ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-24}"
ANDROID_NDK_HOST_TAG="${ANDROID_NDK_HOST_TAG:-}"

if [[ -z "$ANDROID_NDK_HOST_TAG" ]]; then
  case "$(uname -s)" in
    Linux)
      ANDROID_NDK_HOST_TAG="linux-x86_64"
      ;;
    Darwin)
      case "$(uname -m)" in
        arm64) ANDROID_NDK_HOST_TAG="darwin-arm64" ;;
        *) ANDROID_NDK_HOST_TAG="darwin-x86_64" ;;
      esac
      ;;
    MINGW*|MSYS*|CYGWIN*)
      ANDROID_NDK_HOST_TAG="windows-x86_64"
      ;;
    *)
      echo "unsupported host OS for Android NDK auto-detection" >&2
      return 1
      ;;
  esac
fi

toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$ANDROID_NDK_HOST_TAG/bin"
compiler_suffix=""
case "$ANDROID_NDK_HOST_TAG" in
  windows-*) compiler_suffix=".cmd" ;;
esac

export CC_aarch64_linux_android="$toolchain/aarch64-linux-android${ANDROID_API_LEVEL}-clang${compiler_suffix}"
export CXX_aarch64_linux_android="$toolchain/aarch64-linux-android${ANDROID_API_LEVEL}-clang++${compiler_suffix}"
export AR_aarch64_linux_android="$toolchain/llvm-ar${compiler_suffix}"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$toolchain/aarch64-linux-android${ANDROID_API_LEVEL}-clang${compiler_suffix}"

# --- x86_64 (Android x86_64) ---
export CC_x86_64_linux_android="$toolchain/x86_64-linux-android${ANDROID_API_LEVEL}-clang${compiler_suffix}"
export CXX_x86_64_linux_android="$toolchain/x86_64-linux-android${ANDROID_API_LEVEL}-clang++${compiler_suffix}"
export AR_x86_64_linux_android="$toolchain/llvm-ar${compiler_suffix}"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$toolchain/x86_64-linux-android${ANDROID_API_LEVEL}-clang${compiler_suffix}"

# --- armv7 (Android armeabi-v7a, 32-bit, Pulley only) ---
# Note: NDK uses "armv7a" prefix (with trailing 'a'), not "armv7"
export CC_armv7_linux_androideabi="$toolchain/armv7a-linux-androideabi${ANDROID_API_LEVEL}-clang${compiler_suffix}"
export CXX_armv7_linux_androideabi="$toolchain/armv7a-linux-androideabi${ANDROID_API_LEVEL}-clang++${compiler_suffix}"
export AR_armv7_linux_androideabi="$toolchain/llvm-ar${compiler_suffix}"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$toolchain/armv7a-linux-androideabi${ANDROID_API_LEVEL}-clang${compiler_suffix}"

# --- i686 (Android x86, 32-bit, Pulley only) ---
export CC_i686_linux_android="$toolchain/i686-linux-android${ANDROID_API_LEVEL}-clang${compiler_suffix}"
export CXX_i686_linux_android="$toolchain/i686-linux-android${ANDROID_API_LEVEL}-clang++${compiler_suffix}"
export AR_i686_linux_android="$toolchain/llvm-ar${compiler_suffix}"
export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$toolchain/i686-linux-android${ANDROID_API_LEVEL}-clang${compiler_suffix}"

export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-z -C link-arg=max-page-size=16384"
