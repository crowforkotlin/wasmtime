#!/bin/bash
set -e

# ================= 配置区域 =================
# 1. 设置目标架构
TARGET="x86_64-pc-windows-msvc"

# 2. 设置官方构建名称 (决定了文件名中的平台部分)
# 官方列表里是 "x86_64-windows"，不是简单的 "windows"
BUILD_NAME="x86_64-windows"

# 3. 欺骗脚本这是正式发布版本 (为了去掉 -dev 后缀)
# 只要 GITHUB_REF 以 refs/heads/release- 开头，脚本就会去读取 Cargo.toml 里的真实版本号
export GITHUB_REF="refs/heads/release-simulate"

# ================= 清理环境 =================
echo ">>> Cleaning up..."
rm -rf dist bins-* target/release target/x86_64-pc-windows-msvc/release
mkdir -p dist

# ================= 阶段 1: 普通构建 (Normal) =================
echo ">>> [1/3] Building Normal Artifacts ($BUILD_NAME)..."

# 1.1 编译
# 注意：这里传给 build-release-artifacts 的第二个参数用于内部标识，我们用完整名
RUSTC_BOOTSTRAP=1 rustup run nightly bash ./ci/build-release-artifacts-kt.sh cranelift $BUILD_NAME $TARGET

# 1.2 打包
# 这会生成 dist/wasmtime-vX.Y.Z-x86_64-windows.zip 等
bash ./ci/build-tarballs-kt.sh $BUILD_NAME $TARGET

# 1.3 模拟 CI 上传
# 必须移动到 bins-$BUILD_NAME 文件夹，否则 merge 脚本找不到
echo ">>> Moving Normal artifacts to bins-$BUILD_NAME..."
mkdir -p bins-$BUILD_NAME
mv dist/* bins-$BUILD_NAME/
rm -rf dist

# ================= 阶段 2: 最小化构建 (Min) =================
echo ">>> [2/3] Building Min Artifacts ($BUILD_NAME-min)..."

# 2.1 编译
# 这会覆盖 target/ 下的文件，但没关系，上一轮的已经打包移走了
RUSTC_BOOTSTRAP=1 rustup run nightly bash ./ci/build-release-artifacts-kt.sh cranelift-min $BUILD_NAME $TARGET

# 2.2 打包
# 注意参数必须加 -min
bash ./ci/build-tarballs-kt.sh ${BUILD_NAME}-min $TARGET

# 2.3 模拟 CI 上传
# 必须移动到 bins-$BUILD_NAME-min 文件夹
echo ">>> Moving Min artifacts to bins-${BUILD_NAME}-min..."
mkdir -p bins-${BUILD_NAME}-min
mv dist/* bins-${BUILD_NAME}-min/
rm -rf dist

# ================= 阶段 3: 合并 (Merge) =================
echo ">>> [3/3] Merging Artifacts..."

# 这个脚本会扫描当前目录下的 bins-* 文件夹进行合并
bash ./ci/merge-artifacts-kt.sh

# ================= 完成 =================
echo ">>> Done!"
echo "Official release artifacts are in the 'dist/' directory:"
ls -l dist/
