{ stdenv
, fetchurl
, lib

, attr
}:

let
  tarballUrls = version: [
    "mirror://savannah/acl/acl-${version}.tar.gz"
  ];

  version = "2.2.53";
in
stdenv.mkDerivation rec {
  name = "acl-${version}";

  src = fetchurl {
    urls = tarballUrls version;
    hashOutput = false;
    sha256 = "06be9865c6f418d851ff4494e12406568353b891ffe1f596b34693c387af26c7";
  };

  buildInputs = [
    attr
  ];

  configureFlags = [
    "--localedir=${placeholder "bin"}/share/locale"
  ];

  preInstall = ''
    installFlagsArray+=("sysconfdir=$dev/etc")
  '';

  postInstall = ''
    mkdir -p "$bin"
    mv -v "$dev"/bin "$bin"

    mkdir -p "$lib"/lib
    mv -v "$dev"/lib*/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$dev"/lib*
  '';

  postFixup = ''
    rm -rv "$dev"/share
  '';

  outputs = [
    "dev"
    "bin"
    "lib"
    "man"
  ];

  passthru = {
    srcVerification = fetchurl rec {
      failEarly = true;
      urls = tarballUrls "2.2.53";
      pgpsigUrls = map (n: "${n}.sig") urls;
      pgpKeyFingerprints = [
        "600C D204 FBCE A418 BD2C  A74F 1543 4326 0542 DF34"
        # Mike Frysinger
        "B902 B527 1325 F892 AC25  1AD4 4163 3B9F E837 F581"
      ];
      inherit (src) outputHashAlgo;
      outputHash = "06be9865c6f418d851ff4494e12406568353b891ffe1f596b34693c387af26c7";
    };
  };

  meta = with lib; {
    description = "Library and tools for manipulating access control lists";
    homepage = http://savannah.nongnu.org/projects/acl;
    license = licenses.lgpl21;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux
      ++ x86_64-linux;
  };
}
