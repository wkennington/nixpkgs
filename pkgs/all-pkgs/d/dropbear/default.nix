{ stdenv
, fetchurl
, lib

, libtomcrypt
, libtommath
, pam
, zlib
}:

stdenv.mkDerivation rec {
  name = "dropbear-2018.76";

  src = fetchurl {
    url = "https://matt.ucc.asn.au/dropbear/releases/${name}.tar.bz2";
    multihash = "QmdbJACjvvkBxMY2Ji6hKW4dnHXfk4Jc7pwrDRFHuPCNR3";
    hashOutput = false;
    sha256 = "f2fb9167eca8cf93456a5fc1d4faf709902a3ab70dd44e352f3acbc3ffdaea65";
  };

  buildInputs = [
    libtomcrypt
    libtommath
    pam
    zlib
  ];

  configureFlags = [
    "--enable-pam"
    "--disable-bundled-libtom"
  ];

  preBuild = ''
    cat default_options.h
    cat options.h
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      pgpsigUrls = map (n: "${n}.asc") src.urls;
      pgpKeyFingerprint = "F734 7EF2 EE2E 07A2 6762  8CA9 4493 1494 F29C 6773";
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
