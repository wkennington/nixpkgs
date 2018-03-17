{ stdenv
, fetchurl
, lib

, cairo
, libsigcxx
}:

stdenv.mkDerivation rec {
  name = "cairomm-1.15.5";

  src = fetchurl {
    url = "http://cairographics.org/releases/${name}.tar.gz";
    multihash = "QmPB3QBVf5eMws5BEdB3msh9J1DkcnWDSEkjJEfa4SKpc6";
    hashOutput = false;
    sha256 = "8db629f44378cac62b4931f725520334024e62c1951c4396682f1add63c1e3d1";
  };

  buildInputs = [
    cairo
    libsigcxx
  ];

  configureFlags = [
    "--disable-maintainer-mode"
    "--disable-documentation"
    "--enable-warnings"
    "--disable-tests"
    "--enable-api-exceptions"
    "--without-libstdc-doc"
    "--without-libsigc-doc"
    "--without-boost"
    "--without-boost-unit-test-framework"
  ];

  passthru = {
    srcVerification = fetchurl {
      inherit (src)
        outputHash
        outputHashAlgo
        urls;
      failEarly = true;
      sha1Urls = map (n: "${n}.sha1.asc") src.urls;
      pgpKeyFingerprints = [
        # Murray Cumming
        "7835 91DD 0B84 B151 C957  3D66 3B76 CE0E B51B D20A"
      ];
    };
  };

  meta = with lib; {
    description = "C++ bindings for the Cairo vector graphics library";
    homepage = http://cairographics.org/cairomm;
    license = licenses.lgpl2Plus;
    maintainers = with maintainers; [
      codyopel
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
