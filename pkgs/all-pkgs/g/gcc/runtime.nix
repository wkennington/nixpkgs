{ stdenv
, cc
, hostcc
, gcc
, gcc_lib
}:

(stdenv.override { cc = null; }).mkDerivation rec {
  name = "gcc-runtime-${gcc.version}";

  src = gcc.src;

  patches = gcc.patches;

  nativeBuildInputs = [
    cc
    hostcc
  ];

  configureFlags = gcc.commonConfigureFlags ++ [
    "--with-system-libunwind"
  ];

  postPatch = ''
    mkdir -p mpfr/src mpc gmp
    sed -i 's,^maybe-all-gcc: .*,maybe-all-gcc:,' Makefile.in
    sed -i 's,^\(maybe-\(all\|install\)-target-libgcc:\) .*,\1,' Makefile.in
  '';

  preConfigure = ''
    mkdir -v build
    cd build
    tar xf '${gcc_lib.internal}'/build.tar.xz
    find . -type f -exec sed -i "s,/build-dir,$NIX_BUILD_TOP,g" {} \;
    configureScript='../configure'
  '';

  preBuild = ''
    buildFlagsArray+=(RAW_CXX_FOR_TARGET="$CC")
  '';

  buildFlags = [
    "all-target"
  ];

  installTargets = [
    "install-target"
  ];

  postInstall = ''
    mv "$dev"/lib/gcc/*/*/include/* "$dev"/include
    rm -rv "$dev"/lib/gcc

    mkdir -p "$lib"/lib "$libcxx"/lib "$libsan"/lib "$libssp"/lib
    mv "$dev"/lib*/libstdc++*.so* "$libcxx"/lib
    rm "$libcxx"/lib/*.py
    mv "$dev"/lib*/*san.so* "$libsan"/lib
    mv "$dev"/lib*/libssp.so* "$libssp"/lib
    mv "$dev"/lib*/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$libcxx"/lib "$libsan"/lib/* "$libssp"/lib/* "$dev"/lib

    mkdir -p "$dev"/nix-support
    echo "-idirafter $dev/include" >>"$dev"/nix-support/cflags
    echo "-L$dev/lib" >>"$dev"/nix-support/ldflags
    cxxinc="$(dirname "$(dirname "$dev"/include/c++/*/*/bits/c++config.h)")"
    echo "-idirafter $(dirname "$cxxinc")" >>"$dev"/nix-support/cxxflags
    echo "-idirafter $cxxinc" >>"$dev"/nix-support/cxxflags
  '';

  preFixup = ''
    rm -r "$dev"/share
  '';

  outputs = [
    "dev"
    "lib"
    "libcxx"
    "libsan"
    "libssp"
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux ++
      x86_64-linux ++
      powerpc64le-linux;
  };
}
