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

  src = sources.llvm;

  nativeBuildInputs = [
    cmake
    ninja
    python
  ];

  buildInputs = [
    libffi
  ];

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

    "-DLLVM_BUILD_LLVM_DYLIB=ON"
    "-DLLVM_LINK_LLVM_DYLIB=ON"
  ];

  doCheck = true;

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
