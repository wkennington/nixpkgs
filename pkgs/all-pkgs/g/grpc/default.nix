{ stdenv
, fetchFromGitHub
, protobuf-cpp
, which

, c-ares
, gperftools
, openssl
, zlib
}:

let
  version = "1.20.1";
in
stdenv.mkDerivation {
  name = "grpc-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "grpc";
    repo = "grpc";
    rev = "v${version}";
    sha256 = "1d72dd89643f59831616bef02618f2a7ea0c66a866a73994606b5122ac95068a";
  };

  nativeBuildInputs = [
    protobuf-cpp
    which
  ];

  buildInputs = [
    c-ares
    gperftools
    openssl
    protobuf-cpp
    zlib
  ];

  postPatch = ''
    rm -r third_party/{cares,protobuf,zlib,gflags,googletest,boringssl}

    grep -q '\-Werror' Makefile
    sed -i 's,-Werror,,' Makefile
  '';

  preBuild = ''
    makeFlagsArray+=("prefix=$out")
  '';

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
