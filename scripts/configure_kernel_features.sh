#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: configure_kernel_features.sh <kernel-source> <defconfig> <expectations> [options]

Options:
  --networking   Enable IPSet, IPv6 NAT, BBRv1, qdiscs, connmark, TTL and WireGuard
  --bbr3         Enable BBRv3 and make it the default (implies --networking)
  --cifs         Enable built-in SMB/CIFS support
  --misc         Enable tmpfs ACL/xattr, tracing and eBPF event support
  --fuse-bpf     Enable FUSE-BPF when this kernel exposes the Kconfig symbol
  --btf          Enable CONFIG_DEBUG_INFO_BTF
  --bbg          Enable Baseband Guard
  --zram         Record the existing ZRAM integration as required
  --rekernel     Record the existing Re-Kernel integration as required
  --susfs        Record the existing SUSFS integration as required
  --droidspaces  Record DroidSpaces namespace support as required
  --ntsync       Record NTSync support as required
EOF
}

if [[ $# -lt 3 ]]; then
  usage >&2
  exit 2
fi

kernel_source=$1
defconfig=$2
expectations=$3
shift 3

[[ -d "$kernel_source" ]] || { echo "kernel source not found: $kernel_source" >&2; exit 1; }
[[ -f "$defconfig" ]] || { echo "defconfig not found: $defconfig" >&2; exit 1; }

networking=false
bbr3=false
cifs=false
misc=false
fuse_bpf=false
btf=false
bbg=false
zram=false
rekernel=false
susfs=false
droidspaces=false
ntsync=false

for option in "$@"; do
  case "$option" in
    --networking) networking=true ;;
    --bbr3) bbr3=true; networking=true ;;
    --cifs) cifs=true ;;
    --misc) misc=true ;;
    --fuse-bpf) fuse_bpf=true ;;
    --btf) btf=true ;;
    --bbg) bbg=true ;;
    --zram) zram=true ;;
    --rekernel) rekernel=true ;;
    --susfs) susfs=true ;;
    --droidspaces) droidspaces=true ;;
    --ntsync) ntsync=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $option" >&2; usage >&2; exit 2 ;;
  esac
done

known_configs_file=$(mktemp)
trap 'rm -f "$known_configs_file"' EXIT
kconfig_roots=("$kernel_source")
kernel_parent=$(dirname "$kernel_source")
for external_tree in "$kernel_parent/KernelSU" "$kernel_parent/Baseband-guard"; do
  [[ -d "$external_tree" ]] && kconfig_roots+=("$external_tree")
done
find "${kconfig_roots[@]}" -type f -name 'Kconfig*' -exec awk '
  /^[[:space:]]*(menuconfig|config)[[:space:]]+[A-Za-z0-9_]+/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "config" || $i == "menuconfig") {
        print "CONFIG_" $(i + 1)
        break
      }
    }
  }
' {} + | sort -u > "$known_configs_file"

: > "$expectations"

config_defined() {
  grep -Fqx -- "$1" "$known_configs_file"
}

remove_config_lines() {
  local file=$1
  local config=$2
  sed -i.bak -e "/^${config}=/d" -e "/^# ${config} is not set$/d" "$file"
  rm -f "${file}.bak"
}

record_exact() {
  local line=$1
  local config
  if [[ "$line" == '# '* ]]; then
    config=${line#\# }
    config=${config% is not set}
  else
    config=${line%%=*}
  fi
  sed -i.bak -e "/^EXACT:${config}=/d" -e "/^EXACT:# ${config} is not set$/d" "$expectations"
  rm -f "${expectations}.bak"
  printf 'EXACT:%s\n' "$line" >> "$expectations"
}

set_config() {
  local config=$1
  local value=$2
  local required=${3:-true}
  local line

  if ! config_defined "$config"; then
    if [[ "$required" == true ]]; then
      echo "required Kconfig symbol is missing: $config" >&2
      exit 1
    fi
    echo "optional Kconfig symbol is unavailable, skipping: $config"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      printf -- '- `%s`: 当前基线未提供，已跳过。\n' "$config" >> "$GITHUB_STEP_SUMMARY"
    fi
    return 0
  fi

  remove_config_lines "$defconfig" "$config"
  if [[ "$value" == n ]]; then
    line="# ${config} is not set"
  else
    line="${config}=${value}"
  fi
  printf '%s\n' "$line" >> "$defconfig"
  record_exact "$line"
}

if [[ "$networking" == true ]]; then
  for config in \
    CONFIG_IP_SET CONFIG_IP_SET_BITMAP_IP CONFIG_IP_SET_BITMAP_IPMAC \
    CONFIG_IP_SET_BITMAP_PORT CONFIG_IP_SET_HASH_IP CONFIG_IP_SET_HASH_IPMARK \
    CONFIG_IP_SET_HASH_IPPORT CONFIG_IP_SET_HASH_IPPORTIP \
    CONFIG_IP_SET_HASH_IPPORTNET CONFIG_IP_SET_HASH_IPMAC \
    CONFIG_IP_SET_HASH_MAC CONFIG_IP_SET_HASH_NETPORTNET CONFIG_IP_SET_HASH_NET \
    CONFIG_IP_SET_HASH_NETNET CONFIG_IP_SET_HASH_NETPORT \
    CONFIG_IP_SET_HASH_NETIFACE CONFIG_IP_SET_LIST_SET \
    CONFIG_NETFILTER_XT_MATCH_ADDRTYPE CONFIG_NETFILTER_XT_SET \
    CONFIG_NETFILTER_XT_TARGET_LOG CONFIG_NETFILTER_XT_MATCH_RECENT \
    CONFIG_IP6_NF_NAT CONFIG_IP6_NF_TARGET_MASQUERADE \
    CONFIG_TCP_CONG_ADVANCED CONFIG_TCP_CONG_BBR CONFIG_TCP_CONG_CUBIC \
    CONFIG_TCP_CONG_BIC CONFIG_TCP_CONG_WESTWOOD CONFIG_TCP_CONG_HTCP \
    CONFIG_NET_SCH_FQ CONFIG_NET_SCH_FQ_CODEL CONFIG_NET_SCH_CAKE \
    CONFIG_NET_ACT_CONNMARK CONFIG_IP_NF_TARGET_TTL CONFIG_IP6_NF_TARGET_HL \
    CONFIG_IP6_NF_MATCH_HL CONFIG_WIREGUARD; do
    set_config "$config" y
  done
  set_config CONFIG_IP_SET_MAX 65534
  set_config CONFIG_DEFAULT_BBR y
  set_config CONFIG_DEFAULT_TCP_CONG '"bbr"'
fi

if [[ "$bbr3" == true ]]; then
  set_config CONFIG_TCP_CONG_BBR3 y
  set_config CONFIG_DEFAULT_BBR n
  set_config CONFIG_DEFAULT_BBR3 y
  set_config CONFIG_DEFAULT_TCP_CONG '"bbr3"'
fi

if [[ "$cifs" == true ]]; then
  for config in CONFIG_NETWORK_FILESYSTEMS CONFIG_KEYS CONFIG_CIFS CONFIG_CIFS_XATTR CONFIG_CIFS_POSIX; do
    set_config "$config" y
  done
  set_config CONFIG_NETFS_SUPPORT y false
fi

if [[ "$misc" == true ]]; then
  for config in \
    CONFIG_OVERLAY_FS CONFIG_TMPFS_XATTR CONFIG_TMPFS_POSIX_ACL \
    CONFIG_KALLSYMS CONFIG_KALLSYMS_ALL CONFIG_BPF_EVENTS \
    CONFIG_KPROBE_EVENTS CONFIG_UPROBES CONFIG_UPROBE_EVENTS; do
    set_config "$config" y
  done
fi

if [[ "$fuse_bpf" == true ]]; then
  set_config CONFIG_FUSE_BPF y false
fi

if [[ "$btf" == true ]]; then
  set_config CONFIG_DEBUG_INFO y
  set_config CONFIG_DEBUG_INFO_DWARF4 y
  set_config CONFIG_DEBUG_INFO_BTF y
fi

if [[ "$bbg" == true ]]; then
  set_config CONFIG_BBG y
  lsm_list=$(sed -n 's/^CONFIG_LSM="\(.*\)"$/\1/p' "$defconfig" | tail -n 1)
  if [[ -z "$lsm_list" ]]; then
    lsm_list=$(awk '
      /^config LSM$/ { in_lsm = 1; next }
      in_lsm && /^[[:space:]]*(config|menuconfig)[[:space:]]+/ { exit }
      in_lsm && /^[[:space:]]*default[[:space:]]+"/ && $0 !~ /[[:space:]]if[[:space:]]/ {
        line = $0
        sub(/^[^"]*"/, "", line)
        sub(/".*$/, "", line)
        print line
        exit
      }
    ' "$kernel_source/security/Kconfig")
  fi
  if [[ -z "$lsm_list" ]]; then
    echo "unable to determine CONFIG_LSM default for Baseband Guard" >&2
    exit 1
  fi
  if [[ ",${lsm_list}," != *",baseband_guard,"* ]]; then
    if [[ ",${lsm_list}," == *",bpf,"* ]]; then
      lsm_list=${lsm_list/,bpf/,baseband_guard,bpf}
    else
      lsm_list="${lsm_list},baseband_guard"
    fi
  fi
  set_config CONFIG_LSM "\"${lsm_list}\""
fi

if [[ "$zram" == true ]]; then
  set_config CONFIG_ZSMALLOC y
  set_config CONFIG_ZRAM y
fi

if [[ "$rekernel" == true ]]; then
  set_config CONFIG_REKERNEL y
  set_config CONFIG_REKERNEL_NETWORK y
fi

if [[ "$susfs" == true ]]; then
  set_config CONFIG_KSU_SUSFS y
fi

if [[ "$droidspaces" == true ]]; then
  for config in CONFIG_SYSVIPC CONFIG_POSIX_MQUEUE CONFIG_IPC_NS CONFIG_PID_NS CONFIG_DEVTMPFS; do
    set_config "$config" y
  done
fi

if [[ "$ntsync" == true ]]; then
  set_config CONFIG_NTSYNC y
fi

sort -u -o "$expectations" "$expectations"
echo "Wrote feature expectations: $expectations"
cat "$expectations"
