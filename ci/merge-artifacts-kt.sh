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

  # 必须确保 normal 包存在，否则说明该架构的全量构建失败了
  if [ ! -f "$normal" ]; then
    echo "Warning: Normal artifact not found for $min. Skipping merge."
    continue
  fi

  filename=$(basename $normal)
  dir=${filename%.tar.gz}
  dir=${dir%.tar.xz}

  rm -rf tmp
  mkdir tmp

  # 解压 Min (得到 wasmtime-min)
  tar xf $min -C tmp
  # 解压 Normal (得到 wasmtime) -> 两个文件现在都在 tmp/$dir 下了
  tar xf $normal -C tmp

  # 重新压缩为 .tar.xz
  tar -cf - -C tmp $dir | xz -T0 > dist/$dir.tar.xz

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
  mkdir tmp

  (cd tmp && unzip -o ../$min)
  (cd tmp && unzip -o ../$normal)

  if command -v 7z >/dev/null 2>&1; then
     (cd tmp && 7z a ../dist/$dir.zip $dir/)
  elif command -v zip >/dev/null 2>&1; then
     (cd tmp && zip -r ../dist/$dir.zip $dir/)
  else
     tar -czvf dist/"$dir".tar.gz -C tmp "$dir"
  fi

  rm $min $normal
done

echo ">>> Moving remaining artifacts..."
mv bins-*/*.tar.* dist/ 2>/dev/null || true
mv bins-*/*.zip dist/ 2>/dev/null || true