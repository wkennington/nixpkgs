{ stdenv
, fetchurl
, fetchTritonPatch
, lib

, zlib

, target ? null
, type ? "full"
}:

let
  inherit (lib)
    boolEn
    boolWt
    optional
    optionals
    optionalAttrs
    optionalString
    stringLength;
in
stdenv.mkDerivation rec {
  name = "binutils-2.32";

  src = fetchurl {
    url = "mirror://gnu/binutils/${name}.tar.xz";
    hashOutput = false;
    sha256 = "0ab6c55dd86a92ed561972ba15b9b70a8b9f75557f896446c82e8b36e473ee04";
  };

  buildInputs = optionals (type != "bootstrap") [
    zlib
  ];

  patches = [
    (fetchTritonPatch {
      rev = "9f59f6dd9aa320bc642aaa2a679823f7f08b2190";
      file = "b/binutils/0001-bfd-No-bundled-bfd-plugin-support.patch";
      sha256 = "da0b9a2d537929db24a4bf4cbf4e5b588f64fac47d1534b72aaf37291ee55edb";
    })
  ];

  postPatch = ''
    # Don't rebuild the docs for bfd
    sed -i '/SUBDIRS/s, doc,,' bfd/Makefile.in

    # Fix host lib install directory
    find . -name configure -exec sed -i \
      's,^\([[:space:]]*bfd\(lib\|include\)dir=\).*$,\1"\\''${\2dir}",' {} \;

    # We don't want our ld to reference "dev"
    sed -i 's,"[^"]*/etc/ld.so.conf","/no-such-path/etc/ld.so.conf",' ld/emultempl/elf32.em
  '';

  preConfigure = ''
    # Clear the default library search path.
    grep -q 'NATIVE_LIB_DIRS=' ld/configure.tgt
    echo 'NATIVE_LIB_DIRS=' >> ld/configure.tgt
  '';

  prefix = placeholder "dev";

  # Needed by cross linker to search DT_RUNPATH of libs during link
  # Otherwise, we won't have the necessary search paths for transitive libs
  USE_LIBPATH = "yes";

  configureFlags = [
    "--exec-prefix=${placeholder "bin"}"
    (optionalString (target != null) "--target=${target}")
    "--enable-shared"
    "--enable-static"
    "--${boolEn (type != "bootstrap")}-nls"
    "--disable-werror"
    "--enable-deterministic-archives"
    "--${boolEn (type != "bootstrap")}-gold${optionalString (type != "bootstrap") "=default"}"
    "--${boolWt (type != "bootstrap")}-system-zlib"
    "--with-separate-debug-dir=/no-such-path/debug"
  ];

  postInstall = ''
    # Invert ld links so that ld.bfd / ld.gold are the proper tools
    ld="$(echo "$bin"/*/bin/ld)"
    if [ -z "$ld" ]; then
      ld="$bin"/bin/ld
    fi
    for prog in "$ld".*; do
      if [ -L "$prog" ]; then
        if [ "$(readlink -f "$prog")" = "$ld" ]; then
          rm -v "$prog"
          mv -v "$ld" "$prog"
          ln -srv "$prog" "$ld"
        fi
      else
        if cmp "$prog" "$ld"; then
          rm -v "$ld"
          ln -srv "$prog" "$ld"
        fi
      fi
    done

    # Make all duplicate binaries symlinks
    declare -A progMap
    for prog in "$bin"/*/bin/* "$bin"/bin/*; do
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

    # Move outputs to their final locations
    mkdir -p "$lib"/lib
    mv "$bin"/lib*/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$bin"/lib
    mv "$bin"/lib "$dev"
  '';

  preFixup = optionalString (type != "full") ''
    # Remove unused files from bootstrap
    rm -r "$dev"/share
  '' + ''
    # Missing install of private static libraries
    rm "$dev"/lib/*.la
  '';

  postFixup = ''
    ln -sv "$bin"/bin "$dev"
  '';

  outputs = [
    "dev"
    "bin"
    "lib"
  ] ++ optionals (type == "full") [
    "man"
  ];

  dontDisableStatic = true;

  meta = with lib; {
    description = "Tools for manipulating binaries (linker, assembler, etc.)";
    homepage = http://www.gnu.org/software/binutils/;
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
