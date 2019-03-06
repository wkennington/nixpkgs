{ stdenv
, fetchurl
, lib

, alsa-lib
, fftw_single
, libsamplerate
, ncurses
, systemd-dummy
}:

stdenv.mkDerivation rec {
  name = "alsa-utils-1.1.8";

  src = fetchurl {
    url = "mirror://alsa/utils/${name}.tar.bz2";
    multihash = "QmZdozgz3BmfMTX8TppasYuSWCqFCfcLKyrivWnreQgNn8";
    hashOutput = false;
    sha256 = "fd9bf528922b3829a91913b89a1858c58a0b24271a7b5f529923aa9ea12fa4cf";
  };

  buildInputs = [
    alsa-lib
    fftw_single
    libsamplerate
    ncurses
    systemd-dummy
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    "--disable-alsatest"  # This is just a test case program
    "--disable-alsaconf"  # Not needed with udev
    "--disable-xmlto"     # Man pages are pre-generated
    "--disable-rst2man"   # Man pages are pre-generated
  ];

  preInstall = ''
    installFlagsArray+=(
      "systemdsystemunitdir=$out/lib/systemd/system"
      "ASOUND_STATE_DIR=$TMPDIR"
    )
  '';

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
    description = "ALSA, the Advanced Linux Sound Architecture utils";
    homepage = http://www.alsa-project.org/;
    license = licenses.gpl2;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
