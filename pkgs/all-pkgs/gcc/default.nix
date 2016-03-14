{ stdenv
, bison
, fetchurl
, flex
, gettext
, gnum4
, perl

, gmp
, isl
, mpc
, libunwind
, mpfr
, zlib

, channel ? "6"
, bootstrap ? false
, libPathExcludes ? [ ]
}:

# WHEN UPDATING THE ARGUMENT LIST ALSO UPDATE STDENV.

let
  sources = import ./sources.nix;

  source = sources."${channel}";

  inherit (stdenv.lib)
    optionals
    optionalString;
in
stdenv.mkDerivation rec {
  name = "gcc-${source.version}";

  src = fetchurl {
    url = "mirror://gnu/gcc/${name}/${name}.tar.bz2";
    inherit (source) sha256;
  };

  nativeBuildInputs = [
    bison
    flex
    gettext
    gnum4
    perl
  ];

  buildInputs = optionals (!bootstrap) [
    gmp
    isl
    mpc
    mpfr
    zlib
  ];

  # We don't want any of the debug info built as it is huge
  # and slow to generate.
  CFLAGS="-O2";
  CXXFLAGS="-O2";

  patches = [
    ../../../../triton-patches/gcc/dont-look-in-usr.patch
    ../../../../triton-patches/gcc/use-source-date-epoch.patch
  ];

  postPatch = optionalString bootstrap ''
    # We need to make sure the sources for libraries exist in the root directory
    # During a bootstrap build where we don't have the libraries available
    # ahead of time.
    unpackFile ${gmp.src}
    mv gmp-* gmp
    unpackFile ${isl.src}
    mv isl-* isl
    unpackFile ${mpc.src}
    mv mpc-* mpc
    unpackFile ${mpfr.src}
    mv mpfr-* mpfr
  '' + optionalString (zlib != null) ''
    # We don't want to use the included zlib
    rm -r zlib
  '';

  configureFlags = [
    "--with-libffi"
    "--with-libatomic"
    "--enable-static"
    "--${if !bootstrap then "enable" else "disable"}-shared"
    "--with-pic"
    "--enable-gold=default"
    "--enable-ld"
    "--with-sysroot=/no-such-path"
    "--with-local-prefix=/no-such-path"
    "--with-native-system-header-dir=/no-such-path"
    "--${if !bootstrap then "with" else "without"}-headers"
    "--${if !bootstrap then "enable" else "disable"}-decimal-float"
    "--${if !bootstrap then "enable" else "disable"}-libquadmath"
    "--${if !bootstrap then "enable" else "disable"}-libquadmath-support"
    "--${if !bootstrap then "enable" else "disable"}-libatomic"
    "--disable-libgcj"
    "--disable-libada"
    "--${if !bootstrap then "enable" else "disable"}-libgomp"
    "--${if !bootstrap then "enable" else "disable"}-libcilkrts"
    "--${if !bootstrap then "enable" else "disable"}-libssp"
    "--${if !bootstrap then "enable" else "disable"}-libstdcxx"
    "--disable-liboffloadmic"
    "--${if !bootstrap then "enable" else "disable"}-libitm"
    "--${if !bootstrap then "enable" else "disable"}-libsanitizer"
    "--${if !bootstrap then "enable" else "disable"}-libvtv"
    "--${if !bootstrap then "enable" else "disable"}-libmpx"
    "--${if bootstrap then "enable" else "disable"}-bootstrap"
    (if bootstrap then null else "--with-mpc")
    (if bootstrap then null else "--with-mpfr")
    (if bootstrap then null else "--with-gmp")
    (if bootstrap then null else "--with-isl")
    "--enable-lto"
    "--${if bootstrap then "with" else "without"}-newlib"
    "--${if !bootstrap then "enable" else "disable"}-nls"
    "--${if zlib != null then "with" else "without"}-system-zlib"
    "--without-tcl"
    "--without-tk"
    "--${if !bootstrap then "enable" else "disable"}-threads"
    "--disable-symbols"
    "--${if libunwind != null then "with" else "without"}-system-libunwind"
    "--with-zlib"
    "--disable-multilib"
    "--disable-checking"
    "--disable-coverage"
    "--disable-multiarch"
    "--${if !bootstrap then "enable" else "disable"}-tls"
    "--enable-languages=c,c++"
    (if bootstrap then "--with-build-config=bootstrap-lto" else null)
  ];

  preBuild = ''
    TARGET_FLAGS=" -Wl,-L${stdenv.libc} -Wl,-rpath${stdenv.libc}"
    makeFlagsArray+=(
      "CFLAGS_FOR_TARGET=$TARGET_FLAGS"
      "CXXFLAGS_FOR_TARGET=$TARGET_FLAGS"
      "FLAGS_FOR_TARGET=$TARGET_FLAGS"
      "LDFLAGS_FOR_TARGET=$TARGET_FLAGS"
    )
  '';

  buildFlags = optionals bootstrap [
    "BOOT_CFLAGS=-O2" # Reduces the size of the intermediate binaries
    "bootstrap-lean" # Removes files as they are no longer needed
  ];

  dontDisableStatic = true;

  parallelBuild = false; # REMOVE

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux
      ++ x86_64-linux;
  };
}
