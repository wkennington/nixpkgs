{ stdenv
, fetchurl
, makeWrapper

, rustc
, zlib
}:

let
  sources = {
    "${stdenv.lib.head stdenv.lib.platforms.x86_64-linux}" = {
      sha256 = "35da884d43a8620534f6da1fbdd05f1e1f24823749f93d3d3be0eb46b3a6d884";
      platform = "x86_64-unknown-linux-gnu";
    };
  };

  version = "0.28.0";

  inherit (sources."${stdenv.targetSystem}")
    platform
    sha256;
in
stdenv.mkDerivation rec {
  name = "cargo-bootstrap-${version}";

  src = fetchurl {
    url = "https://static.rust-lang.org/dist/cargo-${version}-${platform}.tar.gz";
    hashOutput = false;
    inherit sha256;
  };

  nativeBuildInputs = [
    makeWrapper
  ];

  installPhase = ''
    mkdir -p "$out"
    cp -r cargo/bin "$out/bin"
    patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" --set-rpath "${stdenv.cc.cc}/lib:${zlib}/lib" $out/bin/*
    wrapProgram $out/bin/cargo --suffix PATH : "${rustc}/bin"

    # Check that we can launch cargo
    $out/bin/cargo --help
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      pgpsigUrls = map (n: "${n}.asc") src.urls;
      pgpKeyFingerprints = rustc.srcVerification.pgpKeyFingerprints;
      inherit (src) urls outputHash outputHashAlgo;
    };
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
