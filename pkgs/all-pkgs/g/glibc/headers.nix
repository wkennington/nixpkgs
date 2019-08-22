{ stdenv
, cc
, bison
, glibc
, linux-headers
, python3
}:

(stdenv.override { cc = null; }).mkDerivation {
  name = "${glibc.name}-headers";

  inherit (glibc)
    src;

  nativeBuildInputs = [
    bison
    cc
    python3
  ];

  preConfigure = ''
    mkdir -p build
    cd build
    configureScript=../configure
  '';

  configureFlags = [
    "--disable-maintainer-mode"
    "--enable-kernel=${linux-headers.channel}"
  ];

  buildPhase = ''
    true
  '';

  installTargets = [
    "install-headers"
    "install-others-nosubdir"
  ];

  postInstall = ''
    mkdir -p "$out"/nix-support
    echo "-idirafter $out/include" >"$out"/nix-support/cflags-compile
  '';
}
