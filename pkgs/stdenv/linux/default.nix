# This file constructs the standard build environment for the
# Linux platform.  It's completely pure; that is, it relies on no
# external (non-Nix) tools, such as /usr/bin/gcc, and it contains a C
# compiler and linker that do not search in default locations,
# ensuring purity of components produced by it.

{ allPackages
, lib
, targetSystem
, hostSystem
, config
}:

# We haven't fleshed out cross compiling yet
assert targetSystem == hostSystem;

let

  bootstrapFiles = import ./bootstrap.nix {
    inherit lib hostSystem;
    inherit (stage0Pkgs) fetchurl;
  };

  commonStdenvOptions = {
    inherit targetSystem hostSystem config;
    preHook = ''
      export NIX_ENFORCE_PURITY="''${NIX_ENFORCE_PURITY-1}"
    '';
  };

  bootstrapTools = (derivation {
    name = "bootstrap-tools";

    builder = "/bin/sh";

    args = [ "-e" ./unpack-bootstrap-tools.sh ];

    busybox = bootstrapFiles.busybox;
    tarball = bootstrapFiles.bootstrapTools;

    outputs = [ "out" "glibc" ];

    system = hostSystem;

    __optionalChroot = true;
    allowSubstitutes = false;
    requiredSystemFeatures = [ "bootstrap" ];
  }) // {
    cc = "gcc";
    cxx = "g++";
    cpp = "cpp";
    optFlags = [ ];
    prefixMapFlag = "-fdebug-prefix-map";
    canStackClashProtect = false;
  };

  bootstrapShell = "${bootstrapTools}/bin/bash";

  commonBootstrapOptions = {
    shell = bootstrapShell;
    optionalChroot = true;
    allowSubstitutes = false;
    requiredSystemFeatures = [ "bootstrap" ];
    initialPath = [ bootstrapTools ];
    extraBuildInputs = [ ];

    preHook = ''
      # We cant patch shebangs or we will retain references to the bootstrap
      export dontPatchShebangs=1
      # We can allow build dir impurities because we might have a weird compiler
      export buildDirCheck=
      # We don't have package config early in the build process so don't use it
      export dontAbsoluteLibtool=1
      export dontAbsolutePkgconfig=1
    '';

  };

  bootstrapTarget = {
    "x86_64-linux" = "x86_64-tritonboot-linux-gnu";
    "powerpc64le-linux" = "powerpc64le-tritonboot-linux-gnu";
    "i686-linux" = "i686-tritonboot-linux-gnu";
  }."${targetSystem}";
  finalTarget = {
    "x86_64-linux" = "x86_64-triton-linux-gnu";
    "powerpc64le-linux" = "powerpc64le-triton-linux-gnu";
    "i686-linux" = "i686-triton-linux-gnu";
  }."${targetSystem}";

  # This is not a real set of packages or stdenv.
  # This is just enough for us to use stdenv.mkDerivation to build our
  # first cc-wrapper and fetchurlBoot.
  # This does not provide any actual packages.
  stage0Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage0";
      cc = null;

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage0Pkgs is missing package definition for `${n}`") pkgs) // rec {
        inherit lib;
        inherit (pkgs) stdenv fetchTritonPatch;

        fetchurl = pkgs.fetchurl.override {
          inherit (finalPkgs)
            callPackage;
        };

        wrapCCNew = pkgs.wrapCCNew.override {
          coreutils = bootstrapTools;
        };

        cc_gcc_glibc = wrapCCNew {
          compiler = bootstrapTools;
          inputs = [
            bootstrapTools.glibc
          ];
        };
      };
    });
  };

  # This stage produces the first bootstrapped compiler tooling
  stage01Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage0.1";
      cc = stage0Pkgs.cc_gcc_glibc;

      preHook = commonBootstrapOptions.preHook + ''
        export NIX_CC_HARDEN=
        export NIX_LD_HARDEN=
      '';

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage01Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv libc python_tiny;

        binutils = pkgs.binutils.override {
          type = "bootstrap";
          target = bootstrapTarget;
        };

        gcc = pkgs.gcc.override {
          type = "bootstrap";
          target = bootstrapTarget;
        };

        bison = pkgs.bison.override {
          type = "bootstrap";
        };

        gnum4 = pkgs.gnum4.override {
          type = "bootstrap";
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch wrapCCNew;
        inherit (pkgs) gmp libmpc mpfr zlib;
      };
    });
  };

  # This stage produces all of the target libraries needed for a working compiler
  stage1Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage1";
      cc = null;

      preHook = commonBootstrapOptions.preHook + ''
        export NIX_SYSTEM_BUILD="$('${bootstrapTools}'/bin/gcc -dumpmachine)"
        export NIX_SYSTEM_HOST='${bootstrapTarget}'
        export NIX_FOR_BUILD_CC_HARDEN=
        export NIX_FOR_BUILD_LD_HARDEN=
      '';

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage1Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv linux-headers linux-headers_4-14 gcc_lib_glibc_static gcc_lib_glibc
          gcc_cxx_glibc libidn2_glibc libunistring_glibc;

        hostcc = stage0Pkgs.cc_gcc_glibc.override {
          type = "build";
        };

        cc_gcc_early = pkgs.cc_gcc_early.override {
          target = bootstrapTarget;
        };

        glibc_headers_gcc = pkgs.glibc_headers_gcc.override {
          python3 = stage01Pkgs.python_tiny;
        };

        cc_gcc_glibc_headers = pkgs.cc_gcc_glibc_headers.override {
          target = bootstrapTarget;
        };

        cc_gcc_glibc_nolibc = pkgs.cc_gcc_glibc_nolibc.override {
          target = bootstrapTarget;
        };

        glibc_lib_gcc = pkgs.glibc_lib_gcc.override {
          type = "bootstrap";
          python3 = stage01Pkgs.python_tiny;
        };

        cc_gcc_glibc_nolibgcc = pkgs.cc_gcc_glibc_nolibgcc.override {
          target = bootstrapTarget;
        };

        cc_gcc_glibc_early = pkgs.cc_gcc_glibc_early.override {
          target = bootstrapTarget;
        };

        cc_gcc_glibc = pkgs.cc_gcc_glibc.override {
          target = bootstrapTarget;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch wrapCCNew;
        inherit (stage01Pkgs) binutils gcc bison;
        gcc_runtime_glibc = stage1Pkgs.gcc_cxx_glibc;
      };
    });
  };

  # This stage is used to rebuild the rest of the toolchain targetting tritonboot
  stage11Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage1.1";
      cc = stage1Pkgs.cc_gcc_glibc;

      preHook = commonBootstrapOptions.preHook + ''
        export NIX_SYSTEM_BUILD="$('${bootstrapTools}'/bin/gcc -dumpmachine)"
        export NIX_SYSTEM_HOST='${bootstrapTarget}'
      '';

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage11Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv isl isl_0-21 libmpc mpfr bash_small coreutils_small gawk_small pcre
          gnupatch_small gnused_small gnutar_small pkgconfig pkgconf pkgconf-wrapper xz;

        python_tiny = pkgs.python_tiny.override {
          python = stage01Pkgs.python_tiny;
        };

        zlib = pkgs.zlib.override {
          type = "small";
        };

        binutils = pkgs.binutils.override {
          type = "small";
          target = finalTarget;
        };

        gnum4 = pkgs.gnum4.override {
          type = "small";
        };

        gmp = pkgs.gmp.override {
          cxx = false;
        };

        gcc = pkgs.gcc.override {
          type = "small";
          target = finalTarget;
          fakeCanadian = true;
        };

        bzip2 = pkgs.bzip2.override {
          type = "small";
        };

        diffutils = pkgs.diffutils.override {
          type = "small";
        };

        findutils = pkgs.findutils.override {
          type = "small";
        };

        gnugrep = pkgs.gnugrep.override {
          type = "small";
        };

        gnumake = pkgs.gnumake.override {
          type = "small";
        };

        gzip = pkgs.gzip.override {
          type = "small";
        };

        patchelf = pkgs.patchelf.override {
          type = "small";
        };

        pkgconf_unwrapped = pkgs.pkgconf_unwrapped.override {
          type = "small";
        };

        xz_5-2-4 = pkgs.xz_5-2-4.override {
          type = "small";
        };

        bison = pkgs.bison.override {
          type = "small";
        };

        glibc_progs = pkgs.glibc_progs.override {
          type = "small";
          python3 = stage01Pkgs.python_tiny;
          glibc_lib = stage1Pkgs.glibc_lib_gcc;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
        inherit (stage1Pkgs) linux-headers;
        brotli = null;
      };
    });
  };

  # This is the first set of packages built without external tooling
  # This builds the initial compiler runtime libraries
  stage2Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // {
      name = "stdenv-linux-boot-stage2";
      cc = null;
      shell = stage11Pkgs.bash_small + stage11Pkgs.bash_small.shellPath;
      initialPath = lib.mapAttrsToList (_: v: v.bin or v) ((import ../generic/common-path.nix) { pkgs = stage11Pkgs; });
      extraBuildInputs = [
        stage11Pkgs.patchelf
        stage11Pkgs.pkgconfig
      ];

      preHook = commonStdenvOptions.preHook + ''
        export NIX_SYSTEM_BUILD='${bootstrapTarget}'
        export NIX_SYSTEM_HOST='${finalTarget}'
        export dontPatchShebangs=1
      '';

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage2Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv wrapCCNew linux-headers linux-headers_4-14 gcc_lib_glibc_static gcc_lib_glibc
          gcc_runtime_glibc libidn2_glibc libunistring_glibc;

        # This is hacky so that we don't depend on the external system
        # runtimes to execute the initial bootstrap compiler. We use our
        # new compiler with our old runtimes.
        hostcc = pkgs.cc_gcc_glibc.override {
          type = "build";
          target = bootstrapTarget;
          compiler = pkgs.cc_relinker {
            tool = stage11Pkgs.gcc.bin;
            target = bootstrapTarget;
          };
          tools = [
            (pkgs.cc_relinker {
              tool = stage11Pkgs.binutils.bin;
              target = bootstrapTarget;
            })
          ];
          inherit (stage1Pkgs.cc_gcc_glibc)
            inputs;
        };

        cc_gcc_early = pkgs.cc_gcc_early.override {
          target = finalTarget;
        };

        glibc_headers_gcc = pkgs.glibc_headers_gcc.override {
          python3 = stage11Pkgs.python_tiny;
        };

        cc_gcc_glibc_headers = pkgs.cc_gcc_glibc_headers.override {
          target = finalTarget;
        };

        cc_gcc_glibc_nolibc = pkgs.cc_gcc_glibc_nolibc.override {
          target = finalTarget;
        };

        glibc_lib_gcc = pkgs.glibc_lib_gcc.override {
          glibc_progs = stage11Pkgs.glibc_progs;
          python3 = stage11Pkgs.python_tiny;
        };

        cc_gcc_glibc_nolibgcc = pkgs.cc_gcc_glibc_nolibgcc.override {
          target = finalTarget;
        };

        cc_gcc_glibc_early = pkgs.cc_gcc_glibc_early.override {
          target = finalTarget;
        };

        cc_gcc_glibc = pkgs.cc_gcc_glibc.override {
          target = finalTarget;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
        inherit (stage11Pkgs) coreutils_small bison binutils gcc;
      };
    });
  };

  # This is the final set of packages built without external tooling
  stage21Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // {
      name = "stdenv-linux-boot-stage2.1";
      cc = stage2Pkgs.cc_gcc_glibc;
      shell = stage11Pkgs.bash_small + stage11Pkgs.bash_small.shellPath;
      initialPath = lib.mapAttrsToList (_: v: v.bin or v) ((import ../generic/common-path.nix) { pkgs = stage11Pkgs; });

      extraBuildInputs = [
        stage11Pkgs.patchelf
        stage11Pkgs.pkgconfig
      ];

      preHook = commonStdenvOptions.preHook + ''
        export NIX_SYSTEM_BUILD='${finalTarget}'
        export NIX_SYSTEM_HOST='${finalTarget}'
        export dontPatchShebangs=1
      '';

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage21Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (stage2Pkgs) glibc_headers_gcc gcc_runtime_glibc gcc_lib_glibc glibc_lib_gcc
          linux-headers_4-14 gcc_lib_glibc_static;
        inherit (pkgs) stdenv isl isl_0-21 libmpc mpfr bash_small coreutils_small gawk_small pcre
          gnupatch_small gnused_small gnutar_small pkgconfig pkgconf pkgconf-wrapper xz xz_5-2-4
          patchelf pkgconf_unwrapped brotli brotli_1-0-7 bzip2 diffutils findutils gnugrep gnumake
          gzip cc_gcc_glibc wrapCCNew gcc binutils zlib gmp linux-headers cc_gcc_early cc_gcc_glibc_early
          cc_gcc_glibc_headers cc_gcc_glibc_nolibc cc_gcc_glibc_nolibgcc;

        glibc_progs = pkgs.glibc_progs.override {
          python3 = stage11Pkgs.python_tiny;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
        inherit (stage11Pkgs) gnum4;
      };
    });
  };

  # Construct the final stdenv.  It uses the Glibc and GCC, and adds
  # in a new binutils that doesn't depend on bootstrap-tools, as well
  # as dynamically linked versions of all other tools.
  stdenv = import ../generic { inherit lib; } (commonStdenvOptions // rec {
    name = "stdenv-final";

    # We want common applications in the path like gcc, mv, cp, tar, xz ...
    initialPath = lib.mapAttrsToList (_: v: v.bin or v) ((import ../generic/common-path.nix) { pkgs = stage21Pkgs; });

    # We need patchelf to be a buildInput since it has to install a setup-hook.
    # We need pkgconfig to be a buildInput as it has aclocal files needed to
    # generate PKG_CHECK_MODULES.
    extraBuildInputs = with stage21Pkgs; [
      patchelf
      pkgconfig
    ];

    cc = finalPkgs.cc_gcc_glibc;

    shell = stage21Pkgs.bash_small + stage21Pkgs.bash_small.shellPath;

    preHook = commonStdenvOptions.preHook + ''
      export NIX_SYSTEM_BUILD='${finalTarget}'
      export NIX_SYSTEM_HOST='${finalTarget}'
      if [ -z "$LOCALE_PREDEFINED" ]; then
        export LC_ALL='C.UTF-8'
      fi
    '';

    extraArgs = rec {
      stdenvDeps = stage21Pkgs.stdenv.mkDerivation {
        name = "stdenv-deps";
        buildCommand = ''
          mkdir -p $out
        '' + lib.flip lib.concatMapStrings extraAttrs.bootstrappedPackages' (n: ''
          [ -h "$out/$(basename "${n}")" ] || ln -s "${n}" "$out"
        '');
        allowSubstitutes = false;
        preferLocalBuild = true;
      };
      stdenvDepTest = stage21Pkgs.stdenv.mkDerivation {
        name = "stdenv-dep-test";
        buildCommand = ''
          mkdir -p $out
          ln -s "${stdenvDeps}" $out
        '';
        allowedRequisites = extraAttrs.bootstrappedPackages' ++ [ stdenvDeps ];
        allowSubstitutes = false;
        preferLocalBuild = true;
      };
    };

    extraAttrs = rec {
      bootstrappedPackages' = lib.concatMap (n: n.all or [ ]) (lib.attrValues (overrides { cc_gcc_glibc = null; }));
      bootstrappedPackages = [ stdenv ] ++ bootstrappedPackages';
    };

    overrides = pkgs: rec {
      inherit (stage2Pkgs) glibc_headers_gcc gcc_runtime_glibc gcc_lib_glibc glibc_lib_gcc
        linux-headers_4-14 gcc_lib_glibc_static libidn2_glibc libunistring_glibc;
      inherit (stage21Pkgs) isl isl_0-21 libmpc mpfr bash_small coreutils_small gawk_small pcre
        gnupatch_small gnused_small gnutar_small pkgconfig pkgconf xz xz_5-2-4
        patchelf pkgconf_unwrapped brotli brotli_1-0-7 bzip2 diffutils findutils gnugrep gnumake
        gzip gcc binutils zlib gmp linux-headers;
      libidn2 = libidn2_glibc;
      libunistring = libunistring_glibc;
      cc = pkgs.cc_gcc_glibc;
      hostcc = cc;
      glibc_headers = glibc_headers_gcc;
      glibc_lib = glibc_lib_gcc;
      gcc_lib = gcc_lib_glibc;
      gcc_runtime = gcc_runtime_glibc;
      libc = glibc_lib;
    };
  });

  finalPkgs = allPackages {
    inherit targetSystem hostSystem config stdenv;
  };
in {
  inherit
    bootstrapTools
    stage0Pkgs stage01Pkgs
    stage1Pkgs stage11Pkgs
    stage2Pkgs stage21Pkgs
    stdenv;
}
