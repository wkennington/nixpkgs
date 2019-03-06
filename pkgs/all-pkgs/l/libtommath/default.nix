{ stdenv
, fetchurl
, lib
, libtool
}:

let
  version = "1.0.1";
in
stdenv.mkDerivation rec {
  name = "libtommath-${version}";

  src = fetchurl {
    url = "https://github.com/libtom/libtommath/releases/download/v${version}/ltm-${version}.tar.xz";
    hashOutput = false;
    sha256 = "47032fb39d698ce4cf9c9c462c198e6b08790ce8203ad1224086b9b978636c69";
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
