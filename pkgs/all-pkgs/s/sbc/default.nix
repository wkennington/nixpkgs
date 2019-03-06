{ stdenv
, fetchurl

, libsndfile
}:

stdenv.mkDerivation rec {
  name = "sbc-1.4";

  src = fetchurl {
    url = "https://www.kernel.org/pub/linux/bluetooth/${name}.tar.xz";
    sha256 = "518bf46e6bb3dc808a95e1eabad26fdebe8a099c1e781c27ed7fca6c2f4a54c9";
  };

  buildInputs = [
    libsndfile
  ];

  meta = with stdenv.lib; {
    description = "SubBand Codec Library";
    homepage = http://www.bluez.org/;
    license = licenses.gpl2;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
