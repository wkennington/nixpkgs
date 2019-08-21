{ stdenv
, cc
, fetchurl
, gcc
, libc

, type ? null
}:

let
  inherit (stdenv.lib)
    optionals
    optionalString;
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

  postInstall = ''
    mv -v "$dev"/lib/gcc/*/*/* "$dev"/lib
    rm -r "$dev"/lib/gcc

    mv "$dev"/lib/include "$dev"

    mkdir -p "$lib"/lib
    for file in "$dev"/lib*/*; do
      elf=1
      readelf -h "$file" >/dev/null 2>&1 || elf=0
      if [[ "$file" == *.so* && "$elf" == 1 ]]; then
        mv "$file" "$lib"/lib
      fi
    done
    ln -sv "$lib"/lib/* "$dev"/lib

    mkdir -p "$dev"/nix-support
    echo "-B$dev/lib" >>"$dev"/nix-support/cflags-compile
    echo "-idirafter $dev/include" >>"$dev"/nix-support/cflags-compile
    # We need to inject this rpath since some of our shared objects are
    # linker scripts like libc.so and our linker script doesn't interpret
    # ld scripts
    echo "-rpath $lib/lib" >>"$dev"/nix-support/ldflags
    echo "-L$dev/lib" >>"$dev"/nix-support/ldflags
  '';

  # We want static libgcc
  disableStatic = false;

  outputs = [
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
