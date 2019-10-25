{ stdenv
, cc
, fetchurl
}:

let
  version = "1.1.24";
in
(stdenv.override { cc = null; }).mkDerivation rec {
  name = "musl-${version}";

  src = fetchurl {
    url = "https://www.musl-libc.org/releases/${name}.tar.gz";
    multihash = "QmT6j4ASw3xhXSMrdoN2tRuNz9E9ZgsaDU5DuV9XfXt3VE";
    hashOutput = false;
    sha256 = "1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3";
  };

  nativeBuildInputs = [
    cc
  ];

  postInstall = ''
    mkdir -p "$lib"/lib
    mv "$dev"/lib/*.so* "$lib"/lib
    ln -sv "$lib"/lib/* "$dev"/lib

    mkdir -p "$bin"/bin
    ln -sv "$lib"/lib/libc.so "$bin"/bin/ldd

    mkdir -p "$dev"/nix-support
    echo "-idirafter $dev/include" >"$dev"/nix-support/cflags
    echo "-B$dev/lib" >"$dev"/nix-support/cflags-link
    echo "-dynamic-linker $lib/lib/libc.so" >"$dev"/nix-support/ldflags-before
    echo "-L$dev/lib" >"$dev"/nix-support/ldflags
  '';

  # Can't force the libc to use this
  CC_WRAPPER_CC_STACK_PROTECTOR = false;

  outputs = [
    "dev"
    "bin"
    "lib"
  ];

  allowedReferences = outputs;

  passthru = {
    inherit version;
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
      powerpc64le-linux
      ++ i686-linux
      ++ x86_64-linux;
  };
}
