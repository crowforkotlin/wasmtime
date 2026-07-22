# Wasmline / Kotlin Multiplatform 发布说明

这份文档只覆盖这个 fork 里 **给 Wasmline / Kotlin Multiplatform 使用的定制发布流程**。

核心目标是把这部分和上游 Wasmtime 的通用 `ci/` 逻辑分开：

- Wasmline 定制脚本统一放到 `ci/wasmline/`
- 版本与 tag 校验继续复用根目录下的通用 release helper
- GitHub Actions、本地验证、目标平台说明三者分清职责

## 目录结构

### Wasmline 专用脚本

| 路径 | 作用 |
| --- | --- |
| `ci/wasmline/build-artifacts.sh` | 为单个 target 构建 Wasmline 需要的 CLI + C API 产物 |
| `ci/wasmline/package-artifacts.sh` | 将单个 target 当前构建结果打包到 `dist/` |
| `ci/wasmline/build-target-release.sh` | 对一个 build/target 执行 normal + min 两轮构建，并把结果整理到 `bins-*` |
| `ci/wasmline/merge-artifacts.sh` | 合并 `bins-*` 与 `bins-*-min`，输出最终 `dist/` |
| `ci/wasmline/build-local-release.sh` | 本地完整模拟一次单 target 的 Wasmline release 打包 |
| `ci/wasmline/android-env.example.sh` | 本地 Android AArch64 交叉编译的环境变量示例 |

### 通用 release helper

这些脚本不属于 Wasmline 专用逻辑，仍然放在 `ci/` 根目录：

| 路径 | 作用 |
| --- | --- |
| `ci/release-info.sh` | 统一解析版本、artifact tag、git tag，并做版本一致性校验 |
| `ci/tag-release.sh` | 基于当前 checkout 创建并可推送 `release-v*` tag |
| `ci/set-release-version.sh` | 同步 `Cargo.toml`、workspace dependency 版本与 `wasmtime.h` |

## GitHub Actions 现在怎么跑

`/.github/workflows/release.yml` 的 Wasmline 定制流程现在是：

1. 安装 nightly Rust 和目标 target
2. 按 target 补齐额外工具链配置（例如 Linux AArch64、Android）
3. 调用 `ci/wasmline/build-target-release.sh`
4. 上传 `bins-*` 中间产物
5. 在 release job 中调用 `ci/wasmline/merge-artifacts.sh`
6. 只在 `release-v*` tag 下创建 GitHub Release 草稿

这样 workflow 本身只保留“平台矩阵和环境准备”，真正的 Wasmline 打包逻辑集中在 `ci/wasmline/`。

## 推荐发布流程

### 1. 版本准备

如果当前分支内容已经是你要发的版本，直接创建 release tag：

```bash
bash ./ci/tag-release.sh --push
```

如果你是从 `upstream/main` 合并，而它已经 bump 到下一个版本，先把工作区版本改回目标版本：

```bash
bash ./ci/set-release-version.sh 43.0.0
bash ./ci/tag-release.sh --push
```

## 本地验证怎么跑

### 1. 本地完整模拟一个 target 的 release 打包

默认是 Windows MSVC：

```bash
bash ./ci/wasmline/build-local-release.sh
```

显式指定 build name / target：

```bash
bash ./ci/wasmline/build-local-release.sh x86_64-linux x86_64-unknown-linux-gnu
bash ./ci/wasmline/build-local-release.sh aarch64-android aarch64-linux-android
```

### 2. 只构建单轮产物，不做完整合并

```bash
bash ./ci/wasmline/build-artifacts.sh cranelift x86_64-unknown-linux-gnu
bash ./ci/wasmline/package-artifacts.sh x86_64-linux x86_64-unknown-linux-gnu
```

最小化构建需要 nightly：

```bash
RUSTC_BOOTSTRAP=1 rustup run nightly \
  bash ./ci/wasmline/build-artifacts.sh cranelift-min aarch64-android aarch64-linux-android
```

### 3. 本地单 target 按 release 流程构建 normal + min

```bash
bash ./ci/wasmline/build-target-release.sh x86_64-linux x86_64-unknown-linux-gnu
bash ./ci/wasmline/merge-artifacts.sh
```

## 版本、tag 和产物名的关系

- GitHub Actions 触发 tag：`release-vX.Y.Z`
- release helper 解析出的 artifact tag：`vX.Y.Z`
- 最终产物文件名保持：`wasmtime-vX.Y.Z-...`

例如：

- Git tag：`release-v43.0.0`
- 产物名：`wasmtime-v43.0.0-aarch64-linux.tar.xz`

## `wasmtime.h` 怎么处理

`crates/c-api/include/wasmtime.h` 里的这些宏不再手工维护：

- `WASMTIME_VERSION`
- `WASMTIME_VERSION_MAJOR`
- `WASMTIME_VERSION_MINOR`
- `WASMTIME_VERSION_PATCH`

统一由 `ci/set-release-version.sh` 同步更新；`ci/tag-release.sh` 和打包流程会在 release 模式下校验它们是否与 `Cargo.toml` 一致。

## 目标平台补充说明

和 Kotlin Multiplatform 侧最相关的本地目标说明放在：

- `docs/wasmline-target-notes.md`

里面专门整理了：

- Windows 本地构建注意事项
- Android NDK 环境配置
- Linux AArch64 交叉编译
- Apple 平台的基本要求

## 最常用命令
bash ./ci/set-release-version.sh 45.0.1
```bash
# 创建并推送 release tag
bash ./ci/tag-release.sh --push

# 把当前工作区改回某个要发布的版本
bash ./ci/set-release-version.sh 43.0.0

# 本地完整模拟 Wasmline release 打包
bash ./ci/wasmline/build-local-release.sh

# 本地构建单个 Linux 目标
bash ./ci/wasmline/build-target-release.sh x86_64-linux x86_64-unknown-linux-gnu
```
