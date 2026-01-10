#!/bin/bash

# A small script used for assembling release tarballs.
# Arguments:
# $1: Build Name (e.g. x86_64-windows, aarch64-linux)
# $2: Rust Target

set -ex

build=$1
target=$2

rm -rf tmp
mkdir tmp
mkdir -p dist

# === 1. 版本号逻辑修复 ===
# 只要是 v* 开头的 tag，或者 release-simulate，都读取真实版本号
tag=dev
if [[ $GITHUB_REF == refs/heads/release-* ]] || \
   [[ $GITHUB_REF == refs/tags/v* ]] || \
   [[ $GITHUB_REF == refs/heads/release-simulate ]]; then
  tag=v$(./ci/print-current-version.sh)
fi

# === 2. 确定包名 ===
# *-min 构建使用和普通构建相同的包名，方便后续合并
build_pkgname=$build
if [[ $build == *-min ]]; then
  build_pkgname=${build%-min}
fi

bin_pkgname=wasmtime-$tag-$build_pkgname
api_pkgname=wasmtime-$tag-$build_pkgname-c-api

api_install=target/c-api-install

# === 3. 准备目录结构 (解决只有一层文件夹的问题) ===
# 创建顶层目录
mkdir tmp/$api_pkgname
mkdir tmp/$bin_pkgname

# 复制 License
cp LICENSE README.md tmp/$api_pkgname
cp LICENSE README.md tmp/$bin_pkgname

# 复制 C-API 文件
# 如果是 min 构建，放入 min 子目录，否则放入根目录
if [[ $build == *-min ]]; then
  min="-min"
  mkdir tmp/$api_pkgname/min
  cp -r $api_install/include tmp/$api_pkgname/min
  cp -r $api_install/lib tmp/$api_pkgname/min
else
  cp -r $api_install/include tmp/$api_pkgname
  cp -r $api_install/lib tmp/$api_pkgname
fi

# === 4. 确定打包格式 ===
case $build in
  *windows*)
    # Windows 使用 zip
    fmt=zip
    # 复制 exe
    cp target/$target/release/wasmtime.exe tmp/$bin_pkgname/wasmtime$min.exe
    ;;
  *)
    # Android/Linux/macOS 使用 tar (后续会被 merge 脚本转为 tar.xz)
    fmt=tar
    # 复制二进制文件
    cp target/$target/release/wasmtime tmp/$bin_pkgname/wasmtime$min
    ;;
esac

# Windows MSI 生成 (仅在 CI 且变量存在时)
if [[ $build == x86_64-windows* ]] && [ "$min" = "" ] && [ -n "$WIX" ]; then
    echo "Generating MSI..."
    export WT_VERSION=`cat Cargo.toml | sed -n 's/^version = "\([^"]*\)".*/\1/p'`
    "$WIX/bin/candle" -arch x64 -out target/wasmtime.wixobj ci/wasmtime.wxs
    "$WIX/bin/light" -out dist/$bin_pkgname.msi target/wasmtime.wixobj -ext WixUtilExtension
    rm dist/$bin_pkgname.wixpdb
fi

# === 5. 打包函数 ===
mktarball() {
  dir=$1
  if [ "$fmt" = "tar" ]; then
    # 生成 tar.gz。注意 -C tmp $dir 确保了压缩包解压后有一层文件夹
    tar -czvf dist/$dir.tar.gz -C tmp $dir
  else
    # 生成 zip
    if command -v 7z >/dev/null 2>&1; then
       (cd tmp && 7z a ../dist/$dir.zip $dir/)
    elif command -v zip >/dev/null 2>&1; then
       (cd tmp && zip -r ../dist/$dir.zip $dir/)
    elif command -v powershell.exe >/dev/null 2>&1; then
       powershell.exe -NoProfile -Command "Compress-Archive -Path 'tmp/$dir' -DestinationPath 'dist/$dir.zip' -Force"
    else
       # 如果实在没有 zip 工具，回退到 tar
       tar -czvf dist/$dir.tar.gz -C tmp $dir
    fi
  fi
}

mktarball $api_pkgname
mktarball $bin_pkgname