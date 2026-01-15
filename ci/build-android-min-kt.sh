# NDK 28 及以上默认好像是16kb
# Android 交叉编译配置toochain
export NDK_PATH="C:/Users/CrowF/AppData/Local/Android/Sdk/ndk/29.0.13599879"
export HOST_TAG="windows-x86_64"
export BIN_PATH="$NDK_PATH/toolchains/llvm/prebuilt/$HOST_TAG/bin"

# 编译器设置
export CC_aarch64_linux_android="$BIN_PATH/aarch64-linux-android21-clang.cmd"
export CXX_aarch64_linux_android="$BIN_PATH/aarch64-linux-android21-clang++.cmd"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$BIN_PATH/aarch64-linux-android21-clang.cmd"

# 设置16kb，如有需要改成4096 4kb
export RUSTFLAGS="-Zlocation-detail=none -C link-arg=-z -C link-arg=max-page-size=16384"

RUSTC_BOOTSTRAP=1 rustup run nightly bash ./ci/build-release-artifacts.sh pulley-min android aarch64-linux-android
