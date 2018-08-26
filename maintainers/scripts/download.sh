#!/usr/bin/env bash
set -e
set -o pipefail

cd "$(dirname "$0")"
DRV="$(nix-instantiate ../.. -A "$1" 2>/dev/null)"

declare -A checked

dl() {
  if [ "${checked["$1"]}" = "1" ]; then
    return 0
  fi
  checked["$1"]=1
  if grep -q '"outputHash"' "$1"; then
    echo "$1"
    return 0
  fi
  for drv in $(cat "$1" | tr '"' "\n" | grep '\.drv'); do
    dl "$drv"
  done
}
#exec nix-store --realize $(dl "$DRV")
exec nix build $(dl $DRV)
