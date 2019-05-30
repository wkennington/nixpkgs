#!/usr/bin/env bash
kernels=(
  4-19
  5-0
  5-1
  testing
  bcachefs
)

target="${1:-all}"
shift

args=()
for kernel in "${kernels[@]}"; do
  for output in "$target"; do
    args+=(-A pkgs.linuxPackages_${kernel}.kernel.${output})
  done
done

set -x
exec nix-build "${args[@]}" "$@"
