# Wasmline 目标平台本地构建说明

这份文档补充 `docs/release-wasmline.md`，只记录 **本地** 给 Wasmline / Kotlin Multiplatform 用的目标平台注意事项。

## 总体原则

1. 优先把通用逻辑留在 `ci/wasmline/*.sh`
2. 把平台相关差异放到环境变量和文档里，不要再把机器私有路径硬编码进提交
3. 能由 GitHub Actions 自动完成的配置，尽量和本地命名保持一致

## Linux x86_64

宿主机本身就是 `x86_64-unknown-linux-gnu` 时，通常直接跑：

```bash
bash ./ci/wasmline/build-target-release.sh x86_64-linux x86_64-unknown-linux-gnu
```

## Linux AArch64 交叉编译

在 Ubuntu / Debian 类宿主机上先安装交叉工具链：

```bash
sudo apt-get update
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
```

然后构建：

```bash
bash ./ci/wasmline/build-target-release.sh aarch64-linux aarch64-unknown-linux-gnu
```

`ci/wasmline/build-artifacts.sh` 会自动优先使用这些变量：

- `CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER`
- `CC_aarch64_unknown_linux_gnu`
- `CXX_aarch64_unknown_linux_gnu`

如果你需要自定义工具链，提前导出这些环境变量即可。

## Android AArch64

### 基本要求

- 安装 Android NDK
- 设置 `ANDROID_NDK_HOME`
- 使用 API 24 或更高版本

### 推荐做法

先 source 示例环境脚本：

```bash
export ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/29.0.13599879"
source ./ci/wasmline/android-env.example.sh
```

然后执行本地构建：

```bash
bash ./ci/wasmline/build-target-release.sh aarch64-android aarch64-linux-android
```

默认会保留 16 KiB page size 相关 linker 参数：

```text
-C link-arg=-z -C link-arg=max-page-size=16384
```

如果你的 Android 侧需要别的 page size，可以在 source 之前自行设置或覆盖 `RUSTFLAGS`。

## Windows

### MSVC 目标

本地构建 `x86_64-pc-windows-msvc` 时，建议：

1. 安装 Visual Studio Build Tools
2. 安装 Windows SDK
3. 安装 LLVM / Clang
4. 确保链接器环境可用

常见验证项：

- `clang` / `clang++` 可用
- `link.exe`、`lib.exe` 来自 MSVC 工具链
- `INCLUDE` / `LIB` 指向对应 SDK 和 MSVC 目录

构建命令：

```bash
bash ./ci/wasmline/build-local-release.sh x86_64-windows x86_64-pc-windows-msvc
```

### GNU 目标

GitHub Actions 里的 Windows 发布当前走的是：

```text
x86_64-pc-windows-gnu
```

如果你本地也想复现这一目标，需要先准备好 MinGW/GCC 环境，再运行：

```bash
bash ./ci/wasmline/build-target-release.sh x86_64-windows x86_64-pc-windows-gnu
```

## macOS / iOS

这些目标建议在 macOS 宿主机上构建。

### macOS

```bash
bash ./ci/wasmline/build-target-release.sh x86_64-macos x86_64-apple-darwin
bash ./ci/wasmline/build-target-release.sh aarch64-macos aarch64-apple-darwin
```

### iOS

```bash
bash ./ci/wasmline/build-target-release.sh aarch64-ios aarch64-apple-ios
bash ./ci/wasmline/build-target-release.sh aarch64-ios-sim aarch64-apple-ios-sim
```

需要提前安装对应 Rust target，并保证 Xcode / Apple toolchain 可用。
