{ stdenv
, cc
, fetchurl
}:

(stdenv.override { cc = null; }).mkDerivation rec {
  name = "musl-1.1.23";

  src = fetchurl {
    url = "https://www.musl-libc.org/releases/${name}.tar.gz";
    multihash = "QmdJfuZf7VdcfVW6vixRgCvWKAGedbxoTnwi2qm2cKQfBs";
    hashOutput = false;
    sha256 = "8a0feb41cef26c97dde382c014e68b9bb335c094bbc1356f6edaaf6b79bd14aa";
  };

  nativeBuildInputs = [
    cc
  ];

  prefix = placeholder "dev";

  configureFlags = [
    "--enable-shared"
    "--enable-static"
  ];

  postInstall = ''
    mkdir -p "$lib"/lib
    mv "$dev"/lib/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$dev"/lib

    mkdir -p "$bin"/bin
    ln -sv "$lib"/lib/libc.so "$bin"/bin/ldd

    mkdir -p "$dev"/nix-support
    echo "-idirafter $dev/include" >"$dev"/nix-support/cflags-compile
    echo "-B$dev/lib" >"$dev"/nix-support/cflags-link
    echo "-dynamic-linker $lib/lib/libc.so" >"$dev"/nix-support/ldflags-before
    echo "-L$dev/lib" >"$dev"/nix-support/ldflags
  '';

  # Can't force the libc to use this
  stackProtector = false;

  # We need this for embedded things like busybox
  disableStatic = false;

  # Dont depend on a shell potentially from the bootstrap
  dontPatchShebangs = true;

  outputs = [
    "dev"
    "bin"
    "lib"
  ];

  allowedReferences = outputs;

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") src.urls;
        pgpKeyFingerprint = "8364 8929 0BB6 B70F 99FF  DA05 56BC DB59 3020 450F";
      };
    };
  };

  meta = with stdenv.lib; {
    description = "An efficient, small, quality libc implementation";
    homepage = "http://www.musl-libc.org";
    license = licenses.mit;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
