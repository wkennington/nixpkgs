{ stdenv
, buildLinux
, fetchFromGitHub
, fetchurl
, perl

, # Overrides to the kernel config.
  extraConfig ? ""

, # A list of patches to apply to the kernel.  Each element of this list
  # should be an attribute set {name, patch} where `name' is a
  # symbolic name and `patch' is the actual patch.  The patch may
  # optionally be compressed with gzip or bzip2.
  kernelPatches ? []

, ignoreConfigErrors ? false
, extraMeta ? {}
, channel
, ...
}:

let

  sources = {
    "4.7" = {
      version = "4.7.6";
      sha256 = "7b516520c3dc3a18b1ad30ca54603d9bb31e32ab51fa6b882a02b05e10d32dd2";
    };
    "4.8" = {
      version = "4.8";
      sha256 = "3e9150065f193d3d94bcf46a1fe9f033c7ef7122ab71d75a7fb5a2f0c9a7e11a";
    };
    "testing" = {
      version = "4.8-rc8";
      sha256 = "676b5e3e0529385a75baa650b2e2395a4b001821447869735baa83616942597f";
    };
    "bcache" =
      let
        date = "2016-10-01";
      in {
        version = "4.7.6";
        urls = [
          "https://github.com/wkennington/linux/releases/download/bcachefs-${version}-${date}/linux-bcachefs-${version}-${date}.tar.xz"
        ];
        sha256 = "17ac16c494c16117c927d10caab2aaaaae10424b95735e40374fa5ca773dd454";
        features.bcachefs = true;
      };
  };

  source = sources."${channel}";

  inherit (source)
    version;

  tarballUrls = [
    "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar"
    "mirror://kernel/linux/kernel/v4.x/testing/linux-${version}.tar"
  ];

  src = if source ? rev then
    fetchFromGitHub {
      inherit (source)
        owner
        repo
        rev
        sha256;
    }
  else
    fetchurl {
      urls = source.urls or (map (n: "${n}.xz") tarballUrls);
      hashOutput = false;
      inherit (source) sha256;
    };

  srcVerification = fetchurl {
    failEarly = true;
    pgpDecompress = true;
    pgpsigUrls = map (n: "${n}.sign") tarballUrls;
    pgpKeyFingerprints = [
      "647F 2865 4894 E3BD 4571  99BE 38DB BDC8 6092 693E"
      "ABAF 11C6 5A29 70B1 30AB  E3C4 79BE 3E43 0041 1886"
    ];
    inherit (src) urls outputHash outputHashAlgo;
  };

  lib = stdenv.lib;

  modDirVersion = let
    rcSplit = lib.splitString "-" version;
    vSplit = lib.splitString "." (lib.head rcSplit);
    vSplit' = if lib.length vSplit == 2 then vSplit ++ [ "0" ] else vSplit;
    rcSplit' = [ (lib.concatStringsSep "." vSplit') ] ++ lib.tail rcSplit;
  in lib.concatStringsSep "-" rcSplit';

  common = import ./common.nix { inherit stdenv; };

  kernelConfigFun = baseConfig:
    let
      configFromPatches =
        map ({extraConfig ? "", ...}: extraConfig) kernelPatches;
    in lib.concatStringsSep "\n" ([baseConfig] ++ configFromPatches);

  configfile = stdenv.mkDerivation {
    inherit ignoreConfigErrors;
    name = "linux-config-${version}";

    generateConfig = ./generate-config.pl;

    kernelConfig = kernelConfigFun config;

    nativeBuildInputs = [ perl ];

    platformName = "pc";
    kernelBaseConfig = "defconfig";
    kernelTarget = "bzImage";
    autoModules = true;
    arch = common.kernelArch;

    prePatch = kernel.prePatch + ''
      # Patch kconfig to print "###" after every question so that
      # generate-config.pl from the generic builder can answer them.
      sed -e '/fflush(stdout);/i\printf("###");' -i scripts/kconfig/conf.c
    '';

    inherit (kernel) src patches preUnpack;

    buildPhase = ''
      cd $buildRoot

      # Get a basic config file for later refinement with $generateConfig.
      make -C ../$sourceRoot O=$PWD $kernelBaseConfig ARCH=$arch

      # Create the config file.
      echo "generating kernel configuration..."
      echo "$kernelConfig" > kernel-config
      DEBUG=1 ARCH=$arch KERNEL_CONFIG=kernel-config AUTO_MODULES=$autoModules \
           SRC=../$sourceRoot perl -w $generateConfig
    '';

    installPhase = "mv .config $out";
  };

  kernel = buildLinux {
    inherit version modDirVersion src kernelPatches;

    configfile = configfile.nativeDrv or configfile;

    crossConfigfile = configfile.crossDrv or configfile;

    config = { CONFIG_MODULES = "y"; CONFIG_FW_LOADER = "m"; };

    crossConfig = { CONFIG_MODULES = "y"; CONFIG_FW_LOADER = "m"; };
  };

  passthru = {
    meta = kernel.meta // extraMeta;

    inherit srcVerification;

    features = source.features or { };

    passthru = kernel.passthru // (removeAttrs passthru [ "passthru" "meta" ]);
  };

  config = import ./common-config.nix
    { inherit stdenv version extraConfig; };

  nativeDrv = lib.addPassthru kernel.nativeDrv passthru;

  crossDrv = lib.addPassthru kernel.crossDrv passthru;
in if kernel ? crossDrv then nativeDrv // { inherit nativeDrv crossDrv; } else lib.addPassthru kernel passthru
