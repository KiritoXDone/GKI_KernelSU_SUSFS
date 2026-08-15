#!/usr/bin/env bash

set -euo pipefail

SOURCE_REPO=${1:?"usage: checkout_kernel_source.sh <repo> <ref> <expected-version>"}
SOURCE_REF=${2:-HEAD}
EXPECTED_VERSION=${3:?"usage: checkout_kernel_source.sh <repo> <ref> <expected-version>"}
SOURCE_REMOTE=kernel-source

fail() {
  echo "::error::$*" >&2
  exit 1
}

if [[ ! -f Makefile || ! -e .git ]]; then
  fail "请在 common 内核源码仓库根目录运行此脚本"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  fail "切换基线前 common 源码目录必须保持干净"
fi

RESOLVED_REF=$SOURCE_REF
if [[ "$SOURCE_REF" == "HEAD" ]]; then
  RESOLVED_REF=$(
    git ls-remote --symref "$SOURCE_REPO" HEAD |
      awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }'
  )
  [[ -n "$RESOLVED_REF" ]] || fail "无法解析源码仓库的 default 分支: $SOURCE_REPO"
fi

echo "源码仓库: $SOURCE_REPO"
echo "请求引用: $SOURCE_REF"
echo "解析引用: $RESOLVED_REF"

if git remote get-url "$SOURCE_REMOTE" >/dev/null 2>&1; then
  git remote set-url "$SOURCE_REMOTE" "$SOURCE_REPO"
else
  git remote add "$SOURCE_REMOTE" "$SOURCE_REPO"
fi

if ! git fetch --no-tags --depth=1 "$SOURCE_REMOTE" "refs/heads/$RESOLVED_REF"; then
  fail "无法获取源码分支: $RESOLVED_REF"
fi

git checkout --detach FETCH_HEAD

makefile_value() {
  local key=$1
  awk -v key="$key" '$1 == key && $2 == "=" { print $3; exit }' Makefile
}

VERSION=$(makefile_value VERSION)
PATCHLEVEL=$(makefile_value PATCHLEVEL)
SUBLEVEL=$(makefile_value SUBLEVEL)
ACTUAL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"

if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
  fail "源码版本不匹配: 期望 $EXPECTED_VERSION，实际 $ACTUAL_VERSION ($RESOLVED_REF)"
fi

# 该构建流程会在后续独立叠加 ReSukiSU 和 SUSFS。拒绝已经集成这些组件的
# 源码分支，避免重复补丁产生一个表面成功、实际不可复现的内核。
for integrated_path in KernelSU drivers/kernelsu fs/susfs.c; do
  if [[ -e "$integrated_path" ]]; then
    fail "源码分支已包含 $integrated_path，不能再次叠加 ReSukiSU/SUSFS"
  fi
done

SOURCE_COMMIT=$(git rev-parse HEAD)
echo "已检出 $RESOLVED_REF ($SOURCE_COMMIT)，内核版本 $ACTUAL_VERSION"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "KERNEL_SOURCE_RESOLVED_REF=$RESOLVED_REF"
    echo "KERNEL_SOURCE_COMMIT=$SOURCE_COMMIT"
    echo "KERNEL_SOURCE_VERSION=$ACTUAL_VERSION"
  } >> "$GITHUB_ENV"
fi
