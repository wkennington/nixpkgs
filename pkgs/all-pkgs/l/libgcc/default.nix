{ stdenv
, binutils
, fetchurl
, gcc
, wrapCCNew

, type ? null
}:

let
  inherit (stdenv.lib)
    optionals
    optionalString;

  cc = wrapCCNew {
    compiler = gcc.bin;
    tools = [ binutils.bin ];
    inputs = [ gcc.cc_headers ];
    target = gcc.target;
  };
in
(stdenv.override { cc = null; }).mkDerivation rec {
  name = "libgcc${optionalString (type != null) "-${type}"}-${gcc.version}";

  inherit (gcc)
    src
    patches;

  nativeBuildInputs = [
    cc
  ];

  prefix = placeholder "dev";

  configureFlags = [
    "--host=${gcc.target}"
    "--disable-maintainer-mode"
    "--with-glibc-version=2.30"
  ] ++ optionals (type == "nolibc") [
    "--disable-shared"
    "--disable-gcov"
  ];

  postPatch = optionalString (type == "nolibc") ''
    # We need a fake limits file to pass configure
    mkdir -p "$NIX_BUILD_TOP"/include
    touch "$NIX_BUILD_TOP"/include/limits.h
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -isystem $NIX_BUILD_TOP/include"
  '' + ''
    mkdir -v build
    cd build
    tar xf '${gcc.internal}'/build.tar.xz
    find . -type f -exec sed -i "s,/build-dir,$NIX_BUILD_TOP,g" {} \;
    cd */libgcc
    configureScript='../../../libgcc/configure'
    chmod +x "$configureScript"
  '';

  makeFlags = optionals (type == "nolibc") [
    "thread_header=gthr-single.h"
  ];

  postInstall = optionalString (type == "nolibc") ''
    mkdir -p "$lib"
  '' + ''
    mv -v "$dev"/lib/gcc/*/*/* "$dev"/lib
    rm -r "$dev"/lib/gcc

    mkdir -p "$dev"/nix-support
    echo "-B$dev/lib" >>"$dev"/nix-support/cflags-compile
    echo "-L$dev/lib" >>"$dev"/nix-support/ldflags
  '';

  preFixup = ''
    strip() {
      ${gcc.target}-strip "$@"
    }
    set -x
  '';

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
