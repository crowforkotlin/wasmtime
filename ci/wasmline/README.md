# Wasmline Wasmtime 发行

`main` 只同步官方仓库。Wasmline 改动放在
`support/wasmline-<Wasmtime 大版本>` 分支，并用
`v<官方版本>.<下游修订号>` tag 触发 GitHub Actions。

例如 `v47.0.3.1` 表示基于官方 `v47.0.3` 的第一个 Wasmline 发行版。tag、
Release 标题和 Actions 运行名称都使用 `v47.0.3.1`，产物名以
`wasmtime-v47.0.3.1-` 开头。同一个 tag 不得删除、移动或重复使用。

## 1. 第一次创建大版本并发行

以下示例从官方 `v47.0.3` 创建 47.x 发行分支：

```bash
git fetch upstream --prune --tags
git switch -c support/wasmline-47 v47.0.3

# 添加 ci/wasmline、workflow，以及该版本需要的 Wasmline 源码改动。
git add .github/workflows/wasmline-release.yml ci/wasmline
git commit -m "ci: add Wasmline release for Wasmtime 47"
git push -u origin support/wasmline-47

bash ./ci/wasmline/tag-release.sh v47.0.3.1 --push
```

推送 tag 后，`.github/workflows/wasmline-release.yml` 会自动构建并发布 GitHub
Release。workflow 必须放在 `.github/workflows/`，否则 GitHub 不会执行；其余脚本和
本文都放在 `ci/wasmline/`。

## 2. 更新版本并发行

同一大版本内，例如从 `v47.0.3` 更新到 `v47.0.4`：

```bash
git fetch upstream --prune --tags
git switch support/wasmline-47
git pull --ff-only origin support/wasmline-47
git merge --no-ff v47.0.4 -m "chore: merge Wasmtime v47.0.4"

bash ./ci/wasmline/test-release-info.sh
git push origin support/wasmline-47
bash ./ci/wasmline/tag-release.sh v47.0.4.1 --push
```

如果合并发生冲突，修改冲突文件后执行 `git add <文件>` 和 `git commit`，再继续测试和
推送。已有的 Wasmline 提交会由 Git 保留，不需要 `cherry-pick`。

升级到新的大版本时，从新的官方 tag 创建分支，并一次取回 Wasmline 目录和 workflow：

workflow 固定 Rust 发行版以保证构建可复现；创建新大版本分支时，将其中的 Rust 版本
更新为该 Wasmtime 版本官方 CI 使用的发行版。

```bash
git fetch upstream --prune --tags
git switch -c support/wasmline-48 v48.0.0
git restore --source support/wasmline-47 -- \
  .github/workflows/wasmline-release.yml ci/wasmline

# 完成 48.x 所需的源码适配后一起提交；若还有其他改动路径，也加入 git add。
git add .github/workflows/wasmline-release.yml ci/wasmline
git commit -m "ci: add Wasmline release for Wasmtime 48"
git push -u origin support/wasmline-48
bash ./ci/wasmline/tag-release.sh v48.0.0.1 --push
```

如果官方版本不变、只增加 Wasmline 修复，则下游修订号递增，例如下一次使用
`v47.0.3.2`。旧的 `wasmline-v*` tag 保留并计入修订号；例如已经存在
`wasmline-v48.0.0.1` 时，下一版使用 `v48.0.0.2`。
