{ stdenv
, fetchTritonPatch
, fetchurl

, flac
}:

let
  inherit (stdenv.lib)
    enFlag;
in

stdenv.mkDerivation rec {
  name = "audiofile-0.3.6";

  src = fetchurl {
    url = "http://audiofile.68k.org/${name}.tar.gz";
    sha256 = "0rb927zknk9kmhprd8rdr4azql4gn2dp75a36iazx2xhkbqhvind";
  };

  buildInputs = [
    flac
  ];

  patches = [
    (fetchTritonPatch {
      rev = "28068ed0937ac9025e0605b18dd3c382d2eabad4";
      file = "audiofile/audiofile-0.3.6-CVE-2015-7747.patch";
      sha256 = "046a53b517440047a6cde81da45c6ed8611298e393b878debc1e7a8c86a4468f";
    })
  ];

  configureFlags = [
    "--enable-largefile"
    "--disable-werror"
    "--disable-coverage"
    "--disable-docs"
    "--disable-examples"
    (enFlag "flac" (flac != null) null)
  ];

  CXXFLAGS = "-std=c++03";

  meta = with stdenv.lib; {
    description = "Library for reading & writing various audio file formats";
    homepage = http://www.68k.org/~michael/audiofile/;
    license = licenses.lgpl21Plus;
    maintainers = with maintainers; [
      codyopel
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
