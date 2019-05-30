{ stdenv
, fetchurl
, rustc
, rust-std
}:

let
  sources = {
    "${stdenv.lib.head stdenv.lib.platforms.x86_64-linux}" = {
      sha256 = "881d1b87acae926afd9cb7dbb9de8092143ffd1d72622829b138a195a2a5ef5b";
      platform = "x86_64-unknown-linux-gnu";
    };
  };

  version = "1.34.1";
  
  inherit (sources."${stdenv.targetSystem}")
    platform
    sha256;
in
stdenv.mkDerivation rec {
  name = "rustc-bootstrap-${version}";
  
  src = fetchurl {
    url = "https://static.rust-lang.org/dist/rustc-${version}-${platform}.tar.gz";
    hashOutput = false;
    inherit sha256;
  };

  installPhase = ''
    mkdir -p "$out"/bin "$dev"/lib "$lib"/lib
    rm rustc/bin/rust-*
    rm -r rustc/lib/rustlib/etc
    rm -r rustc/lib/rustlib/*/{bin,lib}
    cp -r rustc/bin/* "$out"/bin
    cp -r rustc/lib/* "$dev"/lib
    mv "$dev"/lib/*.so "$dev"/lib/rustlib/*/codegen-backends "$lib"/lib
    for file in $(find "$lib"/lib "$dev"/lib -type f); do
      name="$(basename "$file")"
      if [ -e "${rust-std.lib}/lib/$name" ] || [ -e "${rust-std.dev}/lib/$name" ]; then
        rm "$file"
      fi
    done
    FILES=($(find "$out"/bin "$lib"/lib -type f))
    for file in "''${FILES[@]}"; do
      echo "Patching $file" >&2
      patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$file" || true
      patchelf --set-rpath "$lib/lib:${rust-std.lib}/lib:${stdenv.cc.cc}/lib:${stdenv.cc.libc}/lib" "$file" || true
    done

    ln -sv "$lib"/lib "$out"/lib

    mkdir -p "$dev"/nix-support
    echo "$lib" >"$dev"/nix-support/propagated-native-build-inputs
  '';

  outputs = [
    "out"
    "dev"
    "lib"
  ];

  setupHook = ./setup-hook.sh;
  
  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src) urls outputHash outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") src.urls;
        pgpKeyFingerprints = rustc.srcVerification.pgpKeyFingerprints;
      };
    };
    inherit
      version
      platform;
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
