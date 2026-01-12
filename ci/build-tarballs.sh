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

# 1. 版本号逻辑
tag=dev
if [[ $GITHUB_REF == refs/heads/release-* ]] || \
   [[ $GITHUB_REF == refs/tags/v* ]] || \
   [[ $GITHUB_REF == refs/heads/release-simulate ]]; then
  tag=v$(./ci/print-current-version.sh)
fi

# 2. 包名逻辑
# 这里的关键是：build_pkgname 对于 min 和 normal 必须是一样的
# 这样解压后它们才会位于同一个文件夹内
build_pkgname=$build
if [[ $build == *-min ]]; then
  build_pkgname=${build%-min}
fi

bin_pkgname=wasmtime-$tag-$build_pkgname
api_pkgname=wasmtime-$tag-$build_pkgname-c-api

api_install=target/c-api-install

# 创建包含包名的目录
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

# 3. 复制二进制文件
case $build in
  *windows*)
    fmt=zip
    cp target/$target/release/wasmtime.exe tmp/$bin_pkgname/wasmtime$min.exe
    ;;
  *)
    fmt=tar
    # 无论是否为 min，都放入同一个文件夹 tmp/$bin_pkgname
    cp target/$target/release/wasmtime tmp/$bin_pkgname/wasmtime$min
    ;;
esac

# 4. 打包函数
mktarball() {
  dir=$1
  # 注意：这里 -C tmp $dir 确保了压缩包内部有一层顶层目录
  if [ "$fmt" = "tar" ]; then
    tar -czvf dist/$dir.tar.gz -C tmp $dir
  else
    if command -v 7z >/dev/null 2>&1; then
       (cd tmp && 7z a ../dist/$dir.zip $dir/)
    elif command -v zip >/dev/null 2>&1; then
       (cd tmp && zip -r ../dist/$dir.zip $dir/)
    else
       # 如果没有 zip 工具，回退到 tar.gz (防止报错)
       echo "Warning: No zip/7z found. Creating tar.gz instead."
       tar -czvf dist/$dir.tar.gz -C tmp $dir
    fi
  fi
}

mktarball $api_pkgname
mktarball $bin_pkgname