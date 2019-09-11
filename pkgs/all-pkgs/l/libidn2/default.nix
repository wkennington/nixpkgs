{ stdenv
, cc
, fetchurl
, hostcc

, libunistring
}:

let
  version = "2.2.0";

  tarballUrls = version: [
    "mirror://gnu/libidn/libidn2-${version}.tar.gz"
  ];
in
(stdenv.override { cc = null; }).mkDerivation rec {
  name = "libidn2-${version}";

  src = fetchurl {
    urls = tarballUrls version;
    hashOutput = false;
    sha256 = "fc734732b506d878753ec6606982bf7b936e868c25c30ddb0d83f7d7056381fe";
  };

  nativeBuildInputs = [
    cc
    hostcc
  ];

  buildInputs = [
    libunistring
  ];

  configureFlags = [
    "--localedir=${placeholder "bin"}/share/locale"
    "--disable-doc"
  ];

  postInstall = ''
    mkdir -p "$bin"
    mv -v "$dev"/bin "$bin"

    mkdir -p "$lib"/lib
    mv -v "$dev"/lib*/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$dev"/lib
  '';

  outputs = [
    "dev"
    "bin"
    "lib"
  ];

  passthru = {
    srcVerification = fetchurl rec {
      failEarly = true;
      urls = tarballUrls "2.2.0";
      inherit (src) outputHashAlgo;
      outputHash = "fc734732b506d878753ec6606982bf7b936e868c25c30ddb0d83f7d7056381fe";
      fullOpts = {
        pgpsigUrls = map (n: "${n}.sig") urls;
        pgpKeyFingerprint = "1CB2 7DBC 9861 4B2D 5841  646D 0830 2DB6 A267 0428";
      };
    };
  };

  meta = with stdenv.lib; {
    homepage = http://www.gnu.org/software/libidn/;
    description = "Library for internationalized domain names";
    license = licenses.lgpl2Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux ++
      x86_64-linux ++
      powerpc64le-linux;
  };
}
