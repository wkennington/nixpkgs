{ stdenv
, cc
, fetchurl
, gcc

, type ? null
}:

let
  inherit (stdenv.lib)
    optionals
    optionalString;
in
(stdenv.override { cc = null; }).mkDerivation rec {
  name = "libgcc${optionalString (type != null) "-${type}"}-${gcc.version}";

  inherit (gcc)
    src
    patches;

  nativeBuildInputs = [
    cc
  ];

  prefix = placeholder "dev";

  configureFlags = gcc.commonConfigureFlags ++ optionals (type == "nolibc") [
    "--disable-shared"
    "--disable-gcov"
  ];

  postPatch = ''
    mkdir -v build
    cd build
    tar xf '${gcc.internal}'/build.tar.xz
    find . -type f -exec sed -i "s,/build-dir,$NIX_BUILD_TOP,g" {} \;
    mkdir -p x/libgcc
    cd x/libgcc
    configureScript='../../../libgcc/configure'
    chmod +x "$configureScript"
  '';

  postInstall = ''
    mv -v "$dev"/lib/gcc/*/*/* "$dev"/lib
    rm -r "$dev"/lib/gcc

    mv "$dev"/lib/include "$dev"

    mkdir -p "$lib"/lib
    for file in "$dev"/lib*/*; do
      elf=1
      readelf -h "$file" >/dev/null 2>&1 || elf=0
      if [[ "$file" == *.so* && "$elf" == 1 ]]; then
        mv "$file" "$lib"/lib
      fi
    done
    ln -sv "$lib"/lib/* "$dev"/lib

    mkdir -p "$dev"/nix-support
    echo "-B$dev/lib" >>"$dev"/nix-support/cflags-compile
    echo "-idirafter $dev/include" >>"$dev"/nix-support/cflags-compile
    echo "-L$dev/lib" >>"$dev"/nix-support/ldflags
  '' + optionalString (type != "nolibc") ''
    # We need to inject this rpath since some of our shared objects are
    # linker scripts like libc.so and our linker script doesn't interpret
    # ld scripts
    echo "-rpath $lib/lib" >>"$dev"/nix-support/ldflags

    find . -not -type d -and -not -name '*'.h -delete
    find . -type f -exec sed -i "s,$NIX_BUILD_TOP,/build-dir,g" {} \;
    mkdir -p "$internal"
    cd ../..
    tar Jcf "$internal"/build.tar.xz x/libgcc
  '' + optionalString (type == "nolibc") ''
    # GCC will pull in gcc_eh during linking, but a libc shouldn't need
    # the exception handling symbols
    ln -sv libgcc.a "$dev"/lib/libgcc_eh.a
  '';

  # We want static libgcc
  disableStatic = false;

  outputs = [
    "dev"
    "lib"
  ] ++ optionals (type != "nolibc") [
    "internal"
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
