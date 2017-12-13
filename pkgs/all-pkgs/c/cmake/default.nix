{ stdenv
, cmake
, fetchTritonPatch
, fetchurl
, ninja

, bzip2
, curl
, expat
, jsoncpp
, libarchive
, libuv
, ncurses
, rhash
, xz
, zlib

, bootstrap ? false
}:

let
  inherit (stdenv.lib)
    optionals
    optionalString;

  majorVersion = "3.10";
  minorVersion = "0";
  version = "${majorVersion}.${minorVersion}";
in
stdenv.mkDerivation rec {
  name = "cmake${optionalString bootstrap "-bootstrap"}-${version}";

  src = fetchurl {
    url = "https://cmake.org/files/v${majorVersion}/cmake-${version}.tar.gz";
    multihash = "QmTJw6hcnomaqzkxyK5Ehnqferxm1kJ39mLTFXzensQNN6";
    sha256 = "b3345c17609ea0f039960ef470aa099de9942135990930a57c14575aae884987";
  };

  patches = [
    (fetchTritonPatch {
      rev = "e6b0d2af7e353e719ea3bb38f550111dab30cd91";
      file = "c/cmake/0001-Fix-search-paths.patch";
      sha256 = "e7c0b304f3c7340d22a44ecff64bd6d9f3997f12f437594f7ec59e5864a5e23a";
    })
  ];

  nativeBuildInputs = optionals (!bootstrap) [
    cmake
    ninja
  ];

  buildInputs = optionals (!bootstrap) [
    bzip2
    curl
    expat
    jsoncpp
    libarchive
    libuv
    ncurses
    rhash
    xz
    zlib
  ];

  postPatch = optionalString (!bootstrap) ''
    sed -i '/CMAKE_USE_SYSTEM_/s,OFF,ON,g' CMakeLists.txt
  '';

  preConfigure = ''
    substituteInPlace Modules/Platform/UnixPaths.cmake \
      --subst-var-by libc ${stdenv.libc}
  '' + optionalString bootstrap ''
    fixCmakeFiles .

    configureFlagsArray+=("--parallel=$NIX_BUILD_CORES")
  '';

  configureFlags = optionals bootstrap [
    "--no-system-libs"
    "--docdir=/share/doc/${name}"
    "--mandir=/share/man"
  ];

  # Cmake flags are only used by the final build of cmake
  cmakeFlags = optionals (!bootstrap) [
    "-DCMAKE_USE_SYSTEM_KWIML=OFF"
  ];

  setupHook = ./setup-hook.sh;
  selfApplySetupHook = true;
  cmakeConfigure = !bootstrap;

  meta = with stdenv.lib; {
    description = "Cross-Platform Makefile Generator";
    homepage = http://www.cmake.org/;
    license = licenses.free; # cmake
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
