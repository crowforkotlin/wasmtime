#!/bin/bash
set -ex

rm -rf dist
mkdir dist

echo ">>> Moving standalone files..."
mv bins-*/*.msi dist/ 2>/dev/null || true
mv bins-*/*.wasm dist/ 2>/dev/null || true

if [ -d "wasmtime-platform-header" ]; then
    mv wasmtime-platform-header/* dist/ 2>/dev/null || true
fi

echo ">>> Merging tarballs..."
for min in bins-*-min/*.tar.*; do
  [ -e "$min" ] || continue

  normal=${min/-min\//\/}

  if [ ! -f "$normal" ]; then
    echo "Warning: Normal artifact not found for $min. Skipping merge."
    continue
  fi

  filename=$(basename $normal)
  # 处理 .tar.gz 和 .tar.xz
  dir=${filename%.tar.gz}
  dir=${dir%.tar.xz}

  rm -rf tmp
  mkdir -p tmp/normal
  mkdir -p tmp/min

  # 1. 分别解压，防止覆盖或路径冲突
  echo "Extracting Normal: $normal"
  tar xf $normal -C tmp/normal

  echo "Extracting Min: $min"
  tar xf $min -C tmp/min

  # 2. 合并：将 Min 的内容复制到 Normal 目录中
  # cp -r 会合并目录结构
  echo "Merging contents..."
  cp -r tmp/min/* tmp/normal/

  # 3. 重新打包
  # 注意：tmp/normal 下面现在应该包含唯一的文件夹 'wasmtime-v42-xxx'
  # 我们需要打包这个文件夹
  pkg_dir=$(ls tmp/normal | head -n 1)

  echo "Repackaging $pkg_dir to .tar.xz"
  tar -cf - -C tmp/normal $pkg_dir | xz -T0 > dist/$dir.tar.xz

  rm $min $normal
done

echo ">>> Merging zips..."
for min in bins-*-min/*.zip; do
  [ -e "$min" ] || continue

  normal=${min/-min\//\/}

  if [ ! -f "$normal" ]; then
    echo "Warning: Normal artifact not found for $min. Skipping merge."
    continue
  fi

  filename=$(basename $normal)
  dir=${filename%.zip}

  rm -rf tmp
  mkdir -p tmp/normal
  mkdir -p tmp/min

  # 1. 分别解压
  (cd tmp/normal && unzip -o ../../$normal)
  (cd tmp/min && unzip -o ../../$min)

  # 2. 合并
  cp -r tmp/min/* tmp/normal/

  pkg_dir=$(ls tmp/normal | head -n 1)

  # 3. 打包
  if command -v 7z >/dev/null 2>&1; then
     (cd tmp/normal && 7z a ../../dist/$dir.zip $pkg_dir/)
  elif command -v zip >/dev/null 2>&1; then
     (cd tmp/normal && zip -r ../../dist/$dir.zip $pkg_dir/)
  else
     # 回退方案
     tar -czvf dist/"$dir".tar.gz -C tmp/normal "$pkg_dir"
  fi

  rm $min $normal
done

echo ">>> Moving remaining artifacts..."
# 移动那些没有配对成功的剩余文件
mv bins-*/*.tar.* dist/ 2>/dev/null || true
mv bins-*/*.zip dist/ 2>/dev/null || true