{ stdenv
, bison
, cc
, fetchurl
, fetchTritonPatch
, gcc_lib_glibc
, glibc_progs
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

  inherit (import ./common.nix { inherit fetchurl fetchTritonPatch; })
    src
    patches
    version;
in
(stdenv.override { cc = null; }).mkDerivation rec {
  name = "glibc-${version}";

  inherit
    src
    patches;

  nativeBuildInputs = [
    bison
    cc
    python3
  ] ++ optionals (type != "bootstrap") [
    glibc_progs
  ];

  prefix = placeholder "lib";

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    "--enable-stackguard-randomization"
    "--enable-bind-now"
    "--enable-stack-protector=strong"
    "--enable-kernel=${linux-headers.channel}"
    "--disable-werror"
  ] ++ optionals (type != "bootstrap") [
    "libc_cv_use_default_link=yes"
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

    $READELF --version >/dev/null

    pushd "$lib"/lib >/dev/null
    for file in $(find * -not -type d); do
      elf=1
      $READELF -h "$file" >/dev/null 2>&1 || elf=0
      if [[ "$file" == *.so* && "$elf" == 1 ]]; then
        mkdir -p "$dev"/lib/"$(dirname "$file")"
        ln -sv "$lib"/lib/"$file" "$dev"/lib/"$file"
      else
        if [[ "$elf" == 0 ]] && grep -q 'ld script' "$file"; then
          sed -i "s,$lib,$dev,g" "$file"
        fi
        mv -v "$file" "$dev"/lib
      fi
    done
    popd >/dev/null
    mv "$dev"/lib/gconv-modules "$lib"/lib
    rm -r "$dev"/etc
    rm -r "$lib"/share
    mv "$lib"/include "$dev"

    mkdir -p "$dev"/nix-support
    echo "-idirafter $dev/include" >>"$dev"/nix-support/cflags
    echo "-B$dev/lib" >>"$dev"/nix-support/cflags
    dyld="$(echo "$lib"/lib/ld-*.so)"
    echo "-L$dev/lib" >>"$dev"/nix-support/ldflags
    echo "-dynamic-linker $dyld" >>"$dev"/nix-support/ldflags-before
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

  # Patchelf will break our loader
  dontPatchELF = true;

  # Early libs can't use some of our hardening flags
  CC_WRAPPER_CC_FORTIFY_SOURCE = false;
  CC_WRAPPER_CC_STACK_PROTECTOR = false;
  CC_WRAPPER_LD_HARDEN = false;
  CC_WRAPPER_LD_ADD_RPATH = false;

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
      i686-linux ++
      x86_64-linux ++
      powerpc64le-linux;
  };
}
