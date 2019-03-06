{ stdenv
, autoconf
, automake
, fetchFromGitHub
, libtool

, libgcrypt
, rdma-core
}:

let
  date = "2018-10-08";
  rev = "6fa5eaff13e2826d180a6e1ddb6c79a83c672ad8";
in
stdenv.mkDerivation rec {
  name = "libiscsi-${date}";

  src = fetchFromGitHub {
    version = 6;
    owner = "sahlberg";
    repo = "libiscsi";
    inherit rev;
    sha256 = "4cb3c12443500f2144e54ef963942a5989a2e6d73a0dcc75c297a3501a079d13";
  };

  nativeBuildInputs = [
    autoconf
    automake
    libtool
  ];

  buildInputs = [
    libgcrypt
    rdma-core
  ];

  preConfigure = ''
    ./autogen.sh
  '';

  configureFlags = [
    "--help"
    "--disable-werror"
    "--enable-manpages"
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
