{ stdenv
, bison
, cc
, fetchurl
, fetchTritonPatch
, gcc_lib_glibc
, libidn2_glibc
, linux-headers
, python3

, type ? "full"
}:

let
  inherit (stdenv.lib)
    boolEn
    boolWt
    optional
    optionals
    optionalAttrs
    optionalString;

  version = "2.30";
in
(stdenv.override { cc = null; }).mkDerivation (rec {
  name = "glibc-${version}";

  src = fetchurl {
    url = "mirror://gnu/glibc/${name}.tar.xz";
    hashOutput = false;
    sha256 = "e2c4114e569afbe7edbc29131a43be833850ab9a459d81beb2588016d2bbb8af";
  };

  nativeBuildInputs = [
    bison
    cc
    python3
  ];

  # Some of the tools depend on a shell. Set to impure /bin/sh to
  # prevent a retained dependency on the bootstrap tools in the stdenv-linux
  # bootstrap.
  BASH_SHELL = "/bin/sh";

  patches = [
    (fetchTritonPatch {
      rev = "081b7a40d174baf95f1979ff15c60b49c8fdc30d";
      file = "g/glibc/0001-Fix-common-header-paths.patch";
      sha256 = "df93cbd406a5dd2add2dd0d601ff9fc97fc42a1402010268ee1ee8331ec6ec72";
    })
    (fetchTritonPatch {
      rev = "081b7a40d174baf95f1979ff15c60b49c8fdc30d";
      file = "g/glibc/0002-sunrpc-Don-t-hardcode-cpp-path.patch";
      sha256 = "7a9ce7f69cd6d3426d19a8343611dc3e9c48e3374fa1cb8b93c5c98d7e79d69b";
    })
    (fetchTritonPatch {
      rev = "081b7a40d174baf95f1979ff15c60b49c8fdc30d";
      file = "g/glibc/0003-timezone-Fix-zoneinfo-path-for-triton.patch";
      sha256 = "b4b47be63c3437882a160fc8d9b8ed7119ab383b1559599e2706ce8f211a0acd";
    })
    (fetchTritonPatch {
      rev = "081b7a40d174baf95f1979ff15c60b49c8fdc30d";
      file = "g/glibc/0004-nsswitch-Try-system-paths-for-modules.patch";
      sha256 = "9cd235f0699661cbfd0b77f74c538d97514ba450dfba9a3f436adc2915ae0acf";
    })
    (fetchTritonPatch {
      rev = "b772989f030aef70b8b5fd39a3bb04738d50b383";
      file = "g/glibc/0005-locale-archive-Support-multiple-locale-archive-locat.patch";
      sha256 = "3ab23b441e573e51ee67a8e65a3c0c5a40d8d80805838a389b9abca08c45156c";
    })
    (fetchTritonPatch {
      rev = "cf6beafafc0d218cf156e3713fe62c0e53629419";
      file = "g/glibc/0006-Add-C.UTF-8-Support.patch";
      sha256 = "07f61db686dc36bc009999cb8d686581a29b13a0d2dd3f7f0b74cdfe964a0540";
    })
  ];

  # We don't want to rewrite the paths to our dynamic linkers for ldd
  # Just use the paths as-is.
  postPatch = ''
    grep -q '^ldd_rewrite_script=' sysdeps/unix/sysv/linux/x86_64/configure
    find sysdeps -name configure -exec sed -i '/^ldd_rewrite_script=/d' {} \;
  '';

  prefix = placeholder "lib";

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    "--disable-maintainer-mode"
    "--enable-stackguard-randomization"
    "--enable-bind-now"
    "--enable-stack-protector=strong"
    "--enable-kernel=${linux-headers.channel}"
    "--disable-werror"
    "--${boolEn (type == "full")}-build-nscd"
  ];

  preConfigure = ''
    mkdir -v build
    cd build
    configureScript='../configure'
  '';
  
  preBuild = ''
    # We don't want to use the ld.so.cache from the system
    grep -q '#define USE_LDCONFIG' config.h
    echo '#undef USE_LDCONFIG' >>config.h

    # Don't build programs
    echo "build-programs=no" >>configparms
  '';

  preInstall = ''
    installFlagsArray+=(
      "sysconfdir=$dev/etc"
      "localstatedir=$TMPDIR"
    )
  '';

  postInstall = ''
    mkdir -p "$dev"/lib

    for file in "$lib"/lib/*; do
      elf=1
      readelf -h "$file" >/dev/null 2>&1 || elf=0
      if [[ "$file" == *.so* && "$elf" == 1 ]]; then
        ln -s "$file" "$dev"/lib
      else
        if [[ "$elf" == 0 ]] && grep -q 'ld script' "$file"; then
          sed -i "s,$lib,$dev,g" "$file"
        fi
        mv "$file" "$dev"/lib
      fi
    done
    mv "$lib"/{include,share} "$dev"

    mkdir -p "$dev"/nix-support
    echo "-idirafter $dev/include" >>"$dev"/nix-support/cflags-compile
    echo "-B$dev/lib" >>"$dev"/nix-support/cflags-compile
    dyld="$lib"/lib/ld-*.so
    echo "-dynamic-linker $dyld" >>"$dev"/nix-support/ldflags-before
    # We need to inject this rpath since some of our shared objects are
    # linker scripts like libc.so and our linker script doesn't interpret
    # ld scripts
    echo "-rpath $lib/lib" >>"$dev"/nix-support/ldflags
    echo "-L$dev/lib" >>"$dev"/nix-support/ldflags
  '' + optionalString (type != "bootstrap") ''
    # Ensure we always have a fallback C.UTF-8 locale-archive
    export LOCALE_ARCHIVE="$lib"/lib/locale/locale-archive
    mkdir -p "$(dirname "$LOCALE_ARCHIVE")"
    localedef -i C -f UTF-8 C.UTF-8
  '';

  outputs = [
    "dev"
    "lib"
  ];

  # Don't retain shell referencs
  dontPatchShebangs = true;

  # Early libs can't use some of our hardening flags
  NIX_CC_FORTIFY_SOURCE = false;
  NIX_CC_STACK_PROTECTOR = false;
  NIX_LD_HARDEN = false;
  NIX_LD_ADD_RPATH = false;

  passthru = {
    impl = "glibc";
    inherit version;
    cc_reqs = stdenv.mkDerivation {
      name = "glibc-cc_reqs-${version}";

      buildCommand = ''
        mkdir -p "$out"/nix-support
        echo "-L${gcc_lib_glibc}/lib -L${libidn2_glibc}/lib --push-state --no-as-needed -lidn2 -lgcc_s --pop-state" >"$out"/nix-support/ldflags-dynamic
      '';
    };
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
} // optionalAttrs (type == "full") {
  setupHook = ./setup-hook.sh;
})
