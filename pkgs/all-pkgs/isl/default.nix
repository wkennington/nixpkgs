{ stdenv
, fetchurl

, gmp

, channel ? "0.17"
}:

let
  channels = {
    "0.17" = {
      version = "0.17.1";
      sha256 = "0iqnffl4c0znkyp5c9vh4wx9y4nqcrb4n6f6yja7aivbh5f2w5dy";
    };
    "0.16" = {
      version = "0.16.1";
      sha256 = "00jb3s5aavidfna1rr49mfsyjy9ayx6h414q001rr2ybncq2yaa5";
    };
    "0.14" = {
      version = "0.14.1";
      sha256 = "1m922l5bz69lvkcxrib7lvjqwfqsr8rpbzgmb2aq07bp76460jha";
    };
  };

  channelData = channels."${channel}";
in

stdenv.mkDerivation rec {
  name = "isl-${channelData.version}";

  src = fetchurl {
    url = "http://isl.gforge.inria.fr/${name}.tar.xz";
    inherit (channelData) sha256;
  };

  buildInputs = [
    gmp
  ];

  meta = with stdenv.lib; {
    homepage = http://www.kotnet.org/~skimo/isl/;
    description = "A library for manipulating sets and relations of integer points bounded by linear constraints";
    license = licenses.mit;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux
      ++ x86_64-linux;
  };
}
