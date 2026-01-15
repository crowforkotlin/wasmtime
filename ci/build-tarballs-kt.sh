#!/bin/bash

# Arguments:
# $1: Build Name (e.g. x86_64-windows)
# $2: Rust Target

set -ex

build=$1
target=$2

rm -rf tmp
mkdir tmp
mkdir -p dist

# 1. 版本号
tag=dev
if [[ $GITHUB_REF == refs/heads/release-* ]] || \
   [[ $GITHUB_REF == refs/tags/v* ]] || \
   [[ $GITHUB_REF == refs/heads/release-simulate ]]; then
  tag=v$(./ci/print-current-version.sh)
fi

# 2. 包名逻辑
build_pkgname=$build
if [[ $build == *-min ]]; then
  build_pkgname=${build%-min}
fi

bin_pkgname=wasmtime-$tag-$build_pkgname
api_pkgname=wasmtime-$tag-$build_pkgname-c-api

api_install=target/c-api-install

# 创建包含包名的目录，确保解压后有一层文件夹
mkdir tmp/$api_pkgname
mkdir tmp/$bin_pkgname

cp LICENSE README.md tmp/$api_pkgname
cp LICENSE README.md tmp/$bin_pkgname

# C-API 文件复制
if [[ $build == *-min ]]; then
  min="-min"
  mkdir tmp/$api_pkgname/min
  cp -r $api_install/include tmp/$api_pkgname/min
  cp -r $api_install/lib tmp/$api_pkgname/min
else
  cp -r $api_install/include tmp/$api_pkgname
  cp -r $api_install/lib tmp/$api_pkgname
fi

# 3. 确定格式和复制二进制
case $build in
  *windows*)
    fmt=zip
    cp target/$target/release/wasmtime.exe tmp/$bin_pkgname/wasmtime$min.exe
    ;;
  *)
    fmt=tar
    # 关键：Normal版这里复制为 wasmtime，Min版复制为 wasmtime-min
    # 只要它们在同一个 bin_pkgname 目录下，merge 时就会共存
    cp target/$target/release/wasmtime tmp/$bin_pkgname/wasmtime$min
    ;;
esac

# 4. 打包函数
mktarball() {
  dir=$1
  if [ "$fmt" = "tar" ]; then
    # 生成 tar.gz，保留目录结构
    tar -czvf dist/$dir.tar.gz -C tmp $dir
  else
    # 生成 zip
    if command -v 7z >/dev/null 2>&1; then
       (cd tmp && 7z a ../dist/$dir.zip $dir/)
    elif command -v zip >/dev/null 2>&1; then
       (cd tmp && zip -r ../dist/$dir.zip $dir/)
    else
        echo "Warning: No zip tool found. Falling back to tar.gz"
        tar -czvf dist/$dir.tar.gz -C tmp $dir
    fi
  fi
}

mktarball $api_pkgname
mktarball $bin_pkgname