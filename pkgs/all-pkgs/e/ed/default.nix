{ stdenv
, fetchurl
, lzip
}:

stdenv.mkDerivation rec {
  name = "ed-1.15";

  src = fetchurl {
    url = "mirror://gnu/ed/${name}.tar.lz";
    hashOutput = false;
    sha256 = "ad4489c0ad7a108c514262da28e6c2a426946fb408a3977ef1ed34308bdfd174";
  };

  nativeBuildInputs = [
    lzip
  ];

  doCheck = true;

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

  meta = with stdenv.lib; {
    description = "An implementation of the standard Unix editor";
    license = licenses.gpl3Plus;
    homepage = http://www.gnu.org/software/ed/;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
