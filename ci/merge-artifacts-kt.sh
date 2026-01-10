#!/bin/bash

# Script to merge the outputs of a run on github actions to github releases.
# Modified to be fail-safe if MSIs or Headers are missing.

set -ex

# Prepare the upload folder
rm -rf dist
mkdir dist

# 1. 尝试移动 MSI 和 WASM 文件 (如果有的话)
# 使用 2>/dev/null || true 忽略“文件不存在”的错误
echo "Moving MSI/WASM files (if any)..."
mv bins-*/*.msi dist/ 2>/dev/null || true
mv bins-*/*.wasm dist/ 2>/dev/null || true

# 2. 尝试移动平台头文件 (如果有的话)
if [ -d "wasmtime-platform-header" ]; then
    echo "Moving platform headers..."
    mv wasmtime-platform-header/* dist/ 2>/dev/null || true
fi

# 3. Merge tarballs (*.tar.gz / *.tar.xz)
echo "Merging tarballs..."
for min in bins-*-min/*.tar.*; do
  # 检查文件是否存在
  [ -e "$min" ] || continue

  normal=${min/-min\//\/}
  filename=$(basename $normal)
  # 去掉后缀，获取目录名
  dir=${filename%.tar.gz}
  dir=${dir%.tar.xz}

  rm -rf tmp
  mkdir tmp

  echo "Processing $dir ..."
  tar xf $min -C tmp
  tar xf $normal -C tmp

  # 重新打包为 .tar.xz
  tar -cf - -C tmp $dir | xz -T0 > dist/$dir.tar.xz

  rm $min $normal
done

# 4. Merge zips (Windows builds)
echo "Merging zips..."
for min in bins-*-min/*.zip; do
  [ -e "$min" ] || continue

  normal=${min/-min\//\/}
  filename=$(basename $normal)
  dir=${filename%.zip}

  rm -rf tmp
  mkdir tmp

  echo "Processing $dir ..."
  # 解压
  (cd tmp && unzip -o ../$min)
  (cd tmp && unzip -o ../$normal)

  # === 压缩逻辑 ===
  if command -v 7z >/dev/null 2>&1; then
     # 优先使用 7z (生成 .zip)
     (cd tmp && 7z a ../dist/$dir.zip $dir/)
  elif command -v zip >/dev/null 2>&1; then
     # 其次使用 zip (生成 .zip)
     (cd tmp && zip -r ../dist/$dir.zip $dir/)
  else
     # 使用 tar (生成 .tar.gz)
     echo "Warning: zip/7z not found. Falling back to tar..."
     tar -czvf dist/$dir.tar.gz -C tmp $dir
  fi

  rm $min $normal
done

# 5. Copy over remaining artifacts
echo "Moving remaining artifacts..."
mv bins-*/*.tar.* dist/ 2>/dev/null || true
mv bins-*/*.zip dist/ 2>/dev/null || true