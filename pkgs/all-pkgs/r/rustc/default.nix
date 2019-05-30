{ stdenv
, cargo
, fetchurl
, lib
, python3
, rustc

, llvm
, xz

, channel
}:

let
  channels = {
    stable = rec {
      version = "1.35.0";
      src = fetchurl {
        url = "https://static.rust-lang.org/dist/rustc-${version}-src.tar.gz";
        hashOutput = false;
        sha256 = "5a4d637a716bac18d085f44dd87ef48b32195f71b967d872d80280b38cff712d";
      };
    };
  };

  inherit (lib)
    head
    platforms;

  targets = {
    "${head platforms.x86_64-linux}" = "x86_64-unknown-linux-gnu";
  };

  inherit (channels."${channel}")
    version
    src
    deps;
in
stdenv.mkDerivation {
  name = "rustc-${version}";

  inherit src;

  nativeBuildInputs = [
    cargo
    python3
    rustc
  ];

  buildInputs = [
    xz
  ];

  # This breaks compilation
  fixLibtool = false;

  # Don't install anything we don't need as part of the compiler toolchain
  # These should be generated separately as needed
  postPatch = ''
    sed -i '/install::\(Docs\|Src\),/d' src/bootstrap/builder.rs
  '';

  configureFlags = [
    "--enable-parallel-compiler"
    "--enable-local-rust"
    "--enable-llvm-link-shared"
    "--enable-vendor"
    "--enable-optimize"
    "--llvm-root=${llvm}"
    "--release-channel=${channel}"
  ];

  buildPhase = ''
    # Ensure our binaries point to our libdir
    export NIX_LDFLAGS="$NIX_LDFLAGS -rpath $lib/lib"

    # Build the initial bootstrapper and tools
    NIX_RUSTFLAGS_OLD="$NIX_RUSTFLAGS"
    export NIX_RUSTFLAGS="$NIX_RUSTFLAGS -L${rustc.lib}/lib -L${rustc.dev}/lib"
    python3 x.py build -j $NIX_BUILD_CORES --stage 0 src/none || true
    python3 x.py build -j $NIX_BUILD_CORES --stage 0 src/tools/rust-installer

    # Buid system expects directories to exist
    mkdir -p "$out"

    # Begin building the bootstrap
    export NIX_RUSTFLAGS="$NIX_RUSTFLAGS_OLD"
    python3 x.py build -j $NIX_BUILD_CORES --stage 0
    python3 x.py install -j $NIX_BUILD_CORES --keep-stage 0
  '';

  installPhase = ''
    # Remove logs and manifests generated during install
    find "$out"/lib/rustlib -mindepth 1 -maxdepth 1 -type f -delete

    mkdir -p "$std"
    mv "$(find "$out"/lib/rustlib -name lib -type d)" "$std"/lib
  '';

  outputs = [
    "out"
    "dev"
    "lib"
  ];

  setupHook = ./setup-hook.sh;

  passthru = {
    inherit
      cargo
      rustc
      version
      targets;

    srcVerification = fetchurl {
      failEarly = true;
      inherit (src) urls outputHash outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") src.urls;
        pgpKeyFingerprint = "108F 6620 5EAE B0AA A8DD  5E1C 85AB 96E6 FA1B E5FE";
      };
    };
  };

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
