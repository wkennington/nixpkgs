{ stdenv
, glibc
, musl
}:

stdenv.mkDerivation {
  name = "${musl.name}-headers";

  inherit (musl)
    src;

  preConfigure = ''
    mkdir -p build
    cd build
    configureScript=../configure
  '';

  configureFlags = [
    "--host=${glibc.host}"
  ];

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
