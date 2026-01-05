# kotlin remove jit
# build min 



- mac
- `RUSTC_BOOTSTRAP=1 rustup run nightly bash ./ci/build-release-artifacts.sh macos-m2-min aarch64-apple-darwin`

- windows
- `RUSTC_BOOTSTRAP=1 rustup run nightly bash ./ci/build-release-artifacts.sh windows-min x86_64-pc-windows-msvc`
```
1. 安装vsbuildtools 2022, 然后安装windwos 11 SDK
2. 安装clang+llvm 并配置环境变量./bin ./lib : https://github.com/llvm/llvm-project/releases/latest
3. choco install nija cmake rust -y 然后重启gitbash
3. rustup install nightly-x86_64-pc-windows-msvc
4. choco install nija cmake -y
5. win + s 打开x64 Native Tools Command Prompt for VS 2022 要64位的
6. 输入以上命令构建windows库，如果遇到问题检查一下是不是which link用的是不是Microsoft链接器是不是优先，不是的话可以在bashrc或者zshrc配置一下命令 自己动态修改下路径、系统变量等...。
export PATH="/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/HostX64/x64:$PATH"
7. Cargo.toml 版本不要乱改，三位版本号，

8. Rust 的底层库（windows-targets）很固执：当它看到环境变量 CC=clang 时，它会自作聪明地认为你在使用类似 MinGW 的 GNU 工具链，所以它非要去找 dlltool.exe。
它不看 lib.exe：尽管你系统里有微软原生的 lib.exe，但因为它“认定”你是 Clang 模式，它就绕过了微软的工具，转而去求助于它认为 Clang 应该配对的 GNU 工具。
mklink "C:\Users\CrowF\wuya\program\sdk\clang+llvm-21.1.8-x86_64-pc-windows-msvc\bin\dlltool.exe" "C:\Users\CrowF\wuya\program\sdk\clang+llvm-21.1.8-x86_64-pc-windows-msvc\bin\llvm-dlltool.exe"
吧llvm的dll-tools通过cmd创建符号链接解决此问题
```
```
# gitbash zshrc 配置这个 提供vs支持，这样就无需打开vsx64在里面打开gitbash了
# --- Visual Studio Build Environment ---

# 1. 定义 MSVC 工具链版本和 SDK 版本（根据你电脑实际路径修改）
MSVC_VERSION="14.44.35207"
SDK_VERSION="10.0.26100.0"

# 2. 注入 PATH (让微软的 link.exe 优先级最高)
export PATH="/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/$MSVC_VERSION/bin/HostX64/x64:$PATH"
export PATH="/c/Program Files (x86)/Windows Kits/10/bin/$SDK_VERSION/x64:$PATH"

# 3. 注入 INCLUDE (Clang 找 windows.h 全靠它)
export INCLUDE="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\\$MSVC_VERSION\include;C:\Program Files (x86)\Windows Kits\10\include\\$SDK_VERSION\ucrt;C:\Program Files (x86)\Windows Kits\10\include\\$SDK_VERSION\um;C:\Program Files (x86)\Windows Kits\10\include\\$SDK_VERSION\shared"

# 4. 注入 LIB (链接器找 .lib 全靠它)
export LIB="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\\$MSVC_VERSION\lib\x64;C:\Program Files (x86)\Windows Kits\10\lib\\$SDK_VERSION\ucrt\x64;C:\Program Files (x86)\Windows Kits\10\lib\\$SDK_VERSION\um\x64"

# 5. 解决 dlltool 的顽疾 (既然你不想改 .sh，就在这里指定)
# 假设你已经按我之前建议的做了 mklink，或者直接指向 llvm-dlltool
export DLLTOOL="llvm-dlltool"
```

- android
- `RUSTC_BOOTSTRAP=1 rustup run nightly bash ./ci/build-release-artifacts.sh android-min aarch64-linux-android`
```
# NDK 28 及以上默认好像是16kb
# Android 交叉编译配置toochain
export NDK_PATH="C:/Users/CrowF/AppData/Local/Android/Sdk/ndk/29.0.13599879"
export HOST_TAG="windows-x86_64"
export BIN_PATH="$NDK_PATH/toolchains/llvm/prebuilt/$HOST_TAG/bin"

# 编译器设置
export CC_aarch64_linux_android="$BIN_PATH/aarch64-linux-android24-clang.cmd"
export CXX_aarch64_linux_android="$BIN_PATH/aarch64-linux-android24-clang++.cmd"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$BIN_PATH/aarch64-linux-android24-clang.cmd"

# 设置16kb，如有需要改成4096 4kb
export RUSTFLAGS="-Zlocation-detail=none -C link-arg=-z -C link-arg=max-page-size=16384"
```
