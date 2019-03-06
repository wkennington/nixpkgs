{ stdenv
, fetchurl
, gnum4
, lib
, makeWrapper
, perl
, python2

, curl
, gpgme
, libarchive
, openssl
}:

stdenv.mkDerivation rec {
  name = "pacman-5.0.2";

  src = fetchurl {
    url = "https://sources.archlinux.org/other/pacman/${name}.tar.gz";
    multihash = "QmewrSbc24Q8A24XrnQCYyZ9e6A18o32vD5Zr9bFLxr9KJ";
    hashOutput = false;
    sha256 = "dfd36086ad68564bcd977f4a1fafe51dd328acd4a95093ac4bf1249be9c41f0e";
  };

  nativeBuildInputs = [
    perl
    python2
  ];

  buildInputs = [
    curl
    gpgme
    libarchive
    openssl
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    "--disable-doc"
    "--with-openssl"
    "--with-gpgme"
    "--with-libcurl"
  ];

  preBuild = ''
    find . -name Makefile -exec cat {} \;
  '';

  preInstall = ''
    installFlagsArray+=("sysconfdir=$out/etc")
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      pgpsigUrls = map (n: "${n}.sig") src.urls;
      pgpKeyFingerprint = "B815 1B11 7037 7810 9551  4CA7 BBDF FC92 306B 1121";
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
