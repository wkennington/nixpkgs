{ stdenv
, cc
, bison
, fetchurl
, fetchTritonPatch
, linux-headers
, python3
}:

let
  inherit (import ./common.nix { inherit fetchurl fetchTritonPatch; })
    src
    patches
    version;
in
(stdenv.override { cc = null; }).mkDerivation {
  name = "glibc-headers-${version}";

  inherit
    src
    patches;

  nativeBuildInputs = [
    bison
    cc
    python3
  ];

  # We don't need subdirs to install the stub headers
  postPatch = ''
    sed -i '/installed-stubs/s, subdir_install,,' Makefile
  '';

  preConfigure = ''
    mkdir -p build
    cd build
    configureScript=../configure
  '';

  configureFlags = [
    "--enable-kernel=${linux-headers.channel}"
  ];

  buildPhase = ''
    true
  '';

  installTargets = [
    "install-headers"
  ];

  postInstall = ''
    # This is okay for building libgcc
    touch "$out"/include/gnu/stubs.h

    mkdir -p "$out"/nix-support
    echo "-idirafter $out/include" >"$out"/nix-support/cflags
  '';
}
