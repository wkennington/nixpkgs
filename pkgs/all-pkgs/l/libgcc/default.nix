{ stdenv
, fetchurl
, gcc
, glibc

, type
}:

let
  inherit (stdenv.lib)
    optionals;
in
stdenv.mkDerivation rec {
  name = "libgcc-${gcc.version}";

  inherit (gcc.override { inherit type; })
    src
    patches
    configureFlags;

  prefix = placeholder "dev";

  /*configureFlags = optionals (type == "bootstrap") [
    "--disable-shared"
    "--disable-gcov"
    "--disable-maintainer-mode"
    "--disable-decimal-float"
    "--with-glibc-version=2.28"
  ];

  preConfigure = ''
    mkdir -p "$NIX_BUILD_TOP"/include
    touch "$NIX_BUILD_TOP"/include/limits.h
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -isystem $NIX_BUILD_TOP/include"

    mkdir -p ../gcc
    touch ../gcc/libgcc.mvars

    mkdir -v build
    cd build
    configureScript='../libgcc/configure'
    chmod +x "$configureScript"
  '';*/

  buildFlags = [
    "all-target-libgcc"
  ];

  # We want static libgcc
  disableStatic = false;

  outputs = [
    "dev"
    "lib"
  ];

  # Ensure we don't depend on anything unexpected
  allowedReferences = [
    "dev"
    "lib"
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
