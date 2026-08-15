#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: verify_kernel_config.sh <final-config> <expectations>" >&2
  exit 2
fi

final_config=$1
expectations=$2
[[ -f "$final_config" ]] || { echo "final kernel config not found: $final_config" >&2; exit 1; }
[[ -f "$expectations" ]] || { echo "feature expectations not found: $expectations" >&2; exit 1; }

failures=0
while IFS= read -r expectation; do
  [[ -z "$expectation" || "$expectation" == '#'* ]] && continue
  case "$expectation" in
    EXACT:*)
      line=${expectation#EXACT:}
      if ! grep -Fqx -- "$line" "$final_config"; then
        echo "missing final config: $line" >&2
        failures=$((failures + 1))
      fi
      ;;
    REGEX:*)
      regex=${expectation#REGEX:}
      if ! grep -Eq -- "$regex" "$final_config"; then
        echo "final config does not match: $regex" >&2
        failures=$((failures + 1))
      fi
      ;;
    *)
      echo "invalid expectation record: $expectation" >&2
      failures=$((failures + 1))
      ;;
  esac
done < "$expectations"

if [[ $failures -ne 0 ]]; then
  echo "$failures requested kernel configuration value(s) were dropped by Kconfig" >&2
  exit 1
fi

echo "All requested kernel features are present in the final .config"
