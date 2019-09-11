{ stdenv
, fetchTritonPatch
, fetchurl

, icu
, xz
, zlib
}:

let
  version = "2.9.9";

  tarballUrls = version: [
    "http://xmlsoft.org/sources/libxml2-${version}.tar.gz"
  ];
in
stdenv.mkDerivation rec {
  name = "libxml2-${version}";

  src = fetchurl {
    urls = tarballUrls version;
    multihash = "QmZW6enUX5jA8JNCK72oQnCiaG4FEPuCHoC84yg12WyDqA";
    hashOutput = false;
    sha256 = "94fb70890143e3c6549f265cee93ec064c80a84c42ad0f23e85ee1fd6540a871";
  };

  buildInputs = [
    icu
    xz
    zlib
  ];

  postPatch = ''
    find . -name Makefile.in -exec sed -i '/^SUBDIRS /s, \(doc\|example\),,g' {} \;
  '';

  configureFlags = [
    "--with-icu"
  ];

  installTargets = [
    "install-libLTLIBRARIES"
    "install-data"
  ];

  postInstall = ''
    mkdir -p "$lib"/lib
    mv -v "$dev"/lib*/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$dev"/lib
  '';

  postFixup = ''
    mkdir -p "$dev"/share2
    mv -v "$dev"/share/aclocal "$dev"/share2
    rm -rv "$dev"/share
    mv "$dev"/share2 "$dev"/share
  '';

  outputs = [
    "dev"
    "lib"
  ];

  passthru = {
    srcVerification = fetchurl rec {
      failEarly = true;
      urls = tarballUrls "2.9.9";
      inherit (src) outputHashAlgo;
      outputHash = "94fb70890143e3c6549f265cee93ec064c80a84c42ad0f23e85ee1fd6540a871";
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") urls;
        pgpKeyFingerprint = "C744 15BA 7C9C 7F78 F02E  1DC3 4606 B8A5 DE95 BC1F";
      };
    };
  };

  meta = with stdenv.lib; {
    homepage = http://xmlsoft.org/;
    description = "An XML parsing library for C";
    license = licenses.mit;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
