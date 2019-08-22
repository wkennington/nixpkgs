{ stdenv
, cc
, fetchurl
, gcc
, gcc_lib
}:

(stdenv.override { cc = null; }).mkDerivation rec {
  name = "libstdcxx-${gcc.version}";

  src = gcc.src;

  patches = gcc.patches;

  nativeBuildInputs = [
    cc
  ];

  prefix = placeholder "dev";

  configureFlags = gcc.commonConfigureFlags;

  preConfigure = ''
    mkdir -v build
    cd build
    tar xf '${gcc_lib.internal}'/build.tar.xz
    find . -type f -exec sed -i "s,/build-dir,$NIX_BUILD_TOP,g" {} \;
    mkdir -p x/libstdc++-v3
    cd x/libstdc++-v3
    configureScript='../../../libstdc++-v3/configure'
    chmod +x "$configureScript"
  '';

  NIX_DEBUG = true;

  postConfigure = ''
    cat config.log
    exit 1
  '';

  postInstall = ''
    rm -r "$dev"/share

    mkdir -p "$lib"/lib
    mv "$dev"/lib*/*.so* "$lib"/lib
    mv "$lib"/lib/*.py "$dev"/lib
    ln -sv "$lib"/lib/* "$dev"/lib

    mkdir -p "$dev"/nix-support
    cxxinc="$(dirname "$(dirname "$dev"/include/c++/*/*/bits/c++config.h)")"
    echo "-idirafter $(dirname "$cxxinc")" >>"$dev"/nix-support/cxxflags-compile
    echo "-idirafter $cxxinc" >>"$dev"/nix-support/cxxflags-compile
    echo "-L$dev/lib" >>"$dev"/nix-support/ldflags
  '';

  outputs = [
    "dev"
    "lib"
  ];

  # We want static libstdc++
  disableStatic = false;

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
