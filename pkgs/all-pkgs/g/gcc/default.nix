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

  target =
    if type == "bootstrap" then
      "x86_64-tritonboot-linux-gnu"
    else
      "x86_64-pc-linux-gnu";

  nativeHeaders =
    if type == "bootstrap" then
      "/no-such-path/native-headers"
    else
      "${libc}/include";

  checking =
    if type == "bootstrap" then
      "yes"
    else
      "release";

  version = "9.2.0";
in
stdenv.mkDerivation (rec {
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

  configureFlags = [
    "--target=${target}"
    "--${boolEn (type != "bootstrap")}-shared"
    "--enable-host-shared"
    "--${boolEn (type != "bootstrap")}-gcov"
    "--disable-multilib"
    "--${boolEn (type != "bootstrap")}-threads"
    "--disable-maintainer-mode"
    "--disable-bootstrap"
    "--enable-languages=c,c++"
    "--${boolEn (type != "bootstrap")}-libsanitizer"
    (optional (type == "bootstrap") "--disable-libssp")
    "--${boolEn (type != "bootstrap")}-libquadmath"
    "--${boolEn (type != "bootstrap")}-libgomp"
    "--${boolEn (type != "bootstrap")}-libvtv"
    "--${boolEn (type != "bootstrap")}-libatomic"
    "--${boolEn (type != "bootstrap")}-libitm"
    "--${boolEn (type != "bootstrap")}-libmpx"
    "--${boolEn (type != "bootstrap")}-libhsail-rt"
    "--${boolEn (type != "bootstrap")}-libstdcxx"
    "--disable-werror"
    "--enable-checking=${checking}"
    "--${boolEn (type != "bootstrap")}-nls"
    (optional (type == "bootstrap") "--disable-decimal-float")
    "--${boolEn (type != "bootstrap")}-lto"
    "--with-glibc-version=2.28"
    (optional (type == "bootstrap") "--without-headers")
    "--${boolWt (type != "bootstrap")}-system-libunwind"
    "--${boolWt (type != "bootstrap")}-system-zlib"
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
  '' + optionalString (type != "bootstrap") ''
    # Our compiler needs to get libc objects
    # Normally using -B${libc}/lib works but libtool filters
    # that out for some of the runtime library builds
    mkdir gcc
    ln -sv "${libc}"/lib/*.o gcc/

    # Our libc needs linux/limits.h for its limits.h
    makeFlagsArray+=("CPPFLAGS_FOR_TARGET=-idirafter ${linux-headers}/include")
    flags=(
      "-idirafter" "${linux-headers}/include"

      # Libc library configs
      "-L${libc}/lib"
      "-Wl,-dynamic-linker=$(echo ${libc}/lib/ld-linux-*.so*)"
      "-Wl,-rpath=${libc}/lib"
    )
    oldifs="$IFS"
    IFS=" "
    makeFlagsArray+=("CFLAGS_FOR_TARGET=''${flags[*]}")
    makeFlagsArray+=("CXXFLAGS_FOR_TARGET=''${flags[*]}")
    makeFlagsArray+=("LDFLAGS_FOR_TARGET=''${flags[*]}")
    IFS="$oldifs"
  '';

  buildTargets = [
    "all-host"
  ];

  installTargets = [
    "install-host"
  ];

  postInstall = ''
    rm "$dev"/bin/*-${version}
  '' + optionalString (type == "bootstrap") ''
    # GCC won't include our libc limits.h if we don't fix it
    cat ../gcc/{limitx.h,glimits.h,limity.h} >"$dev"/lib/gcc/*/*/include-fixed/limits.h

    rm -r "$dev"/lib/gcc/*/*/install-tools

    mkdir -p "$cc_headers"
    mv "$dev"/lib/gcc/*/*/include "$cc_headers"
    mv "$dev"/lib/gcc/*/*/include-fixed "$cc_headers"
    mkdir -p "$cc_headers"/nix-support
    echo "-idirafter $cc_headers/include" >>"$cc_headers"/nix-support/cflags-compile
    echo "-idirafter $cc_headers/include-fixed" >>"$cc_headers"/nix-support/cflags-compile

    mkdir -p "$lib"/lib
    ls -la "$dev" "$dev"/lib*
    mv "$dev"/lib*/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$dev"/lib

    mkdir -p "$bin"/lib
    mv -v "$dev"/{bin,libexec} "$bin"
    mv -v "$dev"/lib/gcc "$bin"/lib

    # CC does not get installed for some reason
    ln -srv "$bin"/bin/${target}-gcc "$bin"/bin/${target}-cc

    # Ensure we have all of the non-prefixed tools
    #for prog in "$bin"/bin/${target}-*; do
    #  base="$(basename "$prog")"
    #  tool="$bin/bin/''${base:${toString (stringLength (target + "-"))}}"
    #  rm -fv "$tool"
    #  ln -srv "$prog" "$tool"
    #done

    find . -not -type d -and -not -name '*'.mvars -and -not -name Makefile -and -not -name '*'.h -delete
    find . -type f -exec sed -i "s,$NIX_BUILD_TOP,/build-dir,g" {} \;
    mkdir -p "$internal"
    tar Jcf "$internal"/build.tar.xz .
  '' + optionalString (type != "bootstrap") ''
    # CC does not get installed for some reason
    ln -srv "$bin"/bin/gcc "$bin"/bin/cc
  '' + ''
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

  prefix = placeholder "dev";

  NIX_LDFLAGS = "-rpath ${placeholder "lib"}/lib";

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
    inherit target version;
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
} // optionalAttrs (type != "bootstrap") {
  # Ensure we don't depend on anything unexpected
  allowedReferences = [
    "out"
    gmp
    isl
    libc
    libmpc
    linux-headers
    mpfr
    zlib
  ] ++ stdenv.cc.runtimeLibcxxLibs;
})
