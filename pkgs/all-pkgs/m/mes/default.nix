{ stdenv
, fetchurl
, lib
, guile
}:

stdenv.mkDerivation rec {
  name = "mes-0.19";

  src = fetchurl {
    url = "mirror://gnu/mes/${name}.tar.gz";
    hashOutput = false;
    sha256 = "80866b6bef36551cb6522083385dc717aa3fc397c2462aaf6c8035ee15f40496";
  };

  nativeBuildInputs = [
    guile
  ];

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.sig") src.urls;
        pgpKeyFingerprint = "1D41 C14B 272A 2219 A739  FA4F 8FE9 9503 132D 7742";
      };
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
