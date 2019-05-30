{ stdenv
, fetchurl
, rustc
}:

let
  sources = {
    "${stdenv.lib.head stdenv.lib.platforms.x86_64-linux}" = {
      sha256 = "0a6d355421299c6aae50ad39c3ea3fb0573a3b207bf59c0433d50fd65cef5d15";
      platform = "x86_64-unknown-linux-gnu";
    };
  };

  version = "1.34.1";
  
  inherit (sources."${stdenv.targetSystem}")
    platform
    sha256;
in
stdenv.mkDerivation rec {
  name = "rust-std-bootstrap-${version}";
  
  src = fetchurl {
    url = "https://static.rust-lang.org/dist/rust-std-${version}-${platform}.tar.gz";
    hashOutput = false;
    inherit sha256;
  };

  installPhase = ''
    mkdir -p "$dev" "$lib"/lib
    cp -r rust-std-*/lib/rustlib/*/lib "$dev"
    mv "$dev"/lib/*.so "$lib"/lib
    FILES=($(find "$lib"/lib -type f))
    for file in "''${FILES[@]}"; do
      echo "Patching $file" >&2
      patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$file" || true
      patchelf --set-rpath "$lib/lib:${stdenv.cc.cc}/lib:${stdenv.cc.libc}/lib" "$file" || true
    done

    mkdir -p "$dev"/nix-support
    echo "$lib" >"$dev"/nix-support/propagated-native-build-inputs
  '';

  outputs = [
    "dev"
    "lib"
  ];

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src) urls outputHash outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") src.urls;
        pgpKeyFingerprints = rustc.srcVerification.pgpKeyFingerprints;
      };
    };
    inherit version;
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
