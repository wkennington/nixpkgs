{ stdenv
, fetchurl
, lib

, alsa-lib
, ffmpeg
, jack2_lib
, libsamplerate
, pulseaudio_lib
, speexdsp
}:

stdenv.mkDerivation rec {
  name = "alsa-plugins-1.1.8";

  src = fetchurl {
    url = "mirror://alsa/plugins/${name}.tar.bz2";
    multihash = "QmQ3m8YMFs3YheXb86HcGoPR149SCg9HwevtN8pB4L4NNw";
    hashOutput = false;
    sha256 = "7f77df171685ccec918268477623a39db4d9f32d5dc5e76874ef2467a2405994";
  };

  buildInputs = [
    alsa-lib
    #ffmpeg
    jack2_lib
    libsamplerate
    pulseaudio_lib
    speexdsp
  ];

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts = {
        insecureHashOutput = true;
      };
    };
  };

  meta = with lib; {
    description = "Various plugins for ALSA";
    homepage = http://alsa-project.org/;
    license = licenses.lgpl21;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
