{ stdenv
, fetchTritonPatch
, fetchurl

, binutils
, gmp
, isl
, libc
, libmpc
, linux-headers
, mpfr
, zlib

, target ? null
, type ? "full"
}:

let
  inherit (stdenv.lib)
    boolEn
    boolWt
    optional
    optionals
    optionalAttrs
    optionalString
    stringLength;

  checking =
    if type == "bootstrap" then
      "yes"
    else
      "release";

  commonConfigureFlags = [
    (optionalString (target != null) "--target=${target}")
    "--${boolEn (type != "bootstrap")}-gcov"
    "--disable-multilib"
    "--disable-maintainer-mode"
    "--disable-bootstrap"
    "--enable-languages=c,c++"
    "--disable-werror"
    "--enable-checking=${checking}"
    "--${boolEn (type != "bootstrap")}-nls"
    "--enable-cet=auto"
    "--with-glibc-version=2.28"
  ];

  runtimeConfigureFlags = [
    "--${boolWt (type != "bootstrap")}-system-libunwind"
  ];

  version = "9.2.0";
in
stdenv.mkDerivation rec {
  name = "gcc-${version}";

  src = fetchurl {
    url = "mirror://gnu/gcc/${name}/${name}.tar.xz";
    hashOutput = false;
    sha256 = "ea6ef08f121239da5695f76c9b33637a118dcf63e24164422231917fa61fb206";
  };

  nativeBuildInputs = [
    binutils.bin
  ];

  buildInputs = optionals (type != "bootstrap") [
    gmp
    isl
    libmpc
    mpfr
    zlib
  ];

  patches = [
    (fetchTritonPatch {
      rev = "07997b8b1232810806ea323cc44d460ee78c1174";
      file = "g/gcc/9.1.0/0001-libcpp-Enforce-purity-BT_TIMESTAMP.patch";
      sha256 = "0d5754d2262fcc349edd8eabe20ddd04494593965859b9e37ee983a6bdc4c47f";
    })
    (fetchTritonPatch {
      rev = "07997b8b1232810806ea323cc44d460ee78c1174";
      file = "g/gcc/9.1.0/0002-c-ada-spec-Workaround-for-impurity-detection.patch";
      sha256 = "156d4a1c885c28b4b4196ceed3ba7b2da0c1fdcc0261e4222c2cfc06296c53ec";
    })
    (fetchTritonPatch {
      rev = "07997b8b1232810806ea323cc44d460ee78c1174";
      file = "g/gcc/9.1.0/0003-gcc-Don-t-hardcode-startfile-locations.patch";
      sha256 = "b5e0f27cf755b066df82d668a3728b28a1a13359272ffe37e106e1164eb3a81f";
    })
    (fetchTritonPatch {
      rev = "07997b8b1232810806ea323cc44d460ee78c1174";
      file = "g/gcc/9.1.0/0004-cppdefault-Don-t-add-a-default-local_prefix-include.patch";
      sha256 = "410f5251b08493d0917018a28fcabe468762e1edc5050fa23fdcc02c30a9c79f";
    })
  ];

  prePatch = optionalString (type == "bootstrap") ''
    ! test -e gmp
    unpackFile '${gmp.src}'
    mv gmp-* gmp
    ! test -e mpc
    unpackFile '${libmpc.src}'
    mv mpc-* mpc
    ! test -e mpfr
    unpackFile '${mpfr.src}'
    mv mpfr-* mpfr
  '';

  prefix = placeholder "bin";

  configureFlags = commonConfigureFlags ++ [
    "--enable-host-shared"
    "--${boolEn (type != "bootstrap")}-lto"
    "--enable-linker-build-id"
    "--${boolWt (type != "bootstrap")}-system-zlib"
    (optional (type == "bootstrap") "--without-headers")
    "--with-local-prefix=/no-such-path/local-prefix"
    "--with-native-system-header-dir=/no-such-path/native-headers"
    "--with-debug-prefix-map=$NIX_BUILD_TOP=/no-such-path"
  ];

  preConfigure = ''
    mkdir -v build
    cd build
    configureScript='../configure'
  '';

  preBuild = ''
    sed -i '/^TOPLEVEL_CONFIGURE_ARGUMENTS=/d' Makefile
  '';

  buildFlags = [
    "all-host"
  ];

  installTargets = [
    "install-host"
  ];

  postInstall = ''
    rm -v "$bin"/bin/*-${version}
  '' + optionalString (type == "bootstrap") ''
    # GCC won't include our libc limits.h if we don't fix it
    cat ../gcc/{limitx.h,glimits.h,limity.h} >"$bin"/lib/gcc/*/*/include-fixed/limits.h

    rm -rv "$bin"/lib/gcc/*/*/install-tools

    mkdir -p "$cc_headers"
    mv -v "$bin"/lib/gcc/*/*/include "$cc_headers"
    mv -v "$bin"/lib/gcc/*/*/include-fixed "$cc_headers"
    mkdir -p "$cc_headers"/nix-support
    echo "-idirafter $cc_headers/include" >>"$cc_headers"/nix-support/cflags-compile
    echo "-idirafter $cc_headers/include-fixed" >>"$cc_headers"/nix-support/cflags-compile

    mkdir -p "$lib"/lib "$dev"/lib
    mv -v "$bin"/lib*/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$dev"/lib

    find "$bin"/lib -name '*'.la

    mv "$bin"/{include,share} "$dev"

    pfx=
  '' + optionalString (target != null) ''
    if [ -e "$bin"/bin/${target}-gcc ]; then
      pfx=${target}-
    fi
  '' + ''
    # CC does not get installed for some reason
    ln -srv "$bin"/bin/''${pfx}gcc "$bin"/bin/''${pfx}cc

    find . -not -type d -and -not -name '*'.mvars -and -not -name Makefile -and -not -name '*'.h -delete
    find . -type f -exec sed -i "s,$NIX_BUILD_TOP,/build-dir,g" {} \;
    mkdir -p "$internal"
    tar Jcf "$internal"/build.tar.xz .

    # Hash the tools and deduplicate
    declare -A progMap
    for prog in "$bin"/bin/*; do
      if [ -L "$prog" ]; then
        continue
      fi
      checksum="$(cksum "$prog" | cut -d ' ' -f1)"
      oProg="''${progMap["$checksum"]}"
      if [ -z "$oProg" ]; then
        progMap["$checksum"]="$prog"
      elif cmp "$prog" "$oProg"; then
        rm "$prog"
        ln -srv "$oProg" "$prog"
      fi
    done

    # We don't need the install-tools for anything
    # They sometimes hold references to interpreters
    rm -rv "$bin"/libexec/gcc/*/*/install-tools
  '';

  preFixup = optionalString (type != "full") ''
    # Remove unused files from bootstrap
    rm -r "$dev"/share
  '' + ''
    # We don't need the libtool archive files so purge them
    # TODO: Fixup libtool archives so we don't reference an old compiler
    find "$dev"/lib* -name '*'.la -delete
  '';

  postFixup = ''
    ln -sv "$cc_headers" "$dev"/cc_headers
    ln -sv "$bin"/bin "$dev"
  '';

  outputs = [
    "dev"
    "bin"
    "lib"
    "cc_headers"
    "internal"
  ] ++ optionals (type == "full") [
    "man"
  ];

  # We want static libgcc_s
  disableStatic = false;

  passthru = {
    inherit target version commonConfigureFlags;
    impl = "gcc";

    cc = "gcc";
    cpp = "cpp";
    cxx = "g++";
    optFlags = [ ];
    prefixMapFlag = "-ffile-prefix-map";
    canStackClashProtect = true;
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
