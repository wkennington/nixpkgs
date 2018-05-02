#!/usr/bin/env bash
pkgs=(
  acmetool
  alertmanager
  consul
  consulfs
  consul-replicate
  consul-template
  dnscrypt-proxy
  elvish
  etcd
  fs-repo-migrations
  grafana
  gx
  hugo
  influxdb
  ipfs
  ipfs-cluster
  lego
  lxd
  madns
  mc
  minio
  mongodb-tools
  nomad
  prometheus
  rclone
  syncthing
  teleport
  vault
)
args=()
for pkg in "${pkgs[@]}"; do
  args+=(-A pkgs."$pkg".bin)
done
set -x
exec nix-build --show-trace -k "${args[@]}"
