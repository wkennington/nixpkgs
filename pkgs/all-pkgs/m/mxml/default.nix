{ stdenv
, fetchurl
}:

let
  version = "2.12";
in
stdenv.mkDerivation rec {
  name = "mxml-${version}";

  src = fetchurl {
    url = "https://github.com/michaelrsweet/mxml/releases/download/v${version}/${name}.tar.gz";
    hashOutput = false;
    sha256 = "267ff58b64ddc767170a71dab0c729c06f45e1df9a9b6f75180b564f09767891";
  };

  configureFlags = [
    "--enable-threads"
    "--enable-shared"
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
        pgpKeyFingerprint = "C722 3EBE 4EF6 6513 B892  5989 11A3 0156 E0E6 7611";
      };
    };
  };

  meta = with stdenv.lib; {
    homepage = "https://www.msweet.org/downloads.php?L+Z3";
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
