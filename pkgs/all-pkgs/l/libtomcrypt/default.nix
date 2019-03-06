{ stdenv
, fetchurl
, lib
, libtool
}:

let
  version = "1.18.1";
in
stdenv.mkDerivation rec {
  name = "libtomcrypt-${version}";

  src = fetchurl {
    url = "https://github.com/libtom/libtomcrypt/releases/download/v${version}/crypt-${version}.tar.xz";
    hashOutput = false;
    sha256 = "57c13a34fbfd45696189d19e47864e48f4e5c11590c29b444accb8edbf047f14";
  };

  nativeBuildInputs = [
    libtool
  ];

  makefile = "makefile.shared";

  # The builder is broken and builds twice
  buildPhase = "true";

  preInstall = ''
    makeFlagsArray+=("PREFIX=$out")
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      pgpsigUrls = map (n: "${n}.asc") src.urls;
      pgpKeyFingerprint = "C438 6A23 7ED4 3A47 5541  B942 7B2C D0DD 4BCF F59B";
      inherit (src) urls outputHash outputHashAlgo;
    };
  };

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
