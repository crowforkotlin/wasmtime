#!/bin/bash

# Script to merge artifacts with EXTREME fault tolerance.

set -ex

# === 调试：打印一下当前到底有什么文件，方便排查 ===
echo ">>> Debug: Listing all bins directories:"
ls -R bins-* || true
echo "------------------------------------------"

# Prepare the upload folder
rm -rf dist
mkdir dist

# 1. 移动独立文件 (忽略错误)
echo ">>> Moving standalone files..."
mv bins-*/*.msi dist/ 2>/dev/null || true
mv bins-*/*.wasm dist/ 2>/dev/null || true

if [ -d "wasmtime-platform-header" ]; then
    mv wasmtime-platform-header/* dist/ 2>/dev/null || true
fi

# 2. 合并 Tarballs (Android/Linux/Mac)
echo ">>> Merging tarballs..."
# 注意：这里匹配 .tar.gz 和 .tar.xz
for min in bins-*-min/*.tar.*; do
  # 如果 glob 没有匹配到文件，直接跳过
  [ -e "$min" ] || continue

  # 计算 Normal 包路径
  normal=${min/-min\//\/}

  # === [核心修复] 检查 Normal 包是否存在 ===
  if [ ! -f "$normal" ]; then
    echo "⚠️ Warning: Normal artifact NOT found at: $normal"
    echo "   Skipping merge for this file."
    # 不要退出，直接处理下一个文件
    continue
  fi

  filename=$(basename $normal)
  # 去掉后缀
  dir=${filename%.tar.gz}
  dir=${dir%.tar.xz}

  rm -rf tmp
  mkdir tmp

  echo "Processing $dir ..."
  # 解压
  tar xf $min -C tmp
  tar xf $normal -C tmp

  # 重新压缩为 .tar.xz
  tar -cf - -C tmp $dir | xz -T0 > dist/$dir.tar.xz

  # 删除源文件
  rm $min $normal
done

# 3. 合并 Zips (Windows)
echo ">>> Merging zips..."
for min in bins-*-min/*.zip; do
  [ -e "$min" ] || continue

  normal=${min/-min\//\/}

  # === [核心修复] 检查 Normal 包是否存在 ===
  if [ ! -f "$normal" ]; then
    echo "⚠️ Warning: Normal artifact NOT found at: $normal"
    echo "   Skipping merge for this file."
    continue
  fi

  filename=$(basename $normal)
  dir=${filename%.zip}

  rm -rf tmp
  mkdir tmp

  echo "Processing $dir ..."
  (cd tmp && unzip -o ../$min)
  (cd tmp && unzip -o ../$normal)

  if command -v 7z >/dev/null 2>&1; then
     (cd tmp && 7z a ../dist/$dir.zip $dir/)
  elif command -v zip >/dev/null 2>&1; then
     (cd tmp && zip -r ../dist/$dir.zip $dir/)
  else
     tar -czvf dist/$dir.zip -C tmp $dir
  fi

  rm $min $normal
done

# 4. 移动剩余文件
echo ">>> Moving remaining artifacts..."
# 剩下的都是没配对成功的，或者是单身包 (如 Pulley 某些构建)，直接移过去发布
mv bins-*/*.tar.* dist/ 2>/dev/null || true
mv bins-*/*.zip dist/ 2>/dev/null || true