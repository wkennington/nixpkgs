#!/usr/bin/env bash
pkgs=(
  cmake
  autoconf
  automake
  libtool
  go
  gnupg
  ninja
  meson
  autogen
  libxslt
  libxml2
  yasm
  nasm
  git
  gettext
  bison
  flex
  googletest
  valgrind
  gdb
  llvm
  asciidoc
  xmlto
  docbook-xsl
  intltool
  vala
  python2
  python3
  perl
  unzip
  unrar
  itstool
  iasl
  nix_1
  nix_2
)
args=()
for pkg in "${pkgs[@]}"; do
  args+=(-A pkgs."$pkg".all)
done
set -x
exec nix-build "${args[@]}"
