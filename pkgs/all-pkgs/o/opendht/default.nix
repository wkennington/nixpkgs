{ stdenv
, cmake
, fetchFromGitHub
, lib
, ninja

, boost
, gnutls
, jsoncpp
, libargon2
, msgpack-c
, ncurses
, nettle
, readline
, restbed
}:

let
  version = "1.7.4";
in
stdenv.mkDerivation rec {
  name = "opendht-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "savoirfairelinux";
    repo = "opendht";
    rev = version;
    sha256 = "b86aab06989ecb263113e473a0fd18ce1b57f68934f7a99bdd9ec07b1081b797";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = [
    boost
    gnutls
    jsoncpp
    libargon2
    msgpack-c
    ncurses
    nettle
    readline
    restbed
  ];

  #postPatch = ''
  #  sed -i "s,\''${systemdunitdir},$out/lib/systemd/system,g" tools/CMakeLists.txt
  #'';

  cmakeFlags = [
    "-DOPENDHT_STATIC=OFF"
    "-DOPENDHT_SYSTEMD=ON"
    "-DOPENDHT_PROXY_SERVER=ON"
    "-DOPENDHT_PROXY_CLIENT=ON"
    "-DOPENDHT_PUSH_NOTIFICATIONS=ON"
  ];

  NIX_LDFLAGS = "-rpath ${boost.lib}/lib";

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
