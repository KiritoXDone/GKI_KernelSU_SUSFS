#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: apply_ztc_patchset.sh <kernel-source> <repo-root>" >&2
  exit 2
fi

kernel_source=$1
repo_root=$2
patch_file="$repo_root/patches/ztc/0001-ztc-android12-5.10-2026-07-optimizations.patch"

expected_base_commit=b14525331e0d5d335b037d6ed17d40424ed47b0a
expected_base_tree=9abb9c0d6b0a69b141ae0ed990e4134406c1f253
expected_result_tree=b96e4445196ab40158bde0c47117630577fbeca0
expected_patch_sha256=0449d772730c9895c890fa0e78d6541b9416180eab9b01fda4fcd6bb1f279d06

[[ -d "$kernel_source" ]] || { echo "kernel source not found: $kernel_source" >&2; exit 1; }
[[ -f "$patch_file" ]] || { echo "ztc patch not found: $patch_file" >&2; exit 1; }

cd "$kernel_source"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ztc patch set requires a clean kernel source tree" >&2
  exit 1
fi

actual_base_commit=$(git rev-parse HEAD)
actual_base_tree=$(git rev-parse HEAD^{tree})
if [[ "$actual_base_commit" != "$expected_base_commit" || "$actual_base_tree" != "$expected_base_tree" ]]; then
  echo "ztc patch base mismatch" >&2
  echo "expected commit/tree: $expected_base_commit / $expected_base_tree" >&2
  echo "actual commit/tree:   $actual_base_commit / $actual_base_tree" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual_patch_sha256=$(sha256sum "$patch_file" | awk '{print $1}')
else
  actual_patch_sha256=$(shasum -a 256 "$patch_file" | awk '{print $1}')
fi
if [[ "$actual_patch_sha256" != "$expected_patch_sha256" ]]; then
  echo "ztc patch checksum mismatch: $actual_patch_sha256" >&2
  exit 1
fi

# Validate the complete post-patch tree through a temporary index before
# touching the worktree. This checks additions and deletions as well as hunks.
temporary_index=$(mktemp)
rm -f "$temporary_index"
trap 'rm -f "$temporary_index"' EXIT
GIT_INDEX_FILE="$temporary_index" git read-tree HEAD
GIT_INDEX_FILE="$temporary_index" git apply --cached --check "$patch_file"
GIT_INDEX_FILE="$temporary_index" git apply --cached --whitespace=nowarn "$patch_file"
actual_result_tree=$(GIT_INDEX_FILE="$temporary_index" git write-tree)
if [[ "$actual_result_tree" != "$expected_result_tree" ]]; then
  echo "ztc patch result tree mismatch" >&2
  echo "expected: $expected_result_tree" >&2
  echo "actual:   $actual_result_tree" >&2
  exit 1
fi

git apply --check "$patch_file"
git apply --whitespace=nowarn "$patch_file"

echo "Applied ztc optimization patch set: $expected_base_commit -> $expected_result_tree"
