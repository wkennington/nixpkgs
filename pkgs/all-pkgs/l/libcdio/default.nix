{ stdenv
, fetchurl
, help2man
, lib

, libcddb
, ncurses
}:

stdenv.mkDerivation rec {
  name = "libcdio-2.0.0";

  src = fetchurl {
    url = "mirror://gnu/libcdio/${name}.tar.gz";
    hashOutput = false;
    sha256 = "1b481b5da009bea31db875805665974e2fc568e2b2afa516f4036733657cf958";
  };

  nativeBuildInputs = [
    help2man
  ];

  buildInputs = [
    libcddb
    ncurses
  ];

  configureFlags = [
    "--disable-maintainer-mode"
    "--disable-cpp-progs"
    "--disable-example-progs"
    "--enable-rock"
    "--enable-cddb"
    "--disable-vcd-info"
  ];

  postInstall = /* Fix hardcoded reference to the build directory */ ''
    sed -i $out/include/cdio/cdio_config.h \
      -e 's,CDIO_LIBCDIO_SOURCE_PATH.*$,CDIO_LIBCDIO_SOURCE_PATH "/no-such-path",'
  '';

  passthru = {
    srcVerification = fetchurl {
      inherit (src)
        outputHash
        outputHashAlgo
        urls;
      pgpsigUrls = map (n: "${n}.sig") src.urls;
      # R. Bernstein
      pgpKeyFingerprint = "DAA6 3BC2 5820 34A0 2B92  3D52 1A8D E500 8275 EC21";
      failEarly = true;
    };
  };

  meta = with lib; {
    description = "A library for OS-independent CD-ROM and CD image access";
    homepage = http://www.gnu.org/software/libcdio/;
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [
      codyopel
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
