{ stdenv
, cc
, fetchurl
}:

let
  inherit (import ./default.nix { cc = null; inherit fetchurl stdenv; })
    src
    meta
    version;
in
(stdenv.override { cc = null; }).mkDerivation {
  name = "musl-headers-${version}";

  inherit
    src
    meta;

  nativeBuildInputs = [
    cc
  ];

  preConfigure = ''
    mkdir -p build
    cd build
    configureScript=../configure
  '';

  buildPhase = ''
    true
  '';

  installTargets = [
    "install-headers"
  ];

  postInstall = ''
    mkdir -p "$out"/nix-support
    echo "-idirafter $out/include" >"$out"/nix-support/cflags
  '';
}
