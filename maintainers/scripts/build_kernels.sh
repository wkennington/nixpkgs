#!/usr/bin/env bash
kernels=(
  4-9
  4-14
  4-17
  4-18
  testing
  bcachefs
)

target="all"
if [ -n "$1" ]; then
  target="$1"
fi

args=()
for kernel in "${kernels[@]}"; do
  for output in "$target"; do
    args+=(-A pkgs.linuxPackages_${kernel}.kernel.${output})
  done
done

set -x
exec nix-build "${args[@]}"
