{ stdenv
, cmake
, fetchTritonPatch
, fetchurl
, gcc
, ninja
, perl
, python
, swig

, libedit
, libffi
, libtirpc
, libxml2
, ncurses
, zlib
}:

let
  sources = import ./sources.nix { inherit fetchurl; };

  inherit (stdenv.lib)
    attrValues
    filterAttrs
    isDerivation;
in
stdenv.mkDerivation {
  name = "llvm-${sources.version}";

  srcs = attrValues (filterAttrs (_: v: isDerivation v) sources);

  sourceRoot = "llvm-${sources.version}.src";

  nativeBuildInputs = [
    cmake
    ninja
    perl
    python
    swig
  ];

  buildInputs = [
    libedit
    libffi
    libtirpc
    libxml2
    ncurses
    zlib
  ];

  prePatch = ''
    mkdir -p projects
    ls .. \
      | grep '${sources.version}' \
      | grep -v 'llvm' \
      | sed 's,\(.*\)-${sources.version}.src$,../\0 projects/\1,g' \
      | xargs -n 2 mv
  '';

  patches = [
    (fetchTritonPatch {
      rev = "1a001778aab424ecd36774befa1f546b0004c5fc";
      file = "llvm/fix-llvm-config.patch";
      sha256 = "059655c0e6ea5dd248785ffc1b2e6402eeb66544ffe36ff15d76543dd7abb413";
    })
  ];

  cmakeFlags = with stdenv; [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_CXX_FLAGS=-std=c++11"

    "-DLLVM_INCLUDE_EXAMPLES=OFF"
    "-DLLVM_BUILD_TESTS=ON"
    "-DLLVM_ENABLE_RTTI=ON"
    "-DLLVM_INSTALL_UTILS=ON"  # Needed by rustc
    "-DLLVM_ENABLE_FFI=ON"

    # Not sure why these are needed
    "-DGCC_INSTALL_PREFIX=${gcc}"
    "-DC_INCLUDE_DIRS=${stdenv.cc.libc}/include"

    "-DLIBCXXABI_USE_LLVM_UNWINDER=ON"

    # TODO: Figure out how to make the single shared library work
    # for external builds
    "-DLLVM_BUILD_LLVM_DYLIB=ON"
    "-DLLVM_LINK_LLVM_DYLIB=ON"
  ];

  doCheck = true;

  passthru = {
    isClang = true;
    inherit gcc;
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
