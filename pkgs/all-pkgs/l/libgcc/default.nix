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
    patches;

  prefix = placeholder "dev";

  configureFlags = optionals (type == "bootstrap") [
    "--host=${gcc.target}"
    "--disable-shared"
    "--disable-gcov"
    "--disable-maintainer-mode"
    "--with-glibc-version=2.30"
  ];

  postPatch = ''
    mkdir -p "$NIX_BUILD_TOP"/include
    #touch "$NIX_BUILD_TOP"/include/tconfig.h
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h >"$NIX_BUILD_TOP"/include/limits.h
    cp gcc/gsyslimits.h "$NIX_BUILD_TOP"/include/syslimits.h
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -isystem $NIX_BUILD_TOP/include"

    mkdir -p ../gcc
    touch ../gcc/libgcc.mvars

    mkdir -v build
    cd build
    tar xvf ${../../../../build.tar.xz}
    find . -type f -exec sed -i "s,/build-dir,$NIX_BUILD_TOP,g" {} \;
    cd */libgcc
    configureScript='../libgcc/configure'
    chmod +x "$configureScript"
  '';

  NIX_CFLAGS_COMPILE = "-DIN_GCC -DCROSS_DIRECTORY_STRUCTURE";

  #preBuild = ''
  #  cat config.log
  #'';

  #buildTargets = [
  #  "all-libgcc-target"
  #];

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
