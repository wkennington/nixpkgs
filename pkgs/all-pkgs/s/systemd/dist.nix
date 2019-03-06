{ stdenv
, autoconf
, automake
, fetchFromGitHub
, gnum4
, gperf
, intltool
, libtool
, libxslt

, libcap
, libgcrypt
, libgpg-error
, util-linux_lib
}:

stdenv.mkDerivation {
  name = "systemd-dist-v233-9-g265d78708";

  src = fetchFromGitHub {
    version = 6;
    owner = "triton";
    repo = "systemd";
    rev = "4af05b652703bb3f2fe493e8571243ba29a32ef1";
    sha256 = "c7f674316f56bc3d2ccbe110edd898a291d6140f2c6675d7985afd75b83b7850";
  };

  nativeBuildInputs = [
    autoconf
    automake
    gnum4
    gperf
    intltool
    libtool
  ];

  # All of these inputs are needed for the DISTFILES to generate correctly
  buildInputs = [
    libcap
    libgcrypt
    libgpg-error
    util-linux_lib
  ];

  preConfigure = ''
    ./autogen.sh

    # We don't actually want to depend on libraries just to have distfiles added correctly
    cp configure configure.old
    sed \
      -e 's,\(.*_\(TRUE\|FALSE\)=\).*,\1,g' \
      -e 's,test -z "''${[A-Za-z0-9_]*_\(TRUE\|FALSE\).*;,false;,g' \
      -i configure
  '';

  postConfigure = ''
    mv configure.old configure
  '';

  configureFlags = [
    "--disable-manpages"
  ];

  buildFlags = [
    "dist"
  ];

  installPhase = ''
    mkdir -p "$out"
    mv systemd-*.tar* "$out"
  '';

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
  };
}
