{ stdenv
, bison
, fetchTritonPatch
, fetchurl
, flex
, gnum4

, gmp
, isl
, mpc
, mpfr
, zlib

, static ? false
, shared ? true
}:

# WHEN UPDATING THE ARGUMENT LIST ALSO UPDATE STDENV.

let
  inherit (stdenv.lib)
    optional
    optionals
    optionalString;
in
stdenv.mkDerivation rec {
  name = "binutils-2.26";

  src = fetchurl {
    url = "mirror://gnu/binutils/${name}.tar.bz2";
    sha256 = "1ngc2h3knhiw8s22l8y6afycfaxr5grviqy7mwvm4bsl14cf9b62";
  };

  nativeBuildInputs = [
    bison
    flex
    gnum4
  ];

  buildInputs = [
    gmp
    isl
    mpc
    mpfr
    zlib
  ];

  patches = [
    ../../../../triton-patches/binutils/deterministic.patch
    ../../../../triton-patches/binutils/always-runpath.patch
  ];

  postPatch = ''
    # Make sure that we are not missing any determinism flags
    if grep -r '& BFD_DETERMINISTIC_OUTPUT'; then
      echo "Found DETERMINISM flags" >&2
      exit 1
    fi
  '' + optionalString (zlib != null) ''
    # We don't want to use the built in zlib
    rm -rf zlib
  '' + ''
    # Use symlinks instead of hard links to save space ("strip" in the
    # fixup phase strips each hard link separately).
    # Also disable documentation generation
    find . -name Makefile.in -exec sed -i {} -e 's,ln ,ln -s ,g' -e 's,\(SUBDIRS.*\) doc,\1,g' \;
  '';

  configureFlags = [
    "--disable-werror"
    "--enable-gold=default"
    "--enable-ld"
    "--enable-compressed-debug-sections=all"
    "--with-sysroot=/no-such-path"
    "--with-lib-path=/no-such-path"
    "--${if shared then "enable" else "disable"}-shared"
    "--enable-deterministic-archives"
    "--enable-plugins"
  ] ++ optionals (zlib != null) [
    "--with-system-zlib"
  ];

  dontDisableStatic = static;

  preBuild = ''
    makeFlagsArray+=("tooldir=$out")
  '';

  meta = with stdenv.lib; {
    description = "Tools for manipulating binaries (linker, assembler, etc.)";
    homepage = http://www.gnu.org/software/binutils/;
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux
      ++ x86_64-linux;
  };
}
