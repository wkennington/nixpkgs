{ stdenv
, cargo
, cc_gcc_new
, fetchurl
, lib
, python3
, rustc

, llvm_split
, xz

, channel
}:

let
  channels = {
    stable = rec {
      version = "1.36.0";
      src = fetchurl {
        url = "https://static.rust-lang.org/dist/rustc-${version}-src.tar.gz";
        hashOutput = false;
        sha256 = "04c4e4d7213d036d6aaed392841496d272146312c0290f728b7400fccd15bb1b";
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
(stdenv.override { cc = cc_gcc_new; }).mkDerivation {
  name = "rustc-${version}";

  inherit src;

  nativeBuildInputs = [
    cargo
    python3
    rustc
  ];

  buildInputs = [
    llvm_split
    xz
  ];

  # This breaks compilation
  fixLibtool = false;

  postPatch = ''
    # Don't install anything we don't need as part of the compiler toolchain
    # These should be generated separately as needed
    sed -i '/install::\(Docs\|Src\),/d' src/bootstrap/builder.rs

    # Don't hardcode references to llvm dev files
    sed -i 's,let cfg_llvm_root =.*;,let cfg_llvm_root = "";,' src/librustc_codegen_llvm/context.rs
  '';

  configureFlags = [
    "--enable-parallel-compiler"
    "--enable-local-rust"
    "--enable-llvm-link-shared"
    "--enable-vendor"
    "--enable-optimize"
    "--llvm-root=${llvm_split}"
    "--release-channel=${channel}"
  ];

  buildPhase = ''
    # Build the initial bootstrapper and tools
    NIX_RUSTFLAGS_OLD="$NIX_RUSTFLAGS"
    export NIX_RUSTFLAGS="$NIX_RUSTFLAGS -L${rustc.std}/lib"
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

    # Ensure we ignore linking against compiler libs
    touch "$out"/lib/.nix-ignore

    mkdir -p "$std"
    mv "$(find "$out"/lib/rustlib -name lib -type d)" "$std"/lib
  '';

  outputs = [
    "out"
    "std"
  ];

  disallowedReferences = [
    llvm_split.bin
    llvm_split.dev
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
