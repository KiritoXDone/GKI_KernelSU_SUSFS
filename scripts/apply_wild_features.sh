#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: apply_wild_features.sh <kernel-source> <wild-kernel-patches> <repo-root> [--bbr3] [--ptrace] [--btf]" >&2
}

if [[ $# -lt 3 ]]; then
  usage
  exit 2
fi

kernel_source=$1
wild_patches=$2
repo_root=$3
shift 3

apply_bbr3=false
apply_ptrace=false
apply_btf=false
for option in "$@"; do
  case "$option" in
    --bbr3) apply_bbr3=true ;;
    --ptrace) apply_ptrace=true ;;
    --btf) apply_btf=true ;;
    *) echo "unknown option: $option" >&2; usage; exit 2 ;;
  esac
done

[[ -d "$kernel_source" ]] || { echo "kernel source not found: $kernel_source" >&2; exit 1; }
cd "$kernel_source"

verify_sha256() {
  local expected=$1
  local file=$2
  printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
}

apply_strict_git_patch() {
  local patch_file=$1
  git apply --check "$patch_file"
  git apply --whitespace=nowarn "$patch_file"
}

if [[ "$apply_bbr3" == true || "$apply_ptrace" == true ]]; then
  expected_patches_commit=0bb0203cdfcadbe32bb572af3a52e1c1430c7515
  actual_patches_commit=$(git -C "$wild_patches" rev-parse HEAD)
  if [[ "$actual_patches_commit" != "$expected_patches_commit" ]]; then
    echo "WildKernels/kernel_patches commit mismatch: $actual_patches_commit" >&2
    exit 1
  fi
fi

if [[ "$apply_ptrace" == true ]]; then
  ptrace_patch="$wild_patches/gki_ptrace.patch"
  verify_sha256 1c56885c34355425c4b15d6b9986047a49b0e09af429dcca00d0c4c13e8d89b0 "$ptrace_patch"
  apply_strict_git_patch "$ptrace_patch"
  echo "Applied WildKernels ptrace leak fix"
fi

if [[ "$apply_bbr3" == true ]]; then
  bbr3_dir="$wild_patches/common/bbrv3"
  bbr3_patch="$bbr3_dir/0001-net-tcp-backport-BBRv3-to-android12-5.10.patch"
  compat_patch="$repo_root/patches/wild/compat/android12-5.10-bbr3-tlp-ack.patch"

  verify_sha256 f2989221fef193b43d665ec8fe96a4093ec3482e46f1154d62c2c3c5204846bb "$bbr3_patch"
  verify_sha256 0d08af00930a77f050e1309528380d281d1033efc81856b83e9aa1c5da0d892b "$compat_patch"

  if git apply --check "$bbr3_patch"; then
    git apply --whitespace=nowarn "$bbr3_patch"
  else
    patched_paths=()
    while IFS= read -r path; do
      patched_paths+=("$path")
    done < <(sed -n 's|^+++ b/||p' "$bbr3_patch" | grep -v '^/dev/null$' | sort -u)
    for path in "${patched_paths[@]}"; do
      if [[ -e "${path}.rej" ]]; then
        echo "pre-existing reject would make BBRv3 validation ambiguous: ${path}.rej" >&2
        exit 1
      fi
    done

    set +e
    git apply --reject --whitespace=nowarn "$bbr3_patch"
    patch_status=$?
    set -e
    if [[ $patch_status -eq 0 ]]; then
      echo "BBRv3 preflight failed but reject-mode unexpectedly succeeded" >&2
      exit 1
    fi

    bbr_rejects=()
    for path in "${patched_paths[@]}"; do
      [[ -f "${path}.rej" ]] && bbr_rejects+=("${path}.rej")
    done
    if [[ ${#bbr_rejects[@]} -ne 1 || "${bbr_rejects[0]}" != net/ipv4/tcp_input.c.rej ]]; then
      printf 'unexpected BBRv3 rejects: %s\n' "${bbr_rejects[*]:-none}" >&2
      exit 1
    fi
    if [[ $(grep -c '^@@ ' net/ipv4/tcp_input.c.rej) -ne 1 ]] \
      || ! grep -qF -- $'-\t\ttcp_process_tlp_ack(sk, ack, flag);' net/ipv4/tcp_input.c.rej \
      || ! grep -qF -- $'+\t\ttcp_process_tlp_ack(sk, ack, flag, &rs);' net/ipv4/tcp_input.c.rej; then
      echo "Android 12 5.10 BBRv3 reject no longer matches the audited TLP-ACK context" >&2
      exit 1
    fi
    git apply --check "$compat_patch"
    git apply "$compat_patch"
    rm net/ipv4/tcp_input.c.rej
    echo "Applied audited Android 12 5.10 TLP-ACK compatibility hunk"
  fi

  if ! grep -qF 'int proc_dou8vec_minmax(' include/linux/sysctl.h; then
    sysctl_add="$bbr3_dir/sysctl_add_proc_dou8vec_minmax.patch"
    sysctl_race="$bbr3_dir/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch"
    verify_sha256 c790ae20a742ffcd55a47daa4b5073818957f8f54e0975293a46f03f9144683b "$sysctl_add"
    verify_sha256 3b184f88c8fdd5ffca4ca6e09a2bd640f6e8088a1df6933c185bde7d45285947 "$sysctl_race"
    apply_strict_git_patch "$sysctl_add"
    apply_strict_git_patch "$sysctl_race"
  fi

  grep -qF 'config TCP_CONG_BBR3' net/ipv4/Kconfig
  grep -qF '.name' net/ipv4/tcp_bbr3.c
  grep -qF '"bbr3"' net/ipv4/tcp_bbr3.c
  echo "Applied WildKernels BBRv3 backport"
fi

if [[ "$apply_btf" == true ]]; then
  btf_patch_1="$repo_root/patches/wild/btf/0001-libbpf-remove-feature-detection-BTF.patch"
  btf_patch_2="$repo_root/patches/wild/btf/0002-resolve-btfids-inherit-host-linker-flags.patch"
  verify_sha256 9d080fb2b95f66650372c761c70dc4986963bf9b773a5cc21388754ad0c5eb26 "$btf_patch_1"
  verify_sha256 25f4656dc4ce0c11e7ba1de295a3dbae6119bb2c2f11fbddb6433526cfd36609 "$btf_patch_2"
  patch --dry-run --batch --forward --fuzz=0 -p1 < "$btf_patch_1"
  patch --batch --forward --fuzz=0 -p1 < "$btf_patch_1"
  patch --dry-run --batch --forward --fuzz=0 -p1 < "$btf_patch_2"
  patch --batch --forward --fuzz=0 -p1 < "$btf_patch_2"
  echo "Applied WildKernels BTF host-tool compatibility patches"
fi
