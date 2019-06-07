{ stdenv
, cmake
, fetchTritonPatch
, fetchurl
, gcc
, ninja
, python3

, llvm
, ncurses
, perl
, z3
, zlib
}:

let
  inherit (llvm)
    version
    srcs
    srcUrls;
in
stdenv.mkDerivation {
  name = "clang-${version}";

  src = fetchurl {
    urls = srcUrls "cfe";
    inherit (srcs.cfe)
      sha256;
  };

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    llvm
    ncurses
    perl
    z3
    zlib
  ];

  preConfigure = ''
    prefix="$dev"
  '';

  cmakeFlags = [
    "-DGCC_INSTALL_PREFIX=${gcc}"
    "-DCLANG_ANALYZER_Z3_INSTALL_DIR=${z3}"
  ];

  preBuild = ''
    export NIX_LDFLAGS="$NIX_LDFLAGS -rpath $lib/lib"
  '';

  postInstall = ''
    mkdir -p "$lib"/lib
    mv "$dev"/lib/*.so* "$lib"/lib
    mv "$dev"/libexec "$lib"

    mkdir -p "$bin"
    mv -v "$dev"/bin "$bin"
    ln -sv clang++ "$bin"/bin/c++
    ln -sv clang "$bin"/bin/cc
    ln -sv "$lib"/libexec "$bin"

    mkdir -p "$man"/share
    mv -v "$dev"/share/man "$man"/share

    mkdir -p "$cc_headers"
    mv "$dev"/lib/clang/*/include "$cc_headers"
    rmdir "$dev"/lib/clang/*
    rmdir "$dev"/lib/clang
  '';

  outputs = [
    "dev"
    "bin"
    "man"
    "lib"
    "cc_headers"
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
