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

    builder = bootstrapFiles.busybox;

    args = [ "ash" "-e" ./unpack-bootstrap-tools.sh ];

    tarball = bootstrapFiles.bootstrapTools;

    outputs = [ "out" "glibc" ];

    system = hostSystem;
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
    initialPath = [ bootstrapTools ];
    extraBuildInputs = [ ];

    preHook = ''
      # We cant patch shebangs or we will retain references to the bootstrap
      export dontPatchShebangs=1
      # We can allow build dir impurities because we might have a weird compiler
      export buildDirCheck=
    '';

  };

  # TODO: Implement mapping for this
  bootstrapTarget = "x86_64-tritonboot-linux-gnu";
  finalTarget = "x86_64-pc-linux-gnu";

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

        cc_gcc = wrapCCNew {
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
      name = "stdenv-linux-boot-stage01";
      cc = stage0Pkgs.cc_gcc;

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage01Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv libc linux-headers linux-headers_4-14 python_tiny;

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
  stage02Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage02";
      cc = null;

      preHook = commonBootstrapOptions.preHook + ''
        export NIX_SYSTEM_HOST='${bootstrapTarget}'
      '';

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage02Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv;
        inherit (stage01Pkgs) gcc linux-headers bison;

        cc_gcc_early = stage0Pkgs.wrapCCNew {
          compiler = stage01Pkgs.gcc.bin;
          tools = [ stage01Pkgs.binutils.bin ];
          inputs = [
            stage01Pkgs.gcc.cc_headers
            stage01Pkgs.linux-headers
          ];
          target = bootstrapTarget;
        };

        glibc_headers = pkgs.glibc_headers.override {
          cc = stage02Pkgs.cc_gcc_early;
          python3 = stage01Pkgs.python_tiny;
        };

        cc_gcc_glibc_headers = stage0Pkgs.wrapCCNew {
          compiler = stage01Pkgs.gcc.bin;
          tools = [ stage01Pkgs.binutils.bin ];
          inputs = [
            stage01Pkgs.gcc.cc_headers
            stage02Pkgs.glibc_headers
            stage01Pkgs.linux-headers
          ];
          target = bootstrapTarget;
        };

        gcc_lib_glibc_static = pkgs.gcc_lib_glibc_static.override {
          cc = stage02Pkgs.cc_gcc_glibc_headers;
        };

        cc_gcc_glibc_nolibc = stage0Pkgs.wrapCCNew {
          compiler = stage01Pkgs.gcc.bin;
          tools = [ stage01Pkgs.binutils.bin ];
          inputs = [
            stage02Pkgs.gcc_lib_glibc_static
            stage01Pkgs.gcc.cc_headers
            stage01Pkgs.linux-headers
          ];
          target = bootstrapTarget;
        };

        glibc = pkgs.glibc.override {
          type = "bootstrap";
          cc = stage02Pkgs.cc_gcc_glibc_nolibc;
          python3 = stage01Pkgs.python_tiny;
        };

        cc_gcc_glibc_nolibgcc = stage0Pkgs.wrapCCNew {
          compiler = stage01Pkgs.gcc.bin;
          tools = [ stage01Pkgs.binutils.bin ];
          inputs = [
            stage02Pkgs.gcc_lib_glibc_static
            stage01Pkgs.gcc.cc_headers
            stage02Pkgs.glibc
            stage01Pkgs.linux-headers
          ];
          target = bootstrapTarget;
        };

        gcc_lib_glibc = pkgs.gcc_lib_glibc.override {
          cc = stage02Pkgs.cc_gcc_glibc_nolibgcc;
        };

        cc_gcc_glibc_early = stage0Pkgs.wrapCCNew {
          compiler = stage01Pkgs.gcc.bin;
          tools = [ stage01Pkgs.binutils.bin ];
          inputs = [
            stage02Pkgs.gcc_lib_glibc
            stage01Pkgs.gcc.cc_headers
            stage02Pkgs.glibc
            stage01Pkgs.linux-headers
          ];
          target = bootstrapTarget;
        };

        libstdcxx_glibc = pkgs.libstdcxx_glibc.override {
          cc = stage02Pkgs.cc_gcc_glibc_early;
          gcc_lib = stage02Pkgs.gcc_lib_glibc;
        };

        libunistring_glibc = pkgs.libunistring_glibc.override {
          cc = stage02Pkgs.cc_gcc_glibc_early;
        };

        libidn2_glibc = pkgs.libidn2_glibc.override {
          cc = stage02Pkgs.cc_gcc_glibc_early;
        };

        cc_gcc_glibc = stage0Pkgs.wrapCCNew {
          compiler = stage01Pkgs.gcc.bin;
          tools = [ stage01Pkgs.binutils.bin ];
          inputs = [
            stage02Pkgs.libstdcxx_glibc
            stage02Pkgs.gcc_lib_glibc
            stage01Pkgs.gcc.cc_headers
            stage02Pkgs.glibc.cc_reqs
            stage02Pkgs.glibc
            stage01Pkgs.linux-headers
          ];
          target = bootstrapTarget;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
      };
    });
  };

  # This stage is used to rebuild the rest of the toolchain targetting tritonboot
  stage03Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage03";
      cc = stage02Pkgs.cc_gcc_glibc;

      preHook = commonBootstrapOptions.preHook + ''
        export NIX_SYSTEM_BUILD='${bootstrapTarget}'
        export NIX_SYSTEM_HOST='${bootstrapTarget}'
      '';

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage03Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv;

        binutils = pkgs.binutils.override {
          type = "small";
          target = finalTarget;
        };

        gcc = pkgs.gcc.override {
          type = "small";
          libc = stage02Pkgs.libc;
        };

        zlib = pkgs.zlib.override {
          type = "small";
        };


        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
      };
    });
  };

  # Rebuild the c / c++ toolchain based on our new libc + libstdcxx.
  stage11Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage11";
      cc = stage03Pkgs.cc;

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage11Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (stage01Pkgs) linux-headers;
        inherit (pkgs) stdenv libmpc mpfr isl isl_0-21;

        gmp = pkgs.gmp.override {
          gnum4 = stage01Pkgs.gnum4;
          cxx = false;
        };

        binutils = pkgs.binutils.override {
          type = "small";
        };

        gcc = pkgs.gcc.override {
          type = "small";
          libc = stage02Pkgs.libc;
        };

        zlib = pkgs.zlib.override {
          type = "small";
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
      };
    });
  };

  # Rebuild the libc based on our second pass compiler and linker
  stage12Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage12";
      # Make sure we don't use the wrong compiler
      cc = null;

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage12Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (stage11Pkgs) binutils gcc;
        inherit (pkgs) stdenv cc libc;

        glibc = pkgs.glibc.override {
          type = "small";
          bison = stage01Pkgs.bison;
          python_tiny = stage01Pkgs.python_tiny;
          linux-headers = stage01Pkgs.linux-headers;
        };

        cc_gcc = lib.makeOverridable (import ../../build-support/cc-wrapper) {
          nativeTools = false;
          nativeLibc = false;
          libc = stage12Pkgs.libc;
          cc = stage11Pkgs.gcc;
          linux-headers = stage01Pkgs.linux-headers;
          libgcc = stage11Pkgs.gcc;
          binutils = stage11Pkgs.binutils;
          coreutils = bootstrapTools;
          name = "bootstrap-cc-wrapper-stage12";
          stdenv = pkgs.stdenv;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
      };
    });
  };

  # Build the rest of the required tooling for the final rebuild
  stage13Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // commonBootstrapOptions // {
      name = "stdenv-linux-boot-stage13";
      cc = stage12Pkgs.cc;

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage13Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv cc bash_small coreutils_small
          gawk_small gnupatch_small gnused_small gnutar_small pcre
          pkgconfig pkgconf pkgconf-wrapper python_tiny xz;

        bison = pkgs.bison.override {
          type = "small";
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

        gnum4 = pkgs.gnum4.override {
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

        cc_gcc = lib.makeOverridable (import ../../build-support/cc-wrapper) {
          nativeTools = false;
          nativeLibc = false;
          libc = stage12Pkgs.libc;
          cc = stage11Pkgs.gcc;
          linux-headers = stage01Pkgs.linux-headers;
          libgcc = stage11Pkgs.gcc;
          binutils = stage11Pkgs.binutils;
          coreutils = stage13Pkgs.coreutils_small;
          name = "bootstrap-cc-wrapper-stage13";
          stdenv = pkgs.stdenv;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
        brotli = null;
      };
    });
  };

  # This is the first set of packages built without external tooling
  # Start by getting a working glibc and headers
  stage21Pkgs = allPackages {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // {
      name = "stdenv-linux-boot-stage21";
      cc = null;
      shell = stage13Pkgs.bash_small + stage13Pkgs.bash_small.shellPath;
      initialPath = lib.attrValues ((import ../generic/common-path.nix) { pkgs = stage13Pkgs; });
      extraBuildInputs = [ ];

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage21Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (pkgs) stdenv cc libc linux-headers;

        linux-headers_4-14 = pkgs.linux-headers_4-14.override {
          stdenv = pkgs.stdenv.override {
            cc = stage13Pkgs.cc;
          };
        };

        glibc = pkgs.glibc.override {
          bison = stage13Pkgs.bison;
          python_tiny = stage13Pkgs.python_tiny;
          binutils = stage11Pkgs.binutils;
          gcc = stage11Pkgs.gcc;
        };

        cc_gcc = lib.makeOverridable (import ../../build-support/cc-wrapper) {
          nativeTools = false;
          nativeLibc = false;
          libc = stage21Pkgs.libc;
          cc = stage11Pkgs.gcc;
          linux-headers = stage21Pkgs.linux-headers;
          binutils = stage11Pkgs.binutils;
          coreutils = stage13Pkgs.coreutils_small;
          name = "cc-wrapper-stage21";
          stdenv = pkgs.stdenv;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
      };
    });
  };

  # This is the second package set using the final glibc and bootstrap tools.
  # This stage is used for building the final gcc
  stage22Pkgs = allPackages rec {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // {
      name = "stdenv-linux-boot-stage22";
      cc = stage21Pkgs.cc;
      shell = stage13Pkgs.bash_small + stage13Pkgs.bash_small.shellPath;
      initialPath = lib.attrValues ((import ../generic/common-path.nix) { pkgs = stage13Pkgs; });
      extraBuildInputs = [
        stage13Pkgs.patchelf
        stage13Pkgs.pkgconfig
      ];

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage22Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (stage21Pkgs) libc glibc linux-headers linux-headers_4-14;
        inherit (pkgs) stdenv cc isl isl_0-21 libmpc mpfr zlib;

        gcc = pkgs.gcc.override {
          binutils = stage11Pkgs.binutils;
        };

        gmp = pkgs.gmp.override {
          gnum4 = stage13Pkgs.gnum4;
          cxx = false;
        };

        cc_gcc = lib.makeOverridable (import ../../build-support/cc-wrapper) {
          nativeTools = false;
          nativeLibc = false;
          libc = stage21Pkgs.libc;
          cc = stage22Pkgs.gcc;
          linux-headers = stage21Pkgs.linux-headers;
          libgcc = stage22Pkgs.gcc;
          binutils = stage11Pkgs.binutils;
          coreutils = stage13Pkgs.coreutils_small;
          name = "cc-wrapper-stage22";
          stdenv = pkgs.stdenv;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
      };
    });
  };

  # This is the second package set using the final glibc, gcc and bootstrap tools.
  # This stage is used for building the final stdenv package set
  stage23Pkgs = allPackages rec {
    inherit targetSystem hostSystem config;
    stdenv = import ../generic { inherit lib; } (commonStdenvOptions // {
      name = "stdenv-linux-boot-stage23";
      cc = stage22Pkgs.cc;
      shell = stage13Pkgs.bash_small + stage13Pkgs.bash_small.shellPath;
      initialPath = lib.attrValues ((import ../generic/common-path.nix) { pkgs = stage13Pkgs; });
      extraBuildInputs = [
        stage13Pkgs.patchelf
        stage13Pkgs.pkgconfig
      ];

      overrides = pkgs: (lib.mapAttrs (n: _: throw "stage23Pkgs is missing package definition for `${n}`") pkgs) // {
        inherit lib;
        inherit (stage21Pkgs) libc glibc linux-headers;
        inherit (stage22Pkgs) gcc gmp isl isl_0-21 libmpc mpfr zlib;
        inherit (pkgs) stdenv cc coreutils_small gnugrep binutils pcre
          bash_small patchelf pkgconfig pkgconf pkgconf-wrapper pkgconf_unwrapped
          brotli brotli_1-0-7 bzip2 diffutils findutils gawk_small gnumake
          gnupatch_small gnused_small gnutar_small gzip xz xz_5-2-4 libidn2;

        cc_gcc = lib.makeOverridable (import ../../build-support/cc-wrapper) {
          nativeTools = false;
          nativeLibc = false;
          libc = stage21Pkgs.libc;
          cc = stage22Pkgs.gcc;
          linux-headers = stage21Pkgs.linux-headers;
          libgcc = stage22Pkgs.gcc;
          libidn2 = stage23Pkgs.libidn2;
          binutils = stage23Pkgs.binutils;
          coreutils = stage23Pkgs.coreutils_small;
          shell = stage23Pkgs.bash_small + stage23Pkgs.bash_small.shellPath;
          name = "cc-wrapper";
          stdenv = pkgs.stdenv;
        };

        # These are only needed to evaluate
        inherit (stage0Pkgs) fetchurl fetchTritonPatch;
      };
    });
  };

  # Construct the final stdenv.  It uses the Glibc and GCC, and adds
  # in a new binutils that doesn't depend on bootstrap-tools, as well
  # as dynamically linked versions of all other tools.
  stdenv = import ../generic { inherit lib; } (commonStdenvOptions // rec {
    name = "stdenv-final";

    # We want common applications in the path like gcc, mv, cp, tar, xz ...
    initialPath = lib.attrValues ((import ../generic/common-path.nix) { pkgs = stage23Pkgs; });

    # We need patchelf to be a buildInput since it has to install a setup-hook.
    # We need pkgconfig to be a buildInput as it has aclocal files needed to
    # generate PKG_CHECK_MODULES.
    extraBuildInputs = with stage23Pkgs; [ patchelf pkgconfig ];

    cc = stage23Pkgs.cc;

    shell = stage23Pkgs.bash_small + stage23Pkgs.bash_small.shellPath;

    extraArgs = rec {
      stdenvDeps = stage23Pkgs.stdenv.mkDerivation {
        name = "stdenv-deps";
        buildCommand = ''
          mkdir -p $out
        '' + lib.flip lib.concatMapStrings extraAttrs.bootstrappedPackages' (n: ''
          [ -h "$out/$(basename "${n}")" ] || ln -s "${n}" "$out"
        '');
      };
      stdenvDepTest = stage23Pkgs.stdenv.mkDerivation {
        name = "stdenv-dep-test";
        buildCommand = ''
          mkdir -p $out
          ln -s "${stdenvDeps}" $out
        '';
        allowedRequisites = extraAttrs.bootstrappedPackages' ++ [ stdenvDeps ];
      };
    };

    extraAttrs = rec {
      bootstrappedPackages' = lib.attrValues (overrides {}) ++ [ cc.cc cc ] ++ extraBuildInputs;
      bootstrappedPackages = [ stdenv ] ++ bootstrappedPackages';
    };

    overrides = pkgs: {
      inherit (stage21Pkgs) libc glibc linux-headers;
      inherit (stage22Pkgs) gcc gmp isl isl_0-21 libmpc mpfr zlib;
      inherit (stage23Pkgs) cc_gcc coreutils_small gnugrep binutils pcre
        bash_small patchelf pkgconfig pkgconf pkgconf_unwrapped
        brotli brotli_1-0-7 bzip2 diffutils findutils gawk_small gnumake
        gnupatch_small gnused_small gnutar_small gzip xz xz_5-2-4 libidn2;
    };
  });

  finalPkgs = allPackages {
    inherit targetSystem hostSystem config stdenv;
  };
in {
  inherit
    bootstrapTools stage0Pkgs
    stage01Pkgs stage02Pkgs stage03Pkgs
    stage11Pkgs stage12Pkgs stage13Pkgs
    stage21Pkgs stage22Pkgs stage23Pkgs
    stdenv;
}
