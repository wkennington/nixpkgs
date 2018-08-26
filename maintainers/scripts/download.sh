#!/usr/bin/env bash
set -e
set -o pipefail

cd "$(dirname "$0")"
DRV="$(nix-instantiate ../../pkgs/stdenv/linux/testing.nix -A "$1")"

declare -A checked

dl() {
  local drv="${1%\!*}"
  if [ "${checked["$drv"]}" = "1" ]; then
    return 0
  fi
  checked["$drv"]=1
  if grep -q '"outputHash"' "$drv"; then
    echo "$drv"
    return 0
  fi
  for drv in $(cat "$drv" | tr '"' "\n" | grep '\.drv'); do
    dl "$drv"
  done
}
#exec nix-store --realize $(dl "$DRV")
exec nix build $(dl $DRV)
