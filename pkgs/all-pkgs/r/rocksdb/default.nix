{ stdenv
, fetchFromGitHub
, perl
, which

, bzip2
, gflags
, jemalloc
, lz4
, numactl
, snappy
, zlib
, zstd
}:

let
  version = "6.0.2";
in
stdenv.mkDerivation rec {
  name = "rocksdb-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "facebook";
    repo = "rocksdb";
    rev = "v${version}";
    sha256 = "1603f5d0401043871a06d6cb9bc5fb14eb6aaf7c7f2e69a34db88bbee256aded";
  };

  nativeBuildInputs = [
    perl
    which
  ];

  buildInputs = [
    bzip2
    gflags
    jemalloc
    lz4
    numactl
    snappy
    zlib
    zstd
  ];

  postPatch = ''
    patchShebangs build_tools
  '';

  # Environment vars used for building certain configurations
  DISABLE_WARNING_AS_ERROR = "1";
  PORTABLE = "1";
  USE_SSE = "1";
  JEMALLOC_LIB = "-ljemalloc";

  makeFlags = [
    "USE_RTTI=1" # Needed for ceph
    "DEBUG_LEVEL=0"
  ];

  buildFlags = [
    "shared_lib"
    "static_lib"
  ];

  installFlags = [
    "INSTALL_PATH=\${out}"
  ];

  installTargets = [
    "install-shared"
    "install-static"
  ];

  postInstall = ''
    # Might eventually remove this when we are confident in the build process
    echo "BUILD CONFIGURATION FOR SANITY CHECKING"
    cat make_config.mk
  '';

  meta = with stdenv.lib; {
    homepage = http://rocksdb.org;
    description = "A library that provides an embeddable, persistent key-value store for fast storage";
    license = licenses.bsd3;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
