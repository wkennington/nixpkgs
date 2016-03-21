/* This file composes the Nix Packages collection.  That is, it
   imports the functions that build the various packages, and calls
   them with appropriate arguments.  The result is a set of all the
   packages in the Nix Packages collection for some particular
   platform. */


{ targetSystem
, hostSystem

# Allow a configuration attribute set to be passed in as an
# argument.  Otherwise, it's read from $NIXPKGS_CONFIG or
# ~/.nixpkgs/config.nix.
, config

# Allows the standard environment to be swapped out
# This is typically most useful for bootstrapping
, stdenv
} @ args:

let

  lib = import ../../lib;

  # The contents of the configuration file found at $NIXPKGS_CONFIG or
  # $HOME/.nixpkgs/config.nix.
  # for NIXOS (nixos-rebuild): use nixpkgs.config option
  config =
    if args.config != null then
      args.config
    else if builtins.getEnv "NIXPKGS_CONFIG" != "" then
      import (builtins.toPath (builtins.getEnv "NIXPKGS_CONFIG")) { inherit pkgs; }
    else
      let
        home = builtins.getEnv "HOME";
        homePath =
          if home != "" then
            builtins.toPath (home + "/.nixpkgs/config.nix")
          else
            null;
      in
        if homePath != null && builtins.pathExists homePath then
          import homePath { inherit pkgs; }
        else
          { };

  # Helper functions that are exported through `pkgs'.
  helperFunctions =
    stdenvAdapters //
    (import ../build-support/trivial-builders.nix { inherit lib; inherit (pkgs) stdenv; inherit (pkgs.xorg) lndir; });

  stdenvAdapters =
    import ../stdenv/adapters.nix pkgs;


  # Allow packages to be overriden globally via the `packageOverrides'
  # configuration option, which must be a function that takes `pkgs'
  # as an argument and returns a set of new or overriden packages.
  # The `packageOverrides' function is called with the *original*
  # (un-overriden) set of packages, allowing packageOverrides
  # attributes to refer to the original attributes (e.g. "foo =
  # ... pkgs.foo ...").
  pkgs = applyGlobalOverrides (config.packageOverrides or (pkgs: {}));

  mkOverrides = pkgsOrig: overrides: overrides //
        (lib.optionalAttrs (pkgsOrig.stdenv ? overrides) (pkgsOrig.stdenv.overrides pkgsOrig));

  # Return the complete set of packages, after applying the overrides
  # returned by the `overrider' function (see above).  Warning: this
  # function is very expensive!
  applyGlobalOverrides = overrider:
    let
      # Call the overrider function.  We don't want stdenv overrides
      # in the case of cross-building, or otherwise the basic
      # overrided packages will not be built with the crossStdenv
      # adapter.
      overrides = mkOverrides pkgsOrig (overrider pkgsOrig);

      # The un-overriden packages, passed to `overrider'.
      pkgsOrig = pkgsFun pkgs {};

      # The overriden, final packages.
      pkgs = pkgsFun pkgs overrides;
    in pkgs;


  # The package compositions.  Yes, this isn't properly indented.
  pkgsFun = pkgs: overrides:
    with helperFunctions;
    let defaultScope = pkgs; self = self_ // overrides;
    self_ =
      let
        inherit (self_)
          callPackage
          callPackages
          callPackageAlias
          recurseIntoAttrs
          wrapCCWith
          wrapCC;
        inherit (lib)
          hiPrio
          hiPrioSet
          lowPrio
          lowPrioSet;
      in
     helperFunctions // {

  # Make some arguments passed to all-packages.nix available
  targetSystem = args.targetSystem;
  hostSystem = args.hostSystem;

  # Allow callPackage to fill in the pkgs argument
  inherit pkgs;


  # We use `callPackage' to be able to omit function arguments that
  # can be obtained from `pkgs' or `pkgs.xorg' (i.e. `defaultScope').
  # Use `newScope' for sets of packages in `pkgs' (see e.g. `gnome'
  # below).
  callPackage = self_.newScope {};

  callPackages = lib.callPackagesWith defaultScope;

  newScope = extra: lib.callPackageWith (defaultScope // extra);

  callPackageAlias = package: newAttrs: pkgs."${package}".override newAttrs;

  # Easily override this package set.
  # Warning: this function is very expensive and must not be used
  # from within the nixpkgs repository.
  #
  # Example:
  #  pkgs.overridePackages (self: super: {
  #    foo = super.foo.override { ... };
  #  }
  #
  # The result is `pkgs' where all the derivations depending on `foo'
  # will use the new version.
  overridePackages = f:
    let
      newpkgs = pkgsFun newpkgs overrides;
      overrides = mkOverrides pkgs (f newpkgs pkgs);
    in newpkgs;

  # Override system. This is useful to build i686 packages on x86_64-linux.
  forceSystem = { targetSystem, hostSystem }: (import ./all-packages.nix) {
    inherit targetSystem hostSystem config stdenv;
  };

  # For convenience, allow callers to get the path to Nixpkgs.
  path = ../..;

  ### Helper functions.
  inherit lib config stdenvAdapters;

  # Applying this to an attribute set will cause nix-env to look
  # inside the set for derivations.
  recurseIntoAttrs = attrs: attrs // { recurseForDerivations = true; };

  builderDefs = lib.composedArgsAndFun (callPackage ../build-support/builder-defs/builder-defs.nix) {};

  builderDefsPackage = builderDefs.builderDefsPackage builderDefs;

  stringsWithDeps = lib.stringsWithDeps;


  ### Nixpkgs maintainer tools

  nix-generate-from-cpan = callPackage ../../maintainers/scripts/nix-generate-from-cpan.nix { };

  nixpkgs-lint = callPackage ../../maintainers/scripts/nixpkgs-lint.nix { };


  ### STANDARD ENVIRONMENT

  stdenv =
    if args.stdenv != null then
      args.stdenv
    else
      import ../stdenv {
        allPackages = args': import ./all-packages.nix (args // args');
        inherit lib targetSystem hostSystem config;
      };

  ### BUILD SUPPORT

  attrSetToDir = arg: callPackage ../build-support/upstream-updater/attrset-to-dir.nix {
    theAttrSet = arg;
  };

  autoreconfHook = makeSetupHook
    { substitutions = { inherit (pkgs) autoconf automake gettext libtool; }; }
    ../build-support/setup-hooks/autoreconf.sh;

  ensureNewerSourcesHook = { year }: makeSetupHook {}
    (writeScript "ensure-newer-sources-hook.sh" ''
      postUnpackHooks+=(_ensureNewerSources)
      _ensureNewerSources() {
        '${pkgs.findutils}/bin/find' "$sourceRoot" \
          '!' -newermt '${year}-01-01' -exec touch -d '${year}-01-02' '{}' '+'
      }
    '');

  buildEnv = callPackage ../build-support/buildenv { }; # not actually a package

  buildFHSEnv = callPackage ../build-support/build-fhs-chrootenv/env.nix { };

  chrootFHSEnv = callPackage ../build-support/build-fhs-chrootenv { };
  userFHSEnv = callPackage ../build-support/build-fhs-userenv {
   ruby = ruby_2_1_3;
  };

  buildFHSChrootEnv = args: chrootFHSEnv {
    env = buildFHSEnv (removeAttrs args [ "extraInstallCommands" ]);
    extraInstallCommands = args.extraInstallCommands or "";
  };

  buildFHSUserEnv = args: userFHSEnv {
    env = buildFHSEnv (removeAttrs args [ "runScript" "extraBindMounts" "extraInstallCommands" "meta" ]);
    runScript = args.runScript or "bash";
    extraBindMounts = args.extraBindMounts or [];
    extraInstallCommands = args.extraInstallCommands or "";
    importMeta = args.meta or {};
  };

  buildMaven = callPackage ../build-support/build-maven.nix {};

  cmark = callPackage ../development/libraries/cmark { };

  dockerTools = callPackage ../build-support/docker { };

  dotnetenv = callPackage ../build-support/dotnetenv {
    dotnetfx = dotnetfx40;
  };

  dotnetbuildhelpers = callPackage ../build-support/dotnetbuildhelpers {
    inherit helperFunctions;
  };

  vsenv = callPackage ../build-support/vsenv {
    vs = vs90wrapper;
  };

  fetchbower = callPackage ../build-support/fetchbower {
    inherit (nodePackages) fetch-bower;
  };

  fetchbzr = callPackage ../build-support/fetchbzr { };

  fetchcvs = callPackage ../build-support/fetchcvs { };

  fetchdarcs = callPackage ../build-support/fetchdarcs { };

  fetchgit = callPackage ../build-support/fetchgit { };

  fetchgitPrivate = callPackage ../build-support/fetchgit/private.nix { };

  fetchgitrevision = import ../build-support/fetchgitrevision runCommand git;

  fetchgitLocal = callPackage ../build-support/fetchgitlocal { };

  packer = callPackage ../development/tools/packer { };

  fetchpatch = callPackage ../build-support/fetchpatch { };

  fetchsvn = callPackage ../build-support/fetchsvn {
    sshSupport = true;
  };

  fetchsvnrevision = import ../build-support/fetchsvnrevision runCommand subversion;

  fetchsvnssh = callPackage ../build-support/fetchsvnssh {
    sshSupport = true;
  };

  fetchhg = callPackage ../build-support/fetchhg { };

  # `fetchurl' downloads a file from the network.
  fetchurl = callPackage ../build-support/fetchurl { };

  fetchTritonPatch = { rev, file, sha256 }: pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/triton/triton-patches/${rev}/${file}";
    inherit sha256;
  };

  fetchzip = callPackage ../build-support/fetchzip { };

  fetchFromGitHub = { owner, repo, rev, sha256, name ? "${repo}-${rev}-src" }: pkgs.fetchzip {
    inherit name sha256;
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    meta.homepage = "https://github.com/${owner}/${repo}/";
  } // { inherit rev; };

  fetchFromBitbucket = { owner, repo, rev, sha256, name ? "${repo}-${rev}-src" }: pkgs.fetchzip {
    inherit name sha256;
    url = "https://bitbucket.org/${owner}/${repo}/get/${rev}.tar.gz";
    meta.homepage = "https://bitbucket.org/${owner}/${repo}/";
    extraPostFetch = ''rm -f "$out"/.hg_archival.txt''; # impure file; see #12002
  };

  # cgit example, snapshot support is optional in cgit
  fetchFromSavannah = { repo, rev, sha256, name ? "${repo}-${rev}-src" }: pkgs.fetchzip {
    inherit name sha256;
    url = "http://git.savannah.gnu.org/cgit/${repo}.git/snapshot/${repo}-${rev}.tar.gz";
    meta.homepage = "http://git.savannah.gnu.org/cgit/${repo}.git/";
  };

  # gitlab example
  fetchFromGitLab = { owner, repo, rev, sha256, name ? "${repo}-${rev}-src" }: pkgs.fetchzip {
    inherit name sha256;
    url = "https://gitlab.com/${owner}/${repo}/repository/archive.tar.gz?ref=${rev}";
    meta.homepage = "https://gitlab.com/${owner}/${repo}/";
  };

  # gitweb example, snapshot support is optional in gitweb
  fetchFromRepoOrCz = { repo, rev, sha256, name ? "${repo}-${rev}-src" }: pkgs.fetchzip {
    inherit name sha256;
    url = "http://repo.or.cz/${repo}.git/snapshot/${rev}.tar.gz";
    meta.homepage = "http://repo.or.cz/${repo}.git/";
  };

  fetchFromSourceforge = { repo, rev, sha256, name ? "${repo}-${rev}-src" }: pkgs.fetchzip {
    inherit name sha256;
    url = "http://sourceforge.net/code-snapshots/git/"
      + "${lib.substring 0 1 repo}/"
      + "${lib.substring 0 2 repo}/"
      + "${repo}/code.git/"
      + "${repo}-code-${rev}.zip";
    meta.homepage = "http://sourceforge.net/p/${repo}/code";
    preFetch = ''
      echo "Telling sourceforge to generate code tarball..."
      $curl --data "path=&" "http://sourceforge.net/p/${repo}/code/ci/${rev}/tarball" >/dev/null
      local found
      found=0
      for i in {1..30}; do
        echo "Checking tarball generation status..." >&2
        status="$($curl "http://sourceforge.net/p/${repo}/code/ci/${rev}/tarball_status?path=")"
        echo "$status"
        if echo "$status" | grep -q '{"status": "complete"}'; then
          found=1
          break
        fi
        if ! echo "$status" | grep -q '{"status": "\(ready\|busy\)"}'; then
          break
        fi
        sleep 1
      done
      if [ "$found" -ne "1" ]; then
        echo "Sourceforge failed to generate tarball"
        exit 1
      fi
    '';
  };

  fetchNuGet = callPackage ../build-support/fetchnuget { };
  buildDotnetPackage = callPackage ../build-support/build-dotnet-package { };

  resolveMirrorURLs = {url}: pkgs.fetchurl {
    showURLs = true;
    inherit url;
  };

  libredirect = callPackage ../build-support/libredirect { };

  makeDesktopItem = callPackage ../build-support/make-desktopitem { };

  makeAutostartItem = callPackage ../build-support/make-startupitem { };

  makeInitrd = { contents, compressor ? "gzip -9n", prepend ? [ ] }:
    callPackage ../build-support/kernel/make-initrd.nix {
      inherit contents compressor prepend;
    };

  makeWrapper = makeSetupHook { } ../build-support/setup-hooks/make-wrapper.sh;

  makeModulesClosure = { kernel, rootModules, allowMissing ? false }:
    callPackage ../build-support/kernel/modules-closure.nix {
      inherit kernel rootModules allowMissing;
    };

  pathsFromGraph = ../build-support/kernel/paths-from-graph.pl;

  srcOnly = args: callPackage ../build-support/src-only args;

  substituteAll = callPackage ../build-support/substitute/substitute-all.nix { };

  substituteAllFiles = callPackage ../build-support/substitute-files/substitute-all-files.nix { };

  replaceDependency = callPackage ../build-support/replace-dependency.nix { };

  nukeReferences = callPackage ../build-support/nuke-references/default.nix { };

  vmTools = callPackage ../build-support/vm/default.nix { };

  releaseTools = callPackage ../build-support/release/default.nix { };

  composableDerivation = callPackage ../../lib/composable-derivation.nix { };

  platforms = import ./platforms.nix;

  setJavaClassPath = makeSetupHook { } ../build-support/setup-hooks/set-java-classpath.sh;

  keepBuildTree = makeSetupHook { } ../build-support/setup-hooks/keep-build-tree.sh;

  enableGCOVInstrumentation = makeSetupHook { } ../build-support/setup-hooks/enable-coverage-instrumentation.sh;

  makeGCOVReport = makeSetupHook
    { deps = [ pkgs.lcov pkgs.enableGCOVInstrumentation ]; }
    ../build-support/setup-hooks/make-coverage-analysis-report.sh;

  # intended to be used like nix-build -E 'with <nixpkgs> {}; enableDebugging fooPackage'
  enableDebugging = pkg: pkg.override { stdenv = stdenvAdapters.keepDebugInfo pkgs.stdenv; };

  findXMLCatalogs = makeSetupHook { } ../build-support/setup-hooks/find-xml-catalogs.sh;

  wrapGAppsHook = makeSetupHook {
    deps = [ makeWrapper ];
  } ../build-support/setup-hooks/wrap-gapps-hook.sh;

  separateDebugInfo = makeSetupHook { } ../build-support/setup-hooks/separate-debug-info.sh;

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
############################# BEGIN ALL BUILDERS ###############################
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################


wrapCCWith = ccWrapper: libc: extraBuildCommands: baseCC: ccWrapper {
  nativeTools = pkgs.stdenv.cc.nativeTools or false;
  nativeLibc = pkgs.stdenv.cc.nativeLibc or false;
  nativePrefix = pkgs.stdenv.cc.nativePrefix or "";
  cc = baseCC;
  isGNU = baseCC.isGNU or false;
  isClang = baseCC.isClang or false;
  inherit libc extraBuildCommands;
};

wrapCC = wrapCCWith (callPackage ../build-support/cc-wrapper) pkgs.stdenv.cc.libc "";

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
############################## END ALL BUILDERS ################################
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
############################### BEGIN ALL PKGS #################################
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################

accountsservice = callPackage ../all-pkgs/accountsservice { };

acl = callPackage ../all-pkgs/acl { };

acpid = callPackage ../all-pkgs/acpid { };

adns = callPackage ../all-pkgs/adns { };

adwaita-icon-theme = callPackage ../all-pkgs/adwaita-icon-theme { };

amrnb = callPackage ../all-pkgs/amrnb { };

amrwb = callPackage ../all-pkgs/amrwb { };

appstream-glib = callPackage ../all-pkgs/appstream-glib { };

apr = callPackage ../all-pkgs/apr { };

apr-util = callPackage ../all-pkgs/apr-util { };

ardour =  callPackage ../all-pkgs/ardour {
  inherit (gnome) libgnomecanvas libgnomecanvasmm;
};

aria2 = callPackage ../all-pkgs/aria2 { };
aria = aria2;

argyllcms = callPackage ../all-pkgs/argyllcms { };

asciidoc = callPackage ../all-pkgs/asciidoc { };

atk = callPackage ../all-pkgs/atk { };

atkmm = callPackage ../all-pkgs/atkmm { };

attr = callPackage ../all-pkgs/attr { };

at-spi2-atk = callPackage ../all-pkgs/at-spi2-atk { };

at-spi2-core = callPackage ../all-pkgs/at-spi2-core { };

atom = callPackage ../all-pkgs/atom { };

audit_full = callPackage ../all-pkgs/audit { };

audit_lib = callPackageAlias "audit_full" {
  prefix = "lib";
};

autoconf = callPackage ../all-pkgs/autoconf { };

autogen = callPackage ../all-pkgs/autogen { };

automake = callPackage ../all-pkgs/automake { };

avahi = callPackage ../all-pkgs/avahi { };

bazaar = callPackage ../all-pkgs/bazaar { };

bash = callPackage ../all-pkgs/bash { };

bashCompletion = callPackage ../all-pkgs/bash-completion { };

bc = callPackage ../all-pkgs/bc { };

beets = callPackage ../all-pkgs/beets { };

bison = callPackage ../all-pkgs/bison { };

bluez = callPackage ../all-pkgs/bluez { };

boost155 = callPackage ../all-pkgs/boost/1.55.nix { };
boost160 = callPackage ../all-pkgs/boost/1.60.nix { };
boost = callPackageAlias "boost160" { };

bs1770gain = callPackage ../all-pkgs/bs1770gain { };

btrfs-progs = callPackage ../all-pkgs/btrfs-progs { };

btsync = callPackage ../all-pkgs/btsync { };

bzip2 = callPackage ../all-pkgs/bzip2 { };

bzrtools = callPackage ../all-pkgs/bzrtools { };

c-ares = callPackage ../all-pkgs/c-ares { };

cairo = callPackage ../all-pkgs/cairo { };

cairomm = callPackage ../all-pkgs/cairomm { };

caribou = callPackage ../all-pkgs/caribou { };

ccid = callPackage ../all-pkgs/ccid { };

cdparanoia = callPackage ../all-pkgs/cdparanoia { };

# Only ever add ceph LTS releases
# The default channel should be the latest LTS
# Dev should always point to the latest versioned release
ceph_lib = pkgs.ceph;
ceph = hiPrio (callPackage ../all-pkgs/ceph { });
ceph_dev = callPackage ../all-pkgs/ceph {
  channel = "dev";
};
ceph_git = callPackage ../all-pkgs/ceph {
  channel = "git";
};

check = callPackage ../all-pkgs/check { };

chromaprint = callPackage ../all-pkgs/chromaprint { };

chromium = callPackage ../all-pkgs/chromium {
  channel = "stable";
};
chromium_beta = lowPrio (chromium.override {
  channel = "beta";
});
chromium_dev = lowPrio (chromium.override {
  channel = "dev";
});

clutter = callPackage ../all-pkgs/clutter { };

clutter-gst_2 = callPackage ../all-pkgs/clutter-gst/2.x.nix { };
clutter-gst_3 = callPackage ../all-pkgs/clutter-gst/3.x.nix { };
clutter-gst = clutter-gst_3;

clutter-gtk = callPackage ../all-pkgs/clutter-gtk { };

cmake = callPackage ../all-pkgs/cmake { };

cogl = callPackage ../all-pkgs/cogl { };

consul = pkgs.goPackages.consul.bin // { outputs = [ "bin" ]; };

consul-ui = callPackage ../all-pkgs/consul-ui { };

consul-template = pkgs.goPackages.consul-template.bin // { outputs = [ "bin" ]; };

colord = callPackage ../all-pkgs/colord { };

coreutils = callPackage ../all-pkgs/coreutils { };

cpio = callPackage ../all-pkgs/cpio { };

cracklib = callPackage ../all-pkgs/cracklib { };

cryptodevHeaders = callPackage ../all-pkgs/cryptodev {
  onlyHeaders = true;
  kernel = null;
};

cryptopp = callPackage ../all-pkgs/crypto++ { };

cryptsetup = callPackage ../all-pkgs/cryptsetup { };

curl = callPackage ../all-pkgs/curl {
  suffix = "";
};

curl_full = callPackageAlias "curl" {
  suffix = "full";
};

cyrus-sasl = callPackage ../all-pkgs/cyrus-sasl { };

dash = callPackage ../all-pkgs/dash { };

db = callPackage ../all-pkgs/db { };
db_5 = callPackageAlias "db" {
  channel = "5";
};
db_6 = callPackageAlias "db" {
  channel = "6";
};

dbus = callPackage ../all-pkgs/dbus { };

dbus-glib = callPackage ../all-pkgs/dbus-glib { };

dconf = callPackage ../all-pkgs/dconf { };

dconf-editor = callPackage ../all-pkgs/dconf-editor { };

ddrescue = callPackage ../all-pkgs/ddrescue { };

devil-nox = devil.override {
  xorg = null;
  mesa = null;
};
devil = callPackage ../all-pkgs/devil { };

diffutils = callPackage ../all-pkgs/diffutils { };

dnsmasq = callPackage ../all-pkgs/dnsmasq { };

dos2unix = callPackage ../all-pkgs/dos2unix { };

dropbox = callPackage ../all-pkgs/dropbox { };

duplicity = callPackage ../all-pkgs/duplicity { };

e2fsprogs = callPackage ../all-pkgs/e2fsprogs { };

edac-utils = callPackage ../all-pkgs/edac-utils { };

efibootmgr = callPackage ../all-pkgs/efibootmgr { };

elfutils = callPackage ../all-pkgs/elfutils { };

eog = callPackage ../all-pkgs/eog { };

evince = callPackage ../all-pkgs/evince { };

evolution = callPackage ../all-pkgs/evolution { };

evolution-data-server = callPackage ../all-pkgs/evolution-data-server { };

expat = callPackage ../all-pkgs/expat { };

faac = callPackage ../all-pkgs/faac { };

ffmpeg_0 = callPackage ../all-pkgs/ffmpeg/0.x.nix { };
ffmpeg_1 = callPackage ../all-pkgs/ffmpeg/1.x.nix { };
ffmpeg_2_2 = callPackage ../all-pkgs/ffmpeg/2.2.nix { };
ffmpeg_2 = callPackage ../all-pkgs/ffmpeg/2.x.nix { };
ffmpeg_3 = callPackage ../all-pkgs/ffmpeg/3.x.nix { };
ffmpeg = callPackageAlias "ffmpeg_3" { };
ffmpeg-full_HEAD = callPackage ../all-pkgs/ffmpeg-full {
  useHEAD = true;
};
ffmpeg-full = callPackage ../all-pkgs/ffmpeg-full { };

fftw_double = callPackage ../all-pkgs/fftw {
  precision = "double";
};

fftw_single = callPackageAlias "fftw_double" {
  precision = "single";
};

fftw_long-double = callPackageAlias "fftw_double" {
  precision = "long-double";
};

file-roller = callPackage ../all-pkgs/file-roller { };

filezilla = callPackage ../all-pkgs/filezilla { };

findutils = callPackage ../all-pkgs/findutils { };

firefox = pkgs.firefox_wrapper pkgs.firefox-unwrapped { };
firefox-esr = pkgs.firefox_wrapper pkgs.firefox-esr-unwrapped { };
firefox-unwrapped = callPackage ../all-pkgs/firefox { };
firefox-esr-unwrapped = callPackage ../all-pkgs/firefox {
  channel = "esr";
};
firefox_wrapper = callPackage ../all-pkgs/firefox/wrapper.nix { };

firefox-bin = callPackage ../applications/networking/browsers/firefox-bin { };

fish = callPackage ../all-pkgs/fish { };

flac = callPackage ../all-pkgs/flac { };

flex = callPackage ../all-pkgs/flex { };

gawk = callPackage ../all-pkgs/gawk { };

gcab = callPackage ../all-pkgs/gcab { };

gconf = callPackage ../all-pkgs/gconf { };

gcr = callPackage ../all-pkgs/gcr { };

gdk-pixbuf = callPackage ../all-pkgs/gdk-pixbuf { };
gdk-pixbuf-core = callPackage ../all-pkgs/gdk-pixbuf-core { };

gdm = callPackage ../all-pkgs/gdm { };

gegl = callPackage ../all-pkgs/gegl { };

geocode-glib = callPackage ../all-pkgs/geocode-glib { };

geoip = callPackage ../all-pkgs/geoip { };

getopt = callPackage ../all-pkgs/getopt { };

gettext = callPackage ../all-pkgs/gettext { };

gexiv2 = callPackage ../all-pkgs/gexiv2 { };

git = callPackage ../all-pkgs/git { };

gjs = callPackage ../all-pkgs/gjs { };

gksu = callPackage ../all-pkgs/gksu { };

glib = callPackage ../all-pkgs/glib { };
# checked version separate to break recursion
glib_tested = glib.override {
  doCheck = true;
  libffi = libffi.override {
    doCheck = true;
  };
};

glibmm = callPackage ../all-pkgs/glibmm { };

glib-networking = callPackage ../all-pkgs/glib-networking { };
glib_networking = callPackageAlias "glib-networking" { }; # Deprecated alias

gmp = callPackage ../all-pkgs/gmp { };

gnome-backgrounds = callPackage ../all-pkgs/gnome-backgrounds { };

gnome-bluetooth = callPackage ../all-pkgs/gnome-bluetooth { };

gnome-calculator = callPackage ../all-pkgs/gnome-calculator { };

gnome-clocks = callPackage ../all-pkgs/gnome-clocks { };

gnome-common = callPackage ../all-pkgs/gnome-common { };

gnome-control-center = callPackage ../all-pkgs/gnome-control-center { };

gnome-desktop = callPackage ../all-pkgs/gnome-desktop { };

gnome-documents = callPackage ../all-pkgs/gnome-documents { };

gnome-keyring = callPackage ../all-pkgs/gnome-keyring { };

gnome-menus = callPackage ../all-pkgs/gnome-menus { };

gnome-mpv = callPackage ../all-pkgs/gnome-mpv { };

gnome-online-accounts = callPackage ../all-pkgs/gnome-online-accounts { };

gnome-online-miners = callPackage ../all-pkgs/gnome-online-miners { };

gnome-screenshot = callPackage ../all-pkgs/gnome-screenshot { };

gnome-session = callPackage ../all-pkgs/gnome-session { };

gnome-settings-daemon = callPackage ../all-pkgs/gnome-settings-daemon { };

gnome-shell = callPackage ../all-pkgs/gnome-shell { };

gnome-shell-extensions = callPackage ../all-pkgs/gnome-shell-extensions { };

gnome-terminal = callPackage ../all-pkgs/gnome-terminal { };

gnome-themes-standard = callPackage ../all-pkgs/gnome-themes-standard { };

gnome-user-share = callPackage ../all-pkgs/gnome-user-share { };

gnome-wrapper = makeSetupHook {
  deps = [ makeWrapper ];
} ../build-support/setup-hooks/gnome-wrapper.sh;

gnonlin_0 = callPackage ../all-pkgs/gnonlin/0.x.nix { };
gnonlin_1 = callPackage ../all-pkgs/gnonlin/1.x.nix { };
gnonlin = gnonlin_1;

gnugrep = callPackage ../all-pkgs/gnugrep { };

gnum4 = callPackage ../all-pkgs/gnum4 { };

gnumake = callPackage ../all-pkgs/gnumake { };

gnupatch = callPackage ../all-pkgs/gnupatch { };

gnupg_2_0 = callPackageAlias "gnupg" {
  channel = "2.0";
};

gnupg_2_1 = callPackageAlias "gnupg" {
  channel = "2.1";
};

gnupg = callPackage ../all-pkgs/gnupg { };

gnused = callPackage ../all-pkgs/gnused { };

gnutar = callPackage ../all-pkgs/gnutar { };

gnutls = callPackage ../all-pkgs/gnutls { };

go = callPackage ../all-pkgs/go { };

go_1_6 = callPackageAlias "go" {
  channel = "1.6";
};

gobject-introspection = callPackage ../all-pkgs/gobject-introspection { };
gobjectIntrospection = callPackageAlias "gobject-introspection" { }; # Deprecated alias

google-gflags = callPackage ../all-pkgs/google-gflags { };

gperf = callPackage ../all-pkgs/gperf { };

gperftools = callPackage ../all-pkgs/gperftools { };

gpm = callPackage ../all-pkgs/gpm+ncurses { };

granite = callPackage ../all-pkgs/granite { };

graphviz = callPackage ../all-pkgs/graphviz { };

grilo = callPackage ../all-pkgs/grilo { };

grilo-plugins = callPackage ../all-pkgs/grilo-plugins { };

gsettings-desktop-schemas = callPackage ../all-pkgs/gsettings-desktop-schemas { };

gsm = callPackage ../all-pkgs/gsm { };

gsound = callPackage ../all-pkgs/gsound { };

gssdp = callPackage ../all-pkgs/gssdp { };

gst-ffmpeg = callPackage ../all-pkgs/gst-ffmpeg { };

gst-libav = callPackage ../all-pkgs/gst-libav { };

gst-plugins-bad_0 = callPackage ../all-pkgs/gst-plugins-bad/0.x.nix { };
gst-plugins-bad_1 = callPackage ../all-pkgs/gst-plugins-bad/1.x.nix { };
gst-plugins-bad = callPackageAlias "gst-plugins-bad_1" { };

gst-plugins-base_0 = callPackage ../all-pkgs/gst-plugins-base/0.x.nix { };
gst-plugins-base_1 = callPackage ../all-pkgs/gst-plugins-base/1.x.nix { };
gst-plugins-base = callPackageAlias "gst-plugins-base_1" { };

gst-plugins-good_0 = callPackage ../all-pkgs/gst-plugins-good/0.x.nix { };
gst-plugins-good_1 = callPackage ../all-pkgs/gst-plugins-good/1.x.nix { };
gst-plugins-good = callPackageAlias "gst-plugins-good_1" { };

gst-plugins-ugly_0 = callPackage ../all-pkgs/gst-plugins-ugly/0.x.nix { };
gst-plugins-ugly_1 = callPackage ../all-pkgs/gst-plugins-ugly/1.x.nix { };
gst-plugins-ugly = callPackageAlias "gst-plugins-ugly_1" { };

gst-python_0 = callPackage ../all-pkgs/gst-python/0.x.nix { };
gst-python_1 = callPackage ../all-pkgs/gst-python/1.x.nix { };
gst-python = callPackageAlias "gst-python_1" { };

gst-validate = callPackage ../all-pkgs/gst-validate { };

gstreamer_0 = callPackage ../all-pkgs/gstreamer/0.x.nix { };
gstreamer_1 = callPackage ../all-pkgs/gstreamer/1.x.nix { };
gstreamer = callPackageAlias "gstreamer_1" { };

gstreamer-editing-services = callPackage ../all-pkgs/gstreamer-editing-services { };

gstreamer-vaapi = callPackage ../all-pkgs/gstreamer-vaapi { };

gstreamermm = callPackage ../all-pkgs/gstreamermm { };

gtk-doc = callPackage ../all-pkgs/gtk-doc { };

gtk_2 = callPackage ../all-pkgs/gtk+/2.x.nix { };
gtk2 = callPackageAlias "gtk_2" { };
gtk_3 = callPackage ../all-pkgs/gtk+/3.x.nix { };
gtk3 = callPackageAlias "gtk_3" { };

gtkhtml = callPackage ../all-pkgs/gtkhtml { };

gtkmm_2 = callPackage ../all-pkgs/gtkmm/2.x.nix { };
gtkmm_3 = callPackage ../all-pkgs/gtkmm/3.x.nix { };

gtksourceview = callPackage ../all-pkgs/gtksourceview { };

gtkspell_2 = callPackage ../all-pkgs/gtkspell/2.x.nix { };
gtkspell_3 = callPackage ../all-pkgs/gtkspell/3.x.nix { };
gtkspell = callPackageAlias "gtkspell_3" { };

guitarix = callPackage ../all-pkgs/guitarix {
  fftw = fftwSinglePrec;
};

gupnp = callPackage ../all-pkgs/gupnp { };

gupnp-av = callPackage ../all-pkgs/gupnp-av { };

gupnp-igd = callPackage ../all-pkgs/gupnp-igd { };

gvfs = callPackage ../all-pkgs/gvfs { };

gx = pkgs.goPackages.gx.bin // { outputs = [ "bin" ]; };

gzip = callPackage ../all-pkgs/gzip { };

hadoop = callPackage ../all-pkgs/hadoop { };

harfbuzz = callPackage ../all-pkgs/harfbuzz { };

help2man = callPackage ../all-pkgs/help2man { };

highlight = callPackage ../all-pkgs/highlight { };

htop = callPackage ../all-pkgs/htop { };

hwdata = callPackage ../all-pkgs/hwdata { };

iasl = callPackage ../all-pkgs/iasl { };

ibus = callPackage ../all-pkgs/ibus { };

icu = callPackage ../all-pkgs/icu { };

id3lib = callPackage ../all-pkgs/id3lib { };

imagemagick_light = imagemagick.override {
  libcl = null;
  perl = null;
  jemalloc = null;
  bzip2 = null;
  zlib = null;
  libX11 = null;
  libXext = null;
  libXt = null;
  dejavu_fonts = null;
  fftw = null;
  libfpx = null;
  djvulibre = null;
  fontconfig = null;
  freetype = null;
  ghostscript = null;
  graphviz = null;
  jbigkit = null;
  libjpeg = null;
  lcms2 = null;
  openjpeg = null;
  liblqr1 = null;
  xz = null;
  openexr = null;
  pango = null;
  libpng = null;
  librsvg = null;
  libtiff = null;
  libwebp = null;
  libxml2 = null;
};

imagemagick = callPackage ../all-pkgs/imagemagick { };

inkscape = callPackage ../all-pkgs/inkscape { };

intltool = callPackage ../all-pkgs/intltool { };

ipset = callPackage ../all-pkgs/ipset { };

iputils = callPackage ../all-pkgs/iputils { };

isl = callPackage ../all-pkgs/isl { };
isl_0_14 = callPackage ../all-pkgs/isl { channel = "0.14"; };

jam = callPackage ../all-pkgs/jam { };

jemalloc = callPackage ../all-pkgs/jemalloc { };

json-glib = callPackage ../all-pkgs/json-glib { };

kbd = callPackage ../all-pkgs/kbd { };

kea = callPackage ../all-pkgs/kea { };

kerberos = callPackageAlias "krb5_lib" { };

kmod = callPackage ../all-pkgs/kmod { };

krb5_full = callPackage ../all-pkgs/krb5 { };

krb5_lib = callPackageAlias "krb5_full" {
  type = "lib";
};

kubernetes = callPackage ../all-pkgs/kubernetes { };

ldb = callPackage ../all-pkgs/ldb { };

libarchive = callPackage ../all-pkgs/libarchive { };

libass = callPackage ../all-pkgs/libass { };

libbluray = callPackage ../all-pkgs/libbluray { };

libbsd = callPackage ../all-pkgs/libbsd { };

libcanberra = callPackage ../all-pkgs/libcanberra { };

libcap_ng = callPackage ../all-pkgs/libcap-ng { };

libclc = callPackage ../all-pkgs/libclc { };

libcroco = callPackage ../all-pkgs/libcroco { };

libcue = callPackage ../all-pkgs/libcue { };

libdrm = callPackage ../all-pkgs/libdrm { };

libebml = callPackage ../all-pkgs/libebml { };

libelf = callPackage ../all-pkgs/libelf { };

libev = callPackage ../all-pkgs/libev { };

libevent = callPackage ../all-pkgs/libevent { };

libffi = callPackage ../all-pkgs/libffi { };

libfilezilla = callPackage ../all-pkgs/libfilezilla { };

libgcrypt = callPackage ../all-pkgs/libgcrypt { };

libgdata = callPackage ../all-pkgs/libgdata { };

libgee = callPackage ../all-pkgs/libgee { };

libgfbgraph = callPackage ../all-pkgs/libgfbgraph { };

libgksu = callPackage ../all-pkgs/libgksu { };

libglvnd = callPackage ../all-pkgs/libglvnd { };

libgnomekbd = callPackage ../all-pkgs/libgnomekbd { };

libgpg-error = callPackage ../all-pkgs/libgpg-error { };

libgphoto2 = callPackage ../all-pkgs/libgphoto2 { };

libgpod = callPackage ../all-pkgs/libgpod {
  inherit (pkgs.pythonPackages) mutagen;
};

libgudev = callPackage ../all-pkgs/libgudev { };

libgusb = callPackage ../all-pkgs/libgusb { };

libgweather = callPackage ../all-pkgs/libgweather { };

libgxps = callPackage ../all-pkgs/libgxps { };

libidl = callPackage ../all-pkgs/libidl { };

libinput = callPackage ../all-pkgs/libinput { };

libjpeg_original = callPackage ../all-pkgs/libjpeg { };
libjpeg_turbo = callPackage ../all-pkgs/libjpeg-turbo { };
libjpeg = callPackageAlias "libjpeg_turbo" { };

libmatroska = callPackage ../all-pkgs/libmatroska { };

libmcrypt = callPackage ../all-pkgs/libmcrypt {};

libmediaart = callPackage ../all-pkgs/libmediaart {
  qt5 = null;
};

libmhash = callPackage ../all-pkgs/libmhash { };

libmicrohttpd = callPackage ../all-pkgs/libmicrohttpd { };

libmnl = callPackage ../all-pkgs/libmnl { };

libmpc = callPackage ../all-pkgs/libmpc { };

libmpdclient = callPackage ../all-pkgs/libmpdclient { };

libmsgpack = callPackage ../all-pkgs/libmsgpack { };

libnl = callPackage ../all-pkgs/libnl { };

libogg = callPackage ../all-pkgs/libogg { };

libomxil-bellagio = callPackage ../all-pkgs/libomxil-bellagio { };

libosinfo = callPackage ../all-pkgs/libosinfo { };

libossp-uuid = callPackage ../all-pkgs/libossp-uuid { };

libpeas = callPackage ../all-pkgs/libpeas { };

libpng = callPackage ../all-pkgs/libpng { };

libraw = callPackage ../all-pkgs/libraw { };

librsvg = callPackage ../all-pkgs/librsvg { };

librsync = callPackage ../all-pkgs/librsync { };

libsecret = callPackage ../all-pkgs/libsecret { };

libssh = callPackage ../all-pkgs/libssh { };

libssh2 = callPackage ../all-pkgs/libssh2 { };

libsigcxx = callPackage ../all-pkgs/libsigcxx { };

libsigsegv = callPackage ../all-pkgs/libsigsegv { };

libsodium = callPackage ../all-pkgs/libsodium { };

libsoup = callPackage ../all-pkgs/libsoup { };

libspectre = callPackage ../all-pkgs/libspectre { };

libtheora = callPackage ../all-pkgs/libtheora { };

libtirpc = callPackage ../all-pkgs/libtirpc { };

libtool = callPackage ../all-pkgs/libtool { };

libtorrent = callPackage ../all-pkgs/libtorrent { };

libtorrent-rasterbar_0 = callPackage ../all-pkgs/libtorrent-rasterbar/0.x.nix { };
libtorrent-rasterbar_1 = callPackage ../all-pkgs/libtorrent-rasterbar/1.x.nix { };
libtorrent-rasterbar = callPackageAlias "libtorrent-rasterbar_1" { };

libunique_1 = callPackage ../all-pkgs/libunique/1.x.nix { };
libunique_3 = callPackage ../all-pkgs/libunique/3.x.nix { };
libunique = callPackageAlias "libunique_3" { };

libusb-compat = callPackage ../all-pkgs/libusb-compat { };

libusb_0 = callPackageAlias "libusb-compat" { };
libusb_1 = callPackage ../all-pkgs/libusb { };
libusb = callPackageAlias "libusb_1" { };

libusbmuxd = callPackage ../all-pkgs/libusbmuxd { };

libva = callPackage ../all-pkgs/libva { };

libvdpau = callPackage ../all-pkgs/libvdpau { };

libverto = callPackage ../all-pkgs/libverto { };

libvorbis = callPackage ../all-pkgs/libvorbis { };

libvpx = callPackage ../all-pkgs/libvpx { };
libvpx_HEAD = callPackage ../development/libraries/libvpx/git.nix { };

libwacom = callPackage ../all-pkgs/libwacom { };

libwps = callPackage ../all-pkgs/libwps { };

libxkbcommon = callPackage ../all-pkgs/libxkbcommon { };

libxml2 = callPackage ../all-pkgs/libxml2 { };

libxslt = callPackage ../all-pkgs/libxslt { };

libzapojit = callPackage ../all-pkgs/libzapojit { };

linux-headers = callPackage ../all-pkgs/linux-headers { };

live555 = callPackage ../all-pkgs/live555 { };

lm-sensors = callPackage ../all-pkgs/lm-sensors { };

lvm2 = callPackage ../all-pkgs/lvm2 { };

lz4 = callPackage ../all-pkgs/lz4 { };

lzip = callPackage ../all-pkgs/lzip { };

lzo = callPackage ../all-pkgs/lzo { };

m4 = callPackageAlias "gnum4" { };

man-pages = callPackage ../all-pkgs/man-pages { };

mercurial = callPackage ../all-pkgs/mercurial { };

mesa_glu =  callPackage ../all-pkgs/mesa-glu { };
mesa_noglu = callPackage ../all-pkgs/mesa {
  # makes it slower, but during runtime we link against just
  # mesa_drivers through mesa_noglu.driverSearchPath, which is overriden
  # according to config.grsecurity
  grsecEnabled = config.grsecurity or false;
};
mesa_drivers = pkgs.mesa_noglu.drivers;
mesa = pkgs.buildEnv {
  name = "mesa-${pkgs.mesa_noglu.version}";
  paths = with pkgs; [ mesa_noglu mesa_glu ];
  passthru = pkgs.mesa_glu.passthru // pkgs.mesa_noglu.passthru;
};

mesos = callPackage ../all-pkgs/mesos {
  inherit (pythonPackages) python boto setuptools wrapPython;
  pythonProtobuf = pythonPackages.protobuf2_5;
  perf = linuxPackages.perf;
};

mg = callPackage ../all-pkgs/mg { };

mime-types = callPackage ../all-pkgs/mime-types { };

mixxx = callPackage ../all-pkgs/mixxx { };

mkvtoolnix = callPackage ../all-pkgs/mkvtoolnix { };

mp4v2 = callPackage ../all-pkgs/mp4v2 { };

mpd = callPackage ../all-pkgs/mpd { };

mpdris2 = callPackage ../all-pkgs/mpdris2 { };

mpfr = callPackage ../all-pkgs/mpfr { };

mpv = callPackage ../all-pkgs/mpv { };

inherit (callPackages ../all-pkgs/mumble {
  jackSupport = config.jack or false;
  speechdSupport = config.mumble.speechdSupport or false;
  pulseSupport = config.pulseaudio or false;
  iceSupport = config.murmur.iceSupport or true;
})
  mumble
  mumble_git
  murmur
  murmur_git;

musepack = callPackage ../all-pkgs/musepack { };

musl = callPackage ../all-pkgs/musl { };

mutter = callPackage ../all-pkgs/mutter { };

nano = callPackage ../all-pkgs/nano { };

nasm = callPackage ../all-pkgs/nasm { };

nautilus = callPackage ../all-pkgs/nautilus { };

ncdc = callPackage ../all-pkgs/ncdc { };

ncmpc = callPackage ../all-pkgs/ncmpc { };

ncmpcpp = callPackage ../all-pkgs/ncmpcpp { };

ncurses = callPackage ../all-pkgs/gpm+ncurses { };

net-tools = callPackage ../all-pkgs/net-tools { };

nettle = callPackage ../all-pkgs/nettle { };

# stripped down, needed by steam
networkmanager098 = callPackage ../all-pkgs/networkmanager/0.9.8.nix { };

networkmanager = callPackage ../all-pkgs/networkmanager { };

networkmanager-openvpn = callPackage ../all-pkgs/networkmanager-openvpn { };

networkmanager-pptp = callPackage ../all-pkgs/networkmanager-pptp { };

networkmanager-l2tp = callPackage ../all-pkgs/networkmanager-l2tp { };

networkmanager-vpnc = callPackage ../all-pkgs/networkmanager-vpnc { };

networkmanager-openconnect = callPackage ../all-pkgs/networkmanager-openconnect { };

networkmanager-applet = callPackage ../all-pkgs/networkmanager-applet { };

nghttp2_full = callPackage ../all-pkgs/nghttp2 { };

nghttp2_lib = callPackageAlias "nghttp2_full" {
  prefix = "lib";
};

nginx = callPackage ../all-pkgs/nginx { };

ninja = callPackage ../all-pkgs/ninja { };

nmap = callPackage ../all-pkgs/nmap { };

noise = callPackage ../all-pkgs/noise { };

numactl = callPackage ../all-pkgs/numactl { };

obexftp = callPackage ../all-pkgs/obexftp { };

openldap = callPackage ../all-pkgs/openldap { };

openobex = callPackage ../all-pkgs/openobex { };

openssl = callPackage ../all-pkgs/openssl { };

openvpn = callPackage ../all-pkgs/openvpn { };

orbit2 = callPackage ../all-pkgs/orbit2 { };

p7zip = callPackage ../all-pkgs/p7zip { };

pam = callPackage ../all-pkgs/pam { };

pango = callPackage ../all-pkgs/pango { };

pangomm = callPackage ../all-pkgs/pangomm { };

pangox-compat = callPackage ../all-pkgs/pangox-compat { };

parallel = callPackage ../all-pkgs/parallel { };

patchelf = callPackage ../all-pkgs/patchelf { };

pavucontrol = callPackage ../all-pkgs/pavucontrol { };

pciutils = callPackage ../all-pkgs/pciutils { };

pcre = callPackage ../all-pkgs/pcre { };

pcre2 = callPackage ../all-pkgs/pcre2 { };

pcsclite = callPackage ../all-pkgs/pcsclite { };

perl = callPackage ../all-pkgs/perl { };

pixman = callPackage ../all-pkgs/pixman { };

pkgconf = callPackage ../all-pkgs/pkgconf { };
pkg-config = callPackage ../all-pkgs/pkgconfig { };
pkgconfig = callPackageAlias "pkgconf" { };

pngcrush = callPackage ../all-pkgs/pngcrush { };

poppler_qt4 = callPackageAlias "poppler" {
  suffix = "qt4";
  qt4 = qt4;
  qt5 = null;
};
poppler_qt5 = callPackageAlias "poppler" {
  suffix = "qt5";
  qt4 = null;
  qt5 = qt54;
};
poppler_utils = callPackageAlias "poppler" {
  suffix = "utils";
  utils = true;
};
poppler = callPackage ../all-pkgs/poppler {
  qt4 = null;
  qt5 = null;
};

postgresql = callPackageAlias "postgresql95" { };
postgresql_lib = callPackageAlias "postgresql" { };

inherit (callPackages ../all-pkgs/postgresql { })
  postgresql91
  postgresql92
  postgresql93
  postgresql94
  postgresql95;

potrace = callPackage ../all-pkgs/potrace {};

psmisc = callPackage ../all-pkgs/psmisc { };

pugixml = callPackage ../all-pkgs/pugixml { };

pulseaudio_full = callPackage ../all-pkgs/pulseaudio { };

pulseaudio_lib = callPackageAlias "pulseaudio_full" {
  prefix = "lib";
};

python27 = callPackage ../all-pkgs/python/2.x.nix {
  channel = "2.7";
  self = callPackageAlias "python27" { };
};
python32 = callPackage ../all-pkgs/python {
  channel = "3.2";
  self = callPackageAlias "python32" { };
};
python33 = callPackage ../all-pkgs/python {
  channel = "3.3";
  self = callPackageAlias "python33" { };
};
python34 = callPackage ../all-pkgs/python {
  channel = "3.4";
  self = callPackageAlias "python34" { };
};
python35 = hiPrio (callPackage ../all-pkgs/python {
  channel = "3.5";
  self = callPackageAlias "python35" { };
});
pypy = callPackage ../all-pkgs/pypy {
  self = callPackageAlias "pypy" { };
};
python2 = callPackageAlias "python27" { };
python3 = callPackageAlias "python35" { };
python = callPackageAlias "python2" { };

python27Packages = hiPrioSet (recurseIntoAttrs (callPackage ../top-level/python-packages.nix {
  python = callPackageAlias "python27" { };
  self = callPackageAlias "python27Packages" { };
}));
python32Packages = callPackage ../top-level/python-packages.nix {
  python = callPackageAlias "python32" { };
  self = callPackageAlias "python32Packages" { };
};
python33Packages = callPackage ../top-level/python-packages.nix {
  python = callPackageAlias "python33" { };
  self = callPackageAlias "python33Packages" { };
};
python34Packages = callPackage ../top-level/python-packages.nix {
  python = callPackageAlias "python34" { };
  self = callPackageAlias "python34Packages" { };
};
python35Packages = recurseIntoAttrs (callPackage ../top-level/python-packages.nix {
  python = callPackageAlias "python35" { };
  self = callPackageAlias "python35Packages" { };
});
pypyPackages = recurseIntoAttrs (callPackage ../top-level/python-packages.nix {
  python = callPackageAlias "pypy" { };
  self = callPackageAlias "pypyPackages" { };
});
python2Packages = callPackageAlias "python27Packages" { };
python3Packages = callPackageAlias "python35Packages" { };
pythonPackages = callPackageAlias "python2Packages" { };

buildPythonPackage = (callPackageAlias "pythonPackages" { }).buildPythonPackage;

qbittorrent = callPackage ../all-pkgs/qbittorrent { };

qjackctl = callPackage ../all-pkgs/qjackctl { };

qrencode = callPackage ../all-pkgs/qrencode { };

qt4 = callPackage ../all-pkgs/qt/4 { };

quassel = callPackage ../all-pkgs/quassel rec {
  monolithic = true;
  daemon = false;
  client = false;
};
quasselDaemon = (pkgs.quassel.override {
  monolithic = false;
  daemon = true;
  client = false;
  tag = "-daemon";
});
quasselClient = (pkgs.quassel.override {
  monolithic = false;
  daemon = false;
  client = true;
  tag = "-client";
});

rapidjson = callPackage ../all-pkgs/rapidjson { };

readline = callPackage ../all-pkgs/readline { };

redis = callPackage ../all-pkgs/redis { };

rest = callPackage ../all-pkgs/rest { };

rocksdb = callPackage ../all-pkgs/rocksdb { };

rtmpdump = callPackage ../all-pkgs/rtmpdump { };

rtorrent = callPackage ../all-pkgs/rtorrent { };

sakura = callPackage ../all-pkgs/sakura { };

samba = callPackage ../all-pkgs/samba { };

scrot = callPackage ../all-pkgs/scrot { };

seabios = callPackage ../all-pkgs/seabios { };

seahorse = callPackage ../all-pkgs/seahorse { };

serf = callPackage ../all-pkgs/serf { };

sharutils = callPackage ../all-pkgs/sharutils { };

snappy = callPackage ../all-pkgs/snappy { };

sqlheavy = callPackage ../all-pkgs/sqlheavy { };

sqlite = callPackage ../all-pkgs/sqlite { };

steamPackages = callPackage ../all-pkgs/steam { };
steam = steamPackages.steam-chrootenv.override {
  # DEPRECATED
  withJava = config.steam.java or false;
  withPrimus = config.steam.primus or false;
};

sublime-text = callPackage ../all-pkgs/sublime-text { };

inherit (callPackages ../all-pkgs/subversion { })
  subversion18 subversion19;

subversion = callPackageAlias "subversion19" { };

sushi = callPackage ../all-pkgs/sushi { };

swig = callPackage ../all-pkgs/swig { };

swig2 = callPackageAlias "swig" {
  channel = "2";
};

# TODO: Rename back to systemd once depedencies are sorted
systemd_full = callPackage ../all-pkgs/systemd { };

systemd_lib = callPackageAlias "systemd_full" {
  type = "lib";
};

talloc = callPackage ../all-pkgs/talloc { };

tcp-wrappers = callPackage ../all-pkgs/tcp-wrappers { };

tdb = callPackage ../all-pkgs/tdb { };

tevent = callPackage ../all-pkgs/tevent { };

texinfo = callPackage ../all-pkgs/texinfo { };

totem-pl-parser = callPackage ../all-pkgs/totem-pl-parser { };

tracker = callPackage ../all-pkgs/tracker { };

tzdata = callPackage ../all-pkgs/tzdata { };

udisks = callPackage ../all-pkgs/udisks { };

unbound = callPackage ../all-pkgs/unbound { };

unrar = callPackage ../all-pkgs/unrar { };

usbmuxd = callPackage ../all-pkgs/usbmuxd { };

util-linux_full = callPackage ../all-pkgs/util-linux { };

util-linux_lib = callPackageAlias "util-linux_full" {
  type = "lib";
};

vala = callPackage ../all-pkgs/vala { };

vim = callPackage ../all-pkgs/vim { };

vino = callPackage ../all-pkgs/vino { };

vlc = callPackage ../all-pkgs/vlc { };

vte = callPackage ../all-pkgs/vte { };

w3m = callPackage ../all-pkgs/w3m { };

wayland = callPackage ../all-pkgs/wayland { };
wayland-docs = callPackage ../all-pkgs/wayland {
  enableDocumentation = true;
};

webkitgtk_2_4_gtk3 = callPackage ../all-pkgs/webkitgtk/2.4.x.nix {
  gtkVer = "3";
};
webkitgtk_2_4_gtk2 = webkitgtk_2_4_gtk3.override {
  gtkVer = "2";
};
webkitgtk_2_4 = webkitgtk_2_4_gtk3;
webkitgtk = callPackage ../all-pkgs/webkitgtk { };

which = callPackage ../all-pkgs/which { };

wxGTK = callPackage ../all-pkgs/wxGTK { };

x264 = callPackage ../all-pkgs/x264 { };

x265 = callPackage ../all-pkgs/x265 { };

xdg-utils = callPackage ../all-pkgs/xdg-utils { };

xfsprogs = callPackage ../all-pkgs/xfsprogs { };
xfsprogs_lib = pkgs.xfsprogs.lib;

xine-lib = callPackage ../all-pkgs/xine-lib { };

xine-ui = callPackage ../all-pkgs/xine-ui { };

xmlto = callPackage ../all-pkgs/xmlto { };

xmltoman = callPackage ../all-pkgs/xmltoman { };

xz = callPackage ../all-pkgs/xz { };

yasm = callPackage ../all-pkgs/yasm { };

zeitgeist = callPackage ../all-pkgs/zeitgeist { };

zenity = callPackage ../all-pkgs/zenity { };

zip = callPackage ../all-pkgs/zip { };

zlib = callPackage ../all-pkgs/zlib { };

zsh = callPackage ../all-pkgs/zsh { };

zstd = callPackage ../all-pkgs/zstd { };

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
############################### END ALL PKGS ###################################
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
#
#  ### TOOLS
#
#  _9pfs = callPackage ../tools/filesystems/9pfs { };
#
#  a2ps = callPackage ../tools/text/a2ps { };
#
#  abduco = callPackage ../tools/misc/abduco { };
#
#  acbuild = callPackage ../applications/misc/acbuild { };
#
#  acct = callPackage ../tools/system/acct { };
#
#  acoustidFingerprinter = callPackage ../tools/audio/acoustid-fingerprinter {
#    ffmpeg = ffmpeg_1;
#  };
#
#  actdiag = pythonPackages.actdiag;
#
#  actkbd = callPackage ../tools/system/actkbd { };
#
#  advancecomp = callPackage ../tools/compression/advancecomp {};
#
#  aegisub = callPackage ../applications/video/aegisub {
#    wxGTK = wxGTK30;
#    spellcheckSupport = config.aegisub.spellcheckSupport or true;
#    automationSupport = config.aegisub.automationSupport or true;
#    openalSupport     = config.aegisub.openalSupport or false;
#    alsaSupport       = config.aegisub.alsaSupport or true;
#    pulseaudioSupport = config.aegisub.pulseaudioSupport or true;
#    portaudioSupport  = config.aegisub.portaudioSupport or false;
#  };
#
#  aespipe = callPackage ../tools/security/aespipe { };
#
#  aescrypt = callPackage ../tools/misc/aescrypt { };
#
#  afl = callPackage ../tools/security/afl { };
#
#  aha = callPackage ../tools/text/aha { };
#
#  ahcpd = callPackage ../tools/networking/ahcpd { };
#
#  aiccu = callPackage ../tools/networking/aiccu { };
#
#  aide = callPackage ../tools/security/aide { };
#
#  aircrack-ng = callPackage ../tools/networking/aircrack-ng { };
#
#  airfield = callPackage ../tools/networking/airfield { };
#
#  aj-snapshot  = callPackage ../applications/audio/aj-snapshot { };
#
#  albert = qt5.callPackage ../applications/misc/albert {};
#
#  analog = callPackage ../tools/admin/analog {};
#
#  apktool = callPackage ../development/tools/apktool {
#    buildTools = androidenv.buildTools;
#  };
#
#  apt-cacher-ng = callPackage ../servers/http/apt-cacher-ng { };
#
#  apt-offline = callPackage ../tools/misc/apt-offline { };
#
#  apulse = callPackage ../misc/apulse { };
#
#  archivemount = callPackage ../tools/filesystems/archivemount { };
#
#  arandr = callPackage ../tools/X11/arandr { };
#
#  arangodb = callPackage ../servers/nosql/arangodb {
#    inherit (pythonPackages) gyp;
#  };
#
#  arcanist = callPackage ../development/tools/misc/arcanist {};
#
#  arduino = arduino-core.override { withGui = true; };
#
#  arduino-core = callPackage ../development/arduino/arduino-core {
#    jdk = jdk;
#    jre = jdk;
#    withGui = false;
#  };
#
#  apitrace = qt5.callPackage ../applications/graphics/apitrace {};
#
#  arp-scan = callPackage ../tools/misc/arp-scan { };
#
#  artyFX = callPackage ../applications/audio/artyFX {};
#
#  ascii = callPackage ../tools/text/ascii { };
#
#  asciinema = pkgs.goPackages.asciinema.bin // { outputs = [ "bin" ]; };
#
#  asymptote = callPackage ../tools/graphics/asymptote {
#    texLive = texlive.combine { inherit (texlive) scheme-small epsf cm-super; };
#    gsl = gsl_1;
#  };
#
#  atomicparsley = callPackage ../tools/video/atomicparsley { };
#
#  attic = callPackage ../tools/backup/attic { };
#
#  avfs = callPackage ../tools/filesystems/avfs { };
#
#  awscli = pythonPackages.awscli;
#
#  azure-cli = callPackage ../tools/virtualization/azure-cli { };
#
#  altermime = callPackage ../tools/networking/altermime {};
#
#  amule = callPackage ../tools/networking/p2p/amule { };
#
#  amuleDaemon = appendToName "daemon" (amule.override {
#    monolithic = false;
#    daemon = true;
#  });
#
#  amuleGui = appendToName "gui" (amule.override {
#    monolithic = false;
#    client = true;
#  });
#
#  androidenv = callPackage ../development/mobile/androidenv {
#  };
#
#  apg = callPackage ../tools/security/apg { };
#
#  bonnie = callPackage ../tools/filesystems/bonnie { };
#
#  djmount = callPackage ../tools/filesystems/djmount { };
#
#  grc = callPackage ../tools/misc/grc { };
#
#  lastpass-cli = callPackage ../tools/security/lastpass-cli { };
#
#  pass = callPackage ../tools/security/pass { };
#
#  oracle-instantclient = callPackage ../development/libraries/oracle-instantclient { };
#
#  xcodeenv = callPackage ../development/mobile/xcodeenv { };
#
#  titaniumenv = callPackage ../development/mobile/titaniumenv {
#  };
#
#  inherit (androidenv) androidsdk_4_4 androidndk;
#
#  androidsdk = androidenv.androidsdk_6_0;
#
#  arc-gtk-theme = callPackage ../misc/themes/arc { };
#
#  at = callPackage ../tools/system/at { };
#
#  atftp = callPackage ../tools/networking/atftp {};
#
#  autojump = callPackage ../tools/misc/autojump { };
#
#  autorandr = callPackage ../tools/misc/autorandr {};
#
#  aws = callPackage ../tools/virtualization/aws { };
#
#  aws_mturk_clt = callPackage ../tools/misc/aws-mturk-clt { };
#
#  axel = callPackage ../tools/networking/axel { };
#
#  backblaze-b2 = callPackage ../development/tools/backblaze-b2 { };
#
#  backup = callPackage ../tools/backup/backup { };
#
#  basex = callPackage ../tools/text/xml/basex { };
#
#  babeld = callPackage ../tools/networking/babeld { };
#
#  badvpn = callPackage ../tools/networking/badvpn {};
#
#  barcode = callPackage ../tools/graphics/barcode {};
#
#  bashburn = callPackage ../tools/cd-dvd/bashburn { };
#
#  bashmount = callPackage ../tools/filesystems/bashmount {};
#
#  bdf2psf = callPackage ../tools/misc/bdf2psf { };
#
#  bchunk = callPackage ../tools/cd-dvd/bchunk { };
#
#  bfr = callPackage ../tools/misc/bfr { };
#
#  bibtool = callPackage ../tools/misc/bibtool { };
#
#  bibutils = callPackage ../tools/misc/bibutils { };
#
#  bindfs = callPackage ../tools/filesystems/bindfs { };
#
#  binwalk = callPackage ../tools/misc/binwalk {
#    wrapPython = pythonPackages.wrapPython;
#    curses = pythonPackages.curses;
#  };
#
#  binwalk-full = callPackage ../tools/misc/binwalk {
#    wrapPython = pythonPackages.wrapPython;
#    curses = pythonPackages.curses;
#    visualizationSupport = true;
#    pyqtgraph = pythonPackages.pyqtgraph;
#  };
#
#  bitbucket-cli = pythonPackages.bitbucket-cli;
#
#  blink = callPackage ../applications/networking/instant-messengers/blink { };
#
#  blitz = callPackage ../development/libraries/blitz { };
#
#  blockdiag = pythonPackages.blockdiag;
#
#  bmon = callPackage ../tools/misc/bmon { };
#
#  bochs = callPackage ../applications/virtualization/bochs { };
#
#  borgbackup = callPackage ../tools/backup/borg { };
#
#  boomerang = callPackage ../development/tools/boomerang { };
#
#  boost-build = callPackage ../development/tools/boost-build { };
#
#  boot = callPackage ../development/tools/build-managers/boot { };
#
#  bootchart = callPackage ../tools/system/bootchart { };
#
#  boxfs = callPackage ../tools/filesystems/boxfs { };
#
#  brasero = callPackage ../tools/cd-dvd/brasero { };
#
#  brltty = callPackage ../tools/misc/brltty {
#    alsaSupport = true;
#  };
#  bro = callPackage ../applications/networking/ids/bro { };
#
#  bruteforce-luks = callPackage ../tools/security/bruteforce-luks { };
#
#  bsod = callPackage ../misc/emulators/bsod { };
#
#  bwm_ng = callPackage ../tools/networking/bwm-ng { };
#
#  byobu = callPackage ../tools/misc/byobu {
#    # Choices: [ tmux screen ];
#    textual-window-manager = tmux;
#  };
#
#  bsh = fetchurl {
#    url = http://www.beanshell.org/bsh-2.0b5.jar;
#    sha256 = "0p2sxrpzd0vsk11zf3kb5h12yl1nq4yypb5mpjrm8ww0cfaijck2";
#  };
#
#  btfs = callPackage ../os-specific/linux/btfs { };
#
#  cabal2nix = haskellPackages.cabal2nix;
#
#  capstone = callPackage ../development/libraries/capstone { };
#
#  catch = callPackage ../development/libraries/catch { };
#
#  catdoc = callPackage ../tools/text/catdoc { };
#
#  cdemu-daemon = callPackage ../misc/emulators/cdemu/daemon.nix { };
#
#  cdemu-client = callPackage ../misc/emulators/cdemu/client.nix { };
#
#  ceres-solver = callPackage ../development/libraries/ceres-solver {
#    google-gflags = null; # only required for examples/tests
#  };
#
#  gcdemu = callPackage ../misc/emulators/cdemu/gui.nix { };
#
#  image-analyzer = callPackage ../misc/emulators/cdemu/analyzer.nix { };
#
#  ccnet = callPackage ../tools/networking/ccnet { };
#
#  ckbcomp = callPackage ../tools/X11/ckbcomp { };
#
#  cli53 = callPackage ../tools/admin/cli53 { };
#
#  cli-visualizer = callPackage ../applications/misc/cli-visualizer { };
#
#  cloud-init = callPackage ../tools/virtualization/cloud-init { };
#
#  clib = callPackage ../tools/package-management/clib { };
#
#  cherrytree = callPackage ../applications/misc/cherrytree { };
#
#  chntpw = callPackage ../tools/security/chntpw { };
#
#  coprthr = callPackage ../development/libraries/coprthr { };
#
#  cpulimit = callPackage ../tools/misc/cpulimit { };
#
#  contacts = callPackage ../tools/misc/contacts { };
#
#  datamash = callPackage ../tools/misc/datamash { };
#
#  ddate = callPackage ../tools/misc/ddate { };
#
#  deis = pkgs.goPackages.deis.bin // { outputs = [ "bin" ]; };
#
#  dfilemanager = kde5.dfilemanager;
#
#  diagrams-builder = callPackage ../tools/graphics/diagrams-builder {
#    inherit (haskellPackages) ghcWithPackages diagrams-builder;
#  };
#
#  dialog = callPackage ../development/tools/misc/dialog { };
#
#  ding = callPackage ../applications/misc/ding {
#    aspellDicts_de = aspellDicts.de;
#    aspellDicts_en = aspellDicts.en;
#  };
#
#  direnv = callPackage ../tools/misc/direnv { };
#
#  discount = callPackage ../tools/text/discount { };
#
#  disorderfs = callPackage ../tools/filesystems/disorderfs {
#    asciidoc = asciidoc-full;
#  };
#
#  ditaa = callPackage ../tools/graphics/ditaa { };
#
#  dlx = callPackage ../misc/emulators/dlx { };
#
#  dragon-drop = callPackage ../tools/X11/dragon-drop {
#    gtk = gtk3;
#  };
#
#  dtrx = callPackage ../tools/compression/dtrx { };
#
#  duperemove = callPackage ../tools/filesystems/duperemove { };
#
#  dynamic-colors = callPackage ../tools/misc/dynamic-colors { };
#
#  eggdrop = callPackage ../tools/networking/eggdrop { };
#
#  elementary-icon-theme = callPackage ../data/icons/elementary-icon-theme { };
#
#  enca = callPackage ../tools/text/enca { };
#
#  ent = callPackage ../tools/misc/ent { };
#
#  facter = callPackage ../tools/system/facter {};
#
#  fasd = callPackage ../tools/misc/fasd { };
#
#  fop = callPackage ../tools/typesetting/fop { };
#
#  filter_audio = callPackage ../development/libraries/filter_audio { };
#
#  fzf = pkgs.goPackages.fzf.bin // { outputs = [ "bin" ]; };
#
#  gencfsm = callPackage ../tools/security/gencfsm { };
#
#  gist = callPackage ../tools/text/gist { };
#
#  gmic = callPackage ../tools/graphics/gmic { };
#
#  heatseeker = callPackage ../tools/misc/heatseeker { };
#
#  interlock = pkgs.goPackages.interlock.bin // { outputs = [ "bin" ]; };
#
#  mathics = pythonPackages.mathics;
#
#  mcrl = callPackage ../tools/misc/mcrl { };
#
#  mcrl2 = callPackage ../tools/misc/mcrl2 { };
#
#  meson = callPackage ../development/tools/build-managers/meson { };
#
#  mp3fs = callPackage ../tools/filesystems/mp3fs { };
#
#  mpdcron = callPackage ../tools/audio/mpdcron { };
#
#  syscall_limiter = callPackage ../os-specific/linux/syscall_limiter {};
#
#  syslogng = callPackage ../tools/system/syslog-ng { };
#
#  syslogng_incubator = callPackage ../tools/system/syslog-ng-incubator { };
#
#  rsyslog = callPackage ../tools/system/rsyslog {
#    hadoop = null; # Currently Broken
#  };
#
#  rsyslog-light = callPackage ../tools/system/rsyslog {
#    libkrb5 = null;
#    systemd = null;
#    jemalloc = null;
#    libmysql = null;
#    postgresql = null;
#    libdbi = null;
#    net_snmp = null;
#    libuuid = null;
#    curl = null;
#    gnutls = null;
#    libgcrypt = null;
#    liblognorm = null;
#    openssl = null;
#    librelp = null;
#    libgt = null;
#    libksi = null;
#    liblogging = null;
#    libnet = null;
#    hadoop = null;
#    rdkafka = null;
#    libmongo-client = null;
#    czmq = null;
#    rabbitmq-c = null;
#    hiredis = null;
#  };
#
#  mcrypt = callPackage ../tools/misc/mcrypt { };
#
#  mongodb-tools = pkgs.goPackages.mongo-tools.bin // { outputs = [ "bin" ]; };
#
#  mstflint = callPackage ../tools/misc/mstflint { };
#
#  mcelog = callPackage ../os-specific/linux/mcelog { };
#
#  apparix = callPackage ../tools/misc/apparix { };
#
  appdata-tools = callPackage ../tools/misc/appdata-tools { };

#  autossh = callPackage ../tools/networking/autossh { };
#
#  asynk = callPackage ../tools/networking/asynk { };
#
#  b2 = callPackage ../tools/backup/b2 { };
#
#  bacula = callPackage ../tools/backup/bacula { };
#
#  bareos = callPackage ../tools/backup/bareos { };
#
#  bats = callPackage ../development/interpreters/bats { };
#
#  beanstalkd = callPackage ../servers/beanstalkd { };
#
#  bgs = callPackage ../tools/X11/bgs { };
#
#  biber = callPackage ../tools/typesetting/biber {
#    inherit (perlPackages)
#      autovivification BusinessISBN BusinessISMN BusinessISSN ConfigAutoConf
#      DataCompare DataDump DateSimple EncodeEUCJPASCII EncodeHanExtra EncodeJIS2K
#      ExtUtilsLibBuilder FileSlurp IPCRun3 Log4Perl LWPProtocolHttps ListAllUtils
#      ListMoreUtils ModuleBuild MozillaCA ReadonlyXS RegexpCommon TextBibTeX
#      UnicodeCollate UnicodeLineBreak URI XMLLibXMLSimple XMLLibXSLT XMLWriter;
#  };
#
#  bibtextools = callPackage ../tools/typesetting/bibtex-tools {
#    inherit (strategoPackages016) strategoxt sdf;
#  };
#
#  bittornado = callPackage ../tools/networking/p2p/bit-tornado { };
#
#  blueman = callPackage ../tools/bluetooth/blueman {
#    inherit (gnome3) dconf;
#    withPulseAudio = config.pulseaudio or true;
#  };
#
#  bmrsa = callPackage ../tools/security/bmrsa/11.nix { };
#
#  bogofilter = callPackage ../tools/misc/bogofilter { };
#
#  bsdiff = callPackage ../tools/compression/bsdiff { };
#
#  btar = callPackage ../tools/backup/btar {
#    librsync = librsync_0_9;
#  };
#
#  bud = callPackage ../tools/networking/bud {
#    inherit (pythonPackages) gyp;
#  };
#
#  bup = callPackage ../tools/backup/bup {
#    inherit (pythonPackages) pyxattr pylibacl setuptools fuse;
#    par2Support = (config.bup.par2Support or false);
#  };
#
#  burp_1_3 = callPackage ../tools/backup/burp/1.3.48.nix { };
#
#  burp = callPackage ../tools/backup/burp { };
#
#  byzanz = callPackage ../applications/video/byzanz {};
#
#  ori = callPackage ../tools/backup/ori { };
#
#  atool = callPackage ../tools/archivers/atool { };
#
#  cabextract = callPackage ../tools/archivers/cabextract { };
#
#  cadaver = callPackage ../tools/networking/cadaver { };
#
#  davix = callPackage ../tools/networking/davix { };
#
#  cantata = qt5.callPackage ../applications/audio/cantata { };
#
#  can-utils = callPackage ../os-specific/linux/can-utils { };
#
#  caudec = callPackage ../applications/audio/caudec { };
#
#  ccrypt = callPackage ../tools/security/ccrypt { };
#
#  ccze = callPackage ../tools/misc/ccze { };
#
#  cdecl = callPackage ../development/tools/cdecl { };
#
#  cdrdao = callPackage ../tools/cd-dvd/cdrdao { };
#
#  cdrkit = callPackage ../tools/cd-dvd/cdrkit { };
#
#  cfdg = callPackage ../tools/graphics/cfdg { };
#
#  checkinstall = callPackage ../tools/package-management/checkinstall { };
#
#  chkrootkit = callPackage ../tools/security/chkrootkit { };
#
#  chrony = callPackage ../tools/networking/chrony { };
#
#  chunkfs = callPackage ../tools/filesystems/chunkfs { };
#
#  chunksync = callPackage ../tools/backup/chunksync { };
#
#  cipherscan = callPackage ../tools/security/cipherscan {
#    openssl = if stdenv.system == "x86_64-linux"
#      then openssl-chacha
#      else openssl;
#  };
#
#  cjdns = callPackage ../tools/networking/cjdns { };
#
#  cksfv = callPackage ../tools/networking/cksfv { };
#
#  clementine = callPackage ../applications/audio/clementine {
#    boost = boost155;
#    gst_plugins = [
#      gst-plugins-base_0
#      gst-plugins-good_0
#      gst-plugins-ugly_0
#      gst-ffmpeg
#    ];
#  };
#
#  clementineFree = clementine.free;
#
#  ciopfs = callPackage ../tools/filesystems/ciopfs { };
#
#  citrix_receiver = callPackage ../applications/networking/remote/citrix-receiver { };
#
#  cmst = qt5.callPackage ../tools/networking/cmst { };
#
  colord-gtk = callPackage ../tools/misc/colord-gtk { };
#
#  colordiff = callPackage ../tools/text/colordiff { };
#
#  concurrencykit = callPackage ../development/libraries/concurrencykit { };
#
#  connect = callPackage ../tools/networking/connect { };
#
#  conspy = callPackage ../os-specific/linux/conspy {};
#
#  connman = callPackage ../tools/networking/connman { };
#
#  connmanui = callPackage ../tools/networking/connmanui { };
#
#  convertlit = callPackage ../tools/text/convertlit { };
#
#  collectd = callPackage ../tools/system/collectd {
#    rabbitmq-c = rabbitmq-c_0_4;
#  };
#
#  colormake = callPackage ../development/tools/build-managers/colormake { };
#
#  cowsay = callPackage ../tools/misc/cowsay { };
#
#  cpuminer = callPackage ../tools/misc/cpuminer { };
#
#  cpuminer-multi = callPackage ../tools/misc/cpuminer-multi { };
#
#  cuetools = callPackage ../tools/cd-dvd/cuetools { };
#
#  unifdef = callPackage ../development/tools/misc/unifdef { };
#
  unionfs-fuse = callPackage ../tools/filesystems/unionfs-fuse { };
#
#  usb_modeswitch = callPackage ../development/tools/misc/usb-modeswitch { };
#
#  anthy = callPackage ../tools/inputmethods/anthy { };
#
#  m17n_db = callPackage ../tools/inputmethods/m17n-db { };
#
#  m17n_lib = callPackage ../tools/inputmethods/m17n-lib { };
#
#  mozc = callPackage ../tools/inputmethods/mozc {
#    inherit (pythonPackages) gyp;
#  };
#
#  ibus-qt = callPackage ../tools/inputmethods/ibus-qt { };
#
#  ibus-anthy = callPackage ../tools/inputmethods/ibus-anthy { };
#
#  ibus-table = callPackage ../tools/inputmethods/ibus-table { };
#
#  ibus-table-others = callPackage ../tools/inputmethods/ibus-table-others { };
#
#  brotli = callPackage ../tools/compression/brotli { };
#
#  biosdevname = callPackage ../tools/networking/biosdevname { };
#
#  checkbashism = callPackage ../development/tools/misc/checkbashisms { };
#
#  clamav = callPackage ../tools/security/clamav { };
#
#  clex = callPackage ../tools/misc/clex { };
#
#  cloc = callPackage ../tools/misc/cloc {
#    inherit (perlPackages) perl AlgorithmDiff RegexpCommon;
#  };
#
#  cloog = callPackage ../development/libraries/cloog {
#    isl = isl_0_14;
#  };
#
#  cloog_0_18_0 = callPackage ../development/libraries/cloog/0.18.0.nix {
#    isl = isl_0_11;
#  };
#
#  cloogppl = callPackage ../development/libraries/cloog-ppl { };
#
#  compass = callPackage ../development/tools/compass { };
#
#  convmv = callPackage ../tools/misc/convmv { };
#
#  cool-retro-term = qt5.callPackage ../applications/misc/cool-retro-term { };
#
#  corkscrew = callPackage ../tools/networking/corkscrew { };
#
#  crackxls = callPackage ../tools/security/crackxls { };
#
#  cromfs = callPackage ../tools/archivers/cromfs { };
#
#  cron = callPackage ../tools/system/cron { };
#
  cudatoolkit5 = callPackage ../development/compilers/cudatoolkit/5.5.nix { };

  cudatoolkit6 = callPackage ../development/compilers/cudatoolkit/6.0.nix { };

  cudatoolkit65 = callPackage ../development/compilers/cudatoolkit/6.5.nix { };

  cudatoolkit7 = callPackage ../development/compilers/cudatoolkit/7.0.nix { };

  cudatoolkit = callPackageAlias "cudatoolkit7" { };

#  cunit = callPackage ../tools/misc/cunit { };
#
#  curlftpfs = callPackage ../tools/filesystems/curlftpfs { };
#
#  cutter = callPackage ../tools/networking/cutter { };
#
#  cvs_fast_export = callPackage ../applications/version-management/cvs-fast-export { };
#
#  dadadodo = callPackage ../tools/text/dadadodo { };
#
#  daemonize = callPackage ../tools/system/daemonize { };
#
#  daq = callPackage ../applications/networking/ids/daq { };
#
#  dar = callPackage ../tools/archivers/dar { };
#
#  darkhttpd = callPackage ../servers/http/darkhttpd { };
#
#  darkstat = callPackage ../tools/networking/darkstat { };
#
#  davfs2 = callPackage ../tools/filesystems/davfs2 {
#    neon = neon_0_29;
#  };
#
#  dbench = callPackage ../development/tools/misc/dbench { };
#
#  dclxvi = callPackage ../development/libraries/dclxvi { };
#
#  dcraw = callPackage ../tools/graphics/dcraw { };
#
#  dcfldd = callPackage ../tools/system/dcfldd { };
#
#  debian_devscripts = callPackage ../tools/misc/debian-devscripts {
#    inherit (perlPackages) CryptSSLeay LWP TimeDate DBFile FileDesktopEntry;
#  };
#
#  debootstrap = callPackage ../tools/misc/debootstrap { };
#
#  detox = callPackage ../tools/misc/detox { };
#
#  devilspie2 = callPackage ../applications/misc/devilspie2 {
#    gtk = gtk3;
#  };
#
#  dex = callPackage ../tools/X11/dex { };
#
#  ddccontrol = callPackage ../tools/misc/ddccontrol { };
#
#  ddccontrol-db = callPackage ../data/misc/ddccontrol-db { };
#
#  ddclient = callPackage ../tools/networking/ddclient { };
#
#  dd_rescue = callPackage ../tools/system/dd_rescue { };
#
#  deluge = pythonPackages.deluge;
#
  desktop_file_utils = callPackage ../tools/misc/desktop-file-utils { };
#
#  despotify = callPackage ../development/libraries/despotify { };
#
#  dfc  = callPackage ../tools/system/dfc { };
#
#  dnscrypt-proxy = callPackage ../tools/networking/dnscrypt-proxy { };
#
#  dnscrypt-wrapper = callPackage ../tools/networking/dnscrypt-wrapper { };
#
  dnssec-root = callPackage ../data/misc/dnssec-root { };
#
  dnstop = callPackage ../tools/networking/dnstop { };

  dhcp = callPackage ../tools/networking/dhcp { };
#
#  dhcpdump = callPackage ../tools/networking/dhcpdump { };
#
  dhcpcd = callPackage ../tools/networking/dhcpcd { };
#
#  dhcping = callPackage ../tools/networking/dhcping { };
#
#  di = callPackage ../tools/system/di { };
#
#  diffoscope = callPackage ../tools/misc/diffoscope {
#    jdk = jdk7;
#    pythonPackages = python3Packages;
#    rpm = rpm.override { python = python3; };
#  };
#
#  diffstat = callPackage ../tools/text/diffstat { };
#
#  dir2opus = callPackage ../tools/audio/dir2opus {
#    inherit (pythonPackages) mutagen python wrapPython;
#  };
#
#  wgetpaste = callPackage ../tools/text/wgetpaste { };
#
#  dirmngr = callPackage ../tools/security/dirmngr { };
#
#  disper = callPackage ../tools/misc/disper { };
#
#  dmg2img = callPackage ../tools/misc/dmg2img { };
#
#  docbook2odf = callPackage ../tools/typesetting/docbook2odf {
#    inherit (perlPackages) PerlMagick;
#  };
#
  docbook2x = callPackage ../tools/typesetting/docbook2x { };
#
#  dog = callPackage ../tools/system/dog { };
#
  dosfstools = callPackage ../tools/filesystems/dosfstools { };
#
#  dotnetfx35 = callPackage ../development/libraries/dotnetfx35 { };
#
#  dotnetfx40 = callPackage ../development/libraries/dotnetfx40 { };
#
#  dolphinEmu = callPackage ../misc/emulators/dolphin-emu { };
#  dolphinEmuMaster = callPackage ../misc/emulators/dolphin-emu/master.nix { };
#
#  doomseeker = callPackage ../applications/misc/doomseeker { };
#
#  driftnet = callPackage ../tools/networking/driftnet {};
#
#  dropbear = callPackage ../tools/networking/dropbear { };
#
#  dtach = callPackage ../tools/misc/dtach { };
#
#  dtc = callPackage ../development/compilers/dtc { };
#
#  dub = callPackage ../development/tools/build-managers/dub { };
#
#  duff = callPackage ../tools/filesystems/duff { };
#
#  duo-unix = callPackage ../tools/security/duo-unix { };
#
#  duply = callPackage ../tools/backup/duply { };
#
#  dvdisaster = callPackage ../tools/cd-dvd/dvdisaster { };
#
#  dvdplusrwtools = callPackage ../tools/cd-dvd/dvd+rw-tools { };
#
#  dvgrab = callPackage ../tools/video/dvgrab { };
#
#  dvtm = callPackage ../tools/misc/dvtm { };
#
#  easyrsa = callPackage ../tools/networking/easyrsa { };
#
#  easyrsa2 = callPackage ../tools/networking/easyrsa/2.x.nix { };
#
#  ebook_tools = callPackage ../tools/text/ebook-tools { };
#
#  ecryptfs = callPackage ../tools/security/ecryptfs { };
#
#  editres = callPackage ../tools/graphics/editres { };
#
#  edk2 = callPackage ../development/compilers/edk2 { };
#
#  eid-mw = callPackage ../tools/security/eid-mw { };
#
#  eid-viewer = callPackage ../tools/security/eid-viewer { };
#
#  emscripten = callPackage ../development/compilers/emscripten { };
#
#  emscriptenfastcomp = callPackage ../development/compilers/emscripten-fastcomp { };
#
  efivar = callPackage ../tools/system/efivar { };
#
#  evemu = callPackage ../tools/system/evemu { };
#
#  elasticsearch = callPackage ../servers/search/elasticsearch { };
#  elasticsearch2 = callPackage ../servers/search/elasticsearch/2.x.nix { };
#
#  elasticsearchPlugins = recurseIntoAttrs (
#    callPackage ../servers/search/elasticsearch/plugins.nix { }
#  );
#
#  emem = callPackage ../applications/misc/emem { };
#
#  emv = callPackage ../tools/misc/emv { };
#
#  enblend-enfuse = callPackage ../tools/graphics/enblend-enfuse { };
#
#  encfs = callPackage ../tools/filesystems/encfs { };
#
#  enscript = callPackage ../tools/text/enscript { };
#
#  entr = callPackage ../tools/misc/entr { };
#
#  eplot = callPackage ../tools/graphics/eplot { };
#
  ethtool = callPackage ../tools/misc/ethtool { };
#
#  ettercap = callPackage ../applications/networking/sniffers/ettercap { };
#
#  euca2ools = callPackage ../tools/virtualization/euca2ools { };
#
#  eventstat = callPackage ../os-specific/linux/eventstat { };
#
#  evtest = callPackage ../applications/misc/evtest { };
#
  exempi = callPackage ../development/libraries/exempi { };
#
#  execline = callPackage ../tools/misc/execline { };
#
#  exif = callPackage ../tools/graphics/exif { };
#
#  exiftags = callPackage ../tools/graphics/exiftags { };
#
#  extundelete = callPackage ../tools/filesystems/extundelete { };
#
#  expect = callPackage ../tools/misc/expect { };
#
  f2fs-tools = callPackage ../tools/filesystems/f2fs-tools { };
#
#  Fabric = pythonPackages.Fabric;
#
#  fail2ban = callPackage ../tools/security/fail2ban { };
#
#  fakeroot = callPackage ../tools/system/fakeroot { };
#
#  fakechroot = callPackage ../tools/system/fakechroot { };
#
#  fatsort = callPackage ../tools/filesystems/fatsort { };
#
#  fcitx = callPackage ../tools/inputmethods/fcitx { };
#
#  fcitx-anthy = callPackage ../tools/inputmethods/fcitx/fcitx-anthy.nix { };
#
#  fcitx-configtool = callPackage ../tools/inputmethods/fcitx/fcitx-configtool.nix { };
#
#  fcitx-with-plugins = callPackage ../tools/inputmethods/fcitx/wrapper.nix {
#    plugins = [ ];
#  };
#
#  fcppt = callPackage ../development/libraries/fcppt/default.nix { };
#
#  fcron = callPackage ../tools/system/fcron { };
#
#  fdm = callPackage ../tools/networking/fdm {};
#
#  fgallery = callPackage ../tools/graphics/fgallery {
#    inherit (perlPackages) ImageExifTool JSON;
#  };
#
#  flannel = pkgs.goPackages.flannel.bin // { outputs = [ "bin" ]; };
#
#  flashbench = callPackage ../os-specific/linux/flashbench { };
#
#  figlet = callPackage ../tools/misc/figlet { };
#
  file = callPackage ../tools/misc/file { };
#
#  filegive = callPackage ../tools/networking/filegive { };
#
#  fileschanged = callPackage ../tools/misc/fileschanged { };
#
#  finger_bsd = callPackage ../tools/networking/bsd-finger { };
#
#  fio = callPackage ../tools/system/fio { };
#
#  flashtool = callPackage_i686 ../development/mobile/flashtool {
#    platformTools = androidenv.platformTools;
#  };
#
#  flashrom = callPackage ../tools/misc/flashrom { };
#
#  flpsed = callPackage ../applications/editors/flpsed { };
#
#  fluentd = callPackage ../tools/misc/fluentd { };
#
#  flvstreamer = callPackage ../tools/networking/flvstreamer { };
#
#  libbladeRF = callPackage ../development/libraries/libbladeRF { };
#
#  lprof = callPackage ../tools/graphics/lprof { };
#
#  fatresize = callPackage ../tools/filesystems/fatresize {};
#
#  fdk_aac = callPackage ../development/libraries/fdk-aac { };
#
#  flvtool2 = callPackage ../tools/video/flvtool2 { };
#
  fontforge = lowPrio (callPackage ../tools/misc/fontforge { });
#  fontforge-gtk = callPackage ../tools/misc/fontforge {
#    withGTK = true;
#  };
#
#  fontmatrix = callPackage ../applications/graphics/fontmatrix {};
#
#  foremost = callPackage ../tools/system/foremost { };
#
#  forktty = callPackage ../os-specific/linux/forktty {};
#
#  fortune = callPackage ../tools/misc/fortune { };
#
#  fox = callPackage ../development/libraries/fox/default.nix {
#    libpng = libpng12;
#  };
#
#  fox_1_6 = callPackage ../development/libraries/fox/fox-1.6.nix { };
#
#  fping = callPackage ../tools/networking/fping {};
#
#  fprot = callPackage ../tools/security/fprot { };
#
#  fprintd = callPackage ../tools/security/fprintd { };
#
#  fprint_demo = callPackage ../tools/security/fprint_demo { };
#
#  freeipmi = callPackage ../tools/system/freeipmi {};
#
#  freetalk = callPackage ../applications/networking/instant-messengers/freetalk { };
#
#  freetds = callPackage ../development/libraries/freetds { };
#
#  frescobaldi = callPackage ../misc/frescobaldi {};
#
#  frostwire = callPackage ../applications/networking/p2p/frostwire { };
#
#  ftgl = callPackage ../development/libraries/ftgl { };
#
#  ftgl212 = callPackage ../development/libraries/ftgl/2.1.2.nix { };
#
#  ftop = callPackage ../os-specific/linux/ftop { };
#
#  fsfs = callPackage ../tools/filesystems/fsfs { };
#
#  fuseiso = callPackage ../tools/filesystems/fuseiso { };
#
#  fuse-7z-ng = callPackage ../tools/filesystems/fuse-7z-ng { };
#
#  fuse_zip = callPackage ../tools/filesystems/fuse-zip { };
#
#  exfat = callPackage ../tools/filesystems/exfat { };
#
#  uni2ascii = callPackage ../tools/text/uni2ascii { };
#
#  g500-control = callPackage ../tools/misc/g500-control { };
#
#  galculator = callPackage ../applications/misc/galculator {
#    gtk = gtk3;
#  };
#
#  garmin-plugin = callPackage ../applications/misc/garmin-plugin {};
#
#  garmintools = callPackage ../development/libraries/garmintools {};
#
#  gawp = pkgs.goPackages.gawp.bin // { outputs = [ "bin" ]; };
#
#  gbdfed = callPackage ../tools/misc/gbdfed {
#    gtk = gtk2;
#  };
#
#  gdmap = callPackage ../tools/system/gdmap { };
#
#  genext2fs = callPackage ../tools/filesystems/genext2fs { };
#
#  gengetopt = callPackage ../development/tools/misc/gengetopt { };
#
#  getmail = callPackage ../tools/networking/getmail { };
#
#  gftp = callPackage ../tools/networking/gftp { };
#
#  ggobi = callPackage ../tools/graphics/ggobi { };
#
#  gibo = callPackage ../tools/misc/gibo { };
#
#  gifsicle = callPackage ../tools/graphics/gifsicle { };
#
#  gitfs = callPackage ../tools/filesystems/gitfs { };
#
#  git-latexdiff = callPackage ../tools/typesetting/git-latexdiff { };
#
  glusterfs = callPackage ../tools/filesystems/glusterfs { };
#
#  glmark2 = callPackage ../tools/graphics/glmark2 { };
#
#  glxinfo = callPackage ../tools/graphics/glxinfo { };
#
#  gmvault = callPackage ../tools/networking/gmvault { };
#
#  gnaural = callPackage ../applications/audio/gnaural { };
#
#  gnokii = callPackage ../tools/misc/gnokii { };
#
#  gnufdisk = callPackage ../tools/system/fdisk {
#    guile = guile_1_8;
#  };
#
  gnulib = callPackage ../development/tools/gnulib { };

#  gnuplot = callPackage ../tools/graphics/gnuplot { qt = qt4; };
#
#  gnuplot_qt = gnuplot.override { withQt = true; };
#
#  # must have AquaTerm installed separately
#  gnuplot_aquaterm = gnuplot.override { aquaterm = true; };
#
#  gnuvd = callPackage ../tools/misc/gnuvd { };
#
#  goaccess = callPackage ../tools/misc/goaccess { };
#
#  go-mtpfs = pkgs.goPackages.mtpfs.bin // { outputs = [ "bin" ]; };
#
#  go-pup = pkgs.goPackages.pup.bin // { outputs = [ "bin" ]; };
#
#  googleAuthenticator = callPackage ../os-specific/linux/google-authenticator { };
#
#  google-cloud-sdk = callPackage ../tools/admin/google-cloud-sdk { };
#
#  google-fonts = callPackage ../data/fonts/google-fonts { };
#
#  gource = callPackage ../applications/version-management/gource { };
#
#  gpart = callPackage ../tools/filesystems/gpart { };
#
#  gparted = callPackage ../tools/misc/gparted { };
#
#  gpodder = callPackage ../applications/audio/gpodder { };
#
  gptfdisk = callPackage ../tools/system/gptfdisk { };
#
#  grafana-old = callPackage ../development/tools/misc/grafana { };
#
#  grafx2 = callPackage ../applications/graphics/grafx2 {};
#
#  grails = callPackage ../development/web/grails { jdk = null; };
#
#  gprof2dot = callPackage ../development/tools/profiling/gprof2dot {
#    # Using pypy provides significant performance improvements (~2x)
#    pythonPackages = pypyPackages;
#  };
#
#  grin = callPackage ../tools/text/grin { };
#
#  grive = callPackage ../tools/filesystems/grive {
#    json_c = json-c-0-11; # won't configure with 0.12; others are vulnerable
#  };
#
  groff = callPackage ../tools/text/groff {
    ghostscript = null;
  };

#  grub = callPackage_i686 ../tools/misc/grub {
#    buggyBiosCDSupport = config.grub.buggyBiosCDSupport or true;
#  };
#
#  trustedGrub = callPackage_i686 ../tools/misc/grub/trusted.nix { };
#
#  trustedGrub-for-HP = callPackage_i686 ../tools/misc/grub/trusted.nix { for_HP_laptop = true; };

  grub2 = callPackage ../tools/misc/grub/2.0x.nix { };

  grub2_efi = callPackageAlias "grub2" {
    efiSupport = true;
  };

#  grub4dos = callPackage ../tools/misc/grub4dos {
#    stdenv = pkgs.stdenv_32bit;
#  };
#
#  sbsigntool = callPackage ../tools/security/sbsigntool { };
#
#  gsmartcontrol = callPackage ../tools/misc/gsmartcontrol {
#    inherit (gnome) libglademm;
#  };
#
#  gt5 = callPackage ../tools/system/gt5 { };
#
  gtest = callPackage ../development/libraries/gtest {};
#  gmock = callPackage ../development/libraries/gmock {};
#
#  gtkdatabox = callPackage ../development/libraries/gtkdatabox {};
#
#  gtklick = callPackage ../applications/audio/gtklick {};
#
#  gtdialog = callPackage ../development/libraries/gtdialog {};
#
#  gtkgnutella = callPackage ../tools/networking/p2p/gtk-gnutella { };
#
#  gtkvnc = callPackage ../tools/admin/gtk-vnc {};
#
#  gtmess = callPackage ../applications/networking/instant-messengers/gtmess { };
#
  gummiboot = callPackage ../tools/misc/gummiboot { };
#
#  gup = callPackage ../development/tools/build-managers/gup {};
#
#  gupnp-tools = callPackage ../tools/networking/gupnp-tools {};
#
#  gvpe = callPackage ../tools/networking/gvpe { };
#
#  gvolicon = callPackage ../tools/audio/gvolicon {};
#
#  gzrt = callPackage ../tools/compression/gzrt { };
#
#  partclone = callPackage ../tools/backup/partclone { };
#
#  partimage = callPackage ../tools/backup/partimage { };
#
#  pgf_graphics = callPackage ../tools/graphics/pgf { };
#
#  pigz = callPackage ../tools/compression/pigz { };
#
#  pixz = callPackage ../tools/compression/pixz { };
#
#  pxz = callPackage ../tools/compression/pxz { };
#
#  hans = callPackage ../tools/networking/hans { };
#
#  haproxy = callPackage ../tools/networking/haproxy { };
#
#  haveged = callPackage ../tools/security/haveged { };
#
#  hardlink = callPackage ../tools/system/hardlink { };
#
#  hashcat = callPackage ../tools/security/hashcat { };
#
  hal-flash = callPackage ../os-specific/linux/hal-flash { };
#
#  halibut = callPackage ../tools/typesetting/halibut { };
#
#  hddtemp = callPackage ../tools/misc/hddtemp { };
#
#  hdf5 = callPackage ../tools/misc/hdf5 {
#    gfortran = null;
#    szip = null;
#    mpi = null;
#  };
#
#  hdf5-mpi = appendToName "mpi" (hdf5.override {
#    szip = null;
#    mpi = pkgs.openmpi;
#  });
#
#  hdf5-cpp = appendToName "cpp" (hdf5.override {
#    cpp = true;
#  });
#
#  hdf5-fortran = appendToName "fortran" (hdf5.override {
#    inherit gfortran;
#  });
#
#  heimdall = callPackage ../tools/misc/heimdall { };
#
#  hevea = callPackage ../tools/typesetting/hevea { };
#
#  homesick = callPackage ../tools/misc/homesick { };
#
#  honcho = callPackage ../tools/system/honcho { };
#
#  horst = callPackage ../tools/networking/horst { };
#
#  host = callPackage ../tools/networking/host { };
#
#  hping = callPackage ../tools/networking/hping { };
#
#  httpie = callPackage ../tools/networking/httpie { };
#
#  httping = callPackage ../tools/networking/httping {};
#
#  httpfs2 = callPackage ../tools/filesystems/httpfs { };
#
#  httptunnel = callPackage ../tools/networking/httptunnel { };
#
#  hubicfuse = callPackage ../tools/filesystems/hubicfuse { };
#
#  hwinfo = callPackage ../tools/system/hwinfo { };
#
#  i2c-tools = callPackage ../os-specific/linux/i2c-tools { };
#
#  i2p = callPackage ../tools/networking/i2p {};
#
#  i2pd = callPackage ../tools/networking/i2pd {};
#
#  icecast = callPackage ../servers/icecast { };
#
#  darkice = callPackage ../tools/audio/darkice { };
#
#  icoutils = callPackage ../tools/graphics/icoutils { };
#
#  idutils = callPackage ../tools/misc/idutils { };
#
#  idle3tools = callPackage ../tools/system/idle3tools { };
#
  iftop = callPackage ../tools/networking/iftop { };
#
#  ifuse = callPackage ../tools/filesystems/ifuse/default.nix { };
#
#  ihaskell = callPackage ../development/tools/haskell/ihaskell/wrapper.nix {
#    inherit (haskellPackages) ihaskell ghcWithPackages;
#
#    ipython = python.buildEnv.override {
#      extraLibs = with pythonPackages; [ ipython ipykernel jupyter_client notebook ];
#    };
#
#    packages = config.ihaskell.packages or (self: []);
#  };
#
#  imapproxy = callPackage ../tools/networking/imapproxy { };
#
#  imapsync = callPackage ../tools/networking/imapsync { };
#
#  imgur-screenshot = callPackage ../tools/graphics/imgur-screenshot { };
#
#  imgurbash = callPackage ../tools/graphics/imgurbash { };
#
#  inadyn = callPackage ../tools/networking/inadyn { };
#
#  inetutils = callPackage ../tools/networking/inetutils { };
#
#  innoextract = callPackage ../tools/archivers/innoextract { };
#
#  ioping = callPackage ../tools/system/ioping { };
#
#  iops = callPackage ../tools/system/iops { };
#
#  iodine = callPackage ../tools/networking/iodine { };
#
#  ip2location = callPackage ../tools/networking/ip2location { };
#
#  ipad_charge = callPackage ../tools/misc/ipad_charge { };
#
  iperf2 = callPackage ../tools/networking/iperf/2.nix { };
  iperf3 = callPackage ../tools/networking/iperf/3.nix { };
  iperf = callPackageAlias "iperf3" { };

  ipfs = pkgs.goPackages.ipfs.bin // { outputs = [ "bin" ]; };

  ipmitool = callPackage ../tools/system/ipmitool {
    static = false;
  };

  ipmiutil = callPackage ../tools/system/ipmiutil {};

  ipmiview = callPackage ../applications/misc/ipmiview {};
#
#  ipcalc = callPackage ../tools/networking/ipcalc {};
#
#  ipv6calc = callPackage ../tools/networking/ipv6calc {};
#
#  ipxe = callPackage ../tools/misc/ipxe { };
#
#  ised = callPackage ../tools/misc/ised {};
#
#  isync = callPackage ../tools/networking/isync { };
#  isyncUnstable = callPackage ../tools/networking/isync/unstable.nix { };
#
#  jaaa = callPackage ../applications/audio/jaaa { };
#
#  jd-gui = callPackage_i686 ../tools/security/jd-gui { };
#
#  jdiskreport = callPackage ../tools/misc/jdiskreport { };
#
#  jekyll = callPackage ../applications/misc/jekyll { };
#
#  jfsutils = callPackage ../tools/filesystems/jfsutils { };
#
#  jhead = callPackage ../tools/graphics/jhead { };
#
#  jing = callPackage ../tools/text/xml/jing { };
#
#  jmtpfs = callPackage ../tools/filesystems/jmtpfs { };
#
#  jnettop = callPackage ../tools/networking/jnettop { };
#
#  john = callPackage ../tools/security/john { };
#
#  jp2a = callPackage ../applications/misc/jp2a { };
#
#  jpegoptim = callPackage ../applications/graphics/jpegoptim { };
#
#  jq = callPackage ../development/tools/jq {};
#
#  jscoverage = callPackage ../development/tools/misc/jscoverage { };
#
#  jwhois = callPackage ../tools/networking/jwhois { };
#
#  k2pdfopt = callPackage ../applications/misc/k2pdfopt { };
#
#  kazam = callPackage ../applications/video/kazam { };
#
#  kalibrate-rtl = callPackage ../tools/misc/kalibrate-rtl { };
#
#  kdbplus = callPackage_i686 ../applications/misc/kdbplus { };
#
  keepalived = callPackage ../tools/networking/keepalived { };
#
  kexectools = callPackage ../os-specific/linux/kexectools { };
#
#  keybase = callPackage ../applications/misc/keybase { };
#
#  keychain = callPackage ../tools/misc/keychain { };
#
#  kibana = callPackage ../development/tools/misc/kibana { };
#
#  kismet = callPackage ../applications/networking/sniffers/kismet { };
#
#  klick = callPackage ../applications/audio/klick { };
#
#  knockknock = callPackage ../tools/security/knockknock { };
#
#  kpcli = callPackage ../tools/security/kpcli { };
#
#  kst = qt5.callPackage ../tools/graphics/kst { gsl = gsl_1; };
#
#  leocad = callPackage ../applications/graphics/leocad { };
#
  less = callPackage ../tools/misc/less { };
#
#  liquidsoap = callPackage ../tools/audio/liquidsoap/full.nix { };
#
#  lnav = callPackage ../tools/misc/lnav { };
#
#  lockfileProgs = callPackage ../tools/misc/lockfile-progs { };
#
#  logstash = callPackage ../tools/misc/logstash { };
#
#  logstash-contrib = callPackage ../tools/misc/logstash/contrib.nix { };
#
#  logstash-forwarder = callPackage ../tools/misc/logstash-forwarder { };
#
#  lolcat = callPackage ../tools/misc/lolcat { };
#
#  lsdvd = callPackage ../tools/cd-dvd/lsdvd {};
#
#  lsyncd = callPackage ../applications/networking/sync/lsyncd {
#    lua = lua5_2_compat;
#  };
#
#  kippo = callPackage ../servers/kippo { };
#
#  kzipmix = callPackage_i686 ../tools/compression/kzipmix { };
#
#  makebootfat = callPackage ../tools/misc/makebootfat { };
#
#  matrix-synapse = callPackage ../servers/matrix-synapse { };
#
#  memtester = callPackage ../tools/system/memtester { };
#
#  minidlna = callPackage ../tools/networking/minidlna { };
#
#  minisign = callPackage ../tools/security/minisign { };
#
#  mmv = callPackage ../tools/misc/mmv { };
#
#  morituri = callPackage ../applications/audio/morituri { };
#
  most = callPackage ../tools/misc/most { };
#
#  mkcast = callPackage ../applications/video/mkcast { };
#
#  multitail = callPackage ../tools/misc/multitail { };
#
#  netperf = callPackage ../applications/networking/netperf { };
#
#  netsniff-ng = callPackage ../tools/networking/netsniff-ng { };
#
#  ninka = callPackage ../development/tools/misc/ninka { };
#
#  nodejs-5_x = callPackage ../development/web/nodejs/v5.nix { };
#
#  nodejs-4_x = callPackage ../development/web/nodejs/v4.nix { };
#
#  nodejs-0_10 = callPackage ../development/web/nodejs/v0_10.nix { };
#
#  nodejs = nodejs-5_x;
#
#  nodePackages_5_x = callPackage ./node-packages.nix { self = nodePackages_5_x; nodejs = nodejs-5_x; };
#
#  nodePackages_4_x = callPackage ./node-packages.nix { self = nodePackages_4_x; nodejs = nodejs-4_x; };
#
#  nodePackages_0_10 = callPackage ./node-packages.nix { self = nodePackages_0_10; nodejs = nodejs-0_10; };
#
#  nodePackages = nodePackages_5_x;
#
  nomad = pkgs.goPackages.nomad.bin // { outputs = [ "bin" ]; };

#  npm2nix = nodePackages.npm2nix;
#
#  ldapvi = callPackage ../tools/misc/ldapvi { };
#
  ldns = callPackage ../development/libraries/ldns { };
#
#  leafpad = callPackage ../applications/editors/leafpad { };
#
#  leela = callPackage ../tools/graphics/leela { };
#
#  lftp = callPackage ../tools/networking/lftp { };
#
  libconfig = callPackage ../development/libraries/libconfig { };
#
#  libcmis = callPackage ../development/libraries/libcmis { };
#
#  libee = callPackage ../development/libraries/libee { };
#
#  libestr = callPackage ../development/libraries/libestr { };
#
  libevdev = callPackage ../development/libraries/libevdev { };
#
#  libevhtp = callPackage ../development/libraries/libevhtp { };
#
  liboauth = callPackage ../development/libraries/liboauth { };
#
#  libsrs2 = callPackage ../development/libraries/libsrs2 { };
#
#  libtermkey = callPackage ../development/libraries/libtermkey { };
#
  libshout = callPackage ../development/libraries/libshout { };
#
#  libqb = callPackage ../development/libraries/libqb { };
#
  libqmi = callPackage ../development/libraries/libqmi { };

  libmbim = callPackage ../development/libraries/libmbim { };
#
#  libmongo-client = callPackage ../development/libraries/libmongo-client { };
#
#  libiberty = callPackage ../development/libraries/libiberty { };
#
  libibverbs = callPackage ../development/libraries/libibverbs { };
#
#  libxcomp = callPackage ../development/libraries/libxcomp { };
#
#  libx86emu = callPackage ../development/libraries/libx86emu { };
#
  librdmacm = callPackage ../development/libraries/librdmacm { };
#
#  libwebsockets = callPackage ../development/libraries/libwebsockets { };
#
#  limesurvey = callPackage ../servers/limesurvey { };
#
#  logcheck = callPackage ../tools/system/logcheck {
#    inherit (perlPackages) mimeConstruct;
#  };
#
#  logkeys = callPackage ../tools/security/logkeys { };
#
#  logrotate = callPackage ../tools/system/logrotate { };
#
#  logstalgia = callPackage ../tools/graphics/logstalgia {};
#
#  longview = callPackage ../servers/monitoring/longview { };
#
#  lout = callPackage ../tools/typesetting/lout { };
#
#  lr = callPackage ../tools/system/lr { };
#
#  lrzip = callPackage ../tools/compression/lrzip { };
#
#  # lsh installs `bin/nettle-lfib-stream' and so does Nettle.  Give the
#  # former a lower priority than Nettle.
#  lsh = lowPrio (callPackage ../tools/networking/lsh { });
#
#  lshw = callPackage ../tools/system/lshw { };
#
#  lxc = callPackage ../os-specific/linux/lxc { };
#  lxd = pkgs.goPackages.lxd.bin // { outputs = [ "bin" ]; };
#
#  lzop = callPackage ../tools/compression/lzop { };
#
#  macchanger = callPackage ../os-specific/linux/macchanger { };
#
#  mailcheck = callPackage ../applications/networking/mailreaders/mailcheck { };
#
#  maildrop = callPackage ../tools/networking/maildrop { };
#
#  mailnag = callPackage ../applications/networking/mailreaders/mailnag { };
#
#  mailsend = callPackage ../tools/networking/mailsend { };
#
#  mailpile = callPackage ../applications/networking/mailreaders/mailpile { };
#
#  mailutils = callPackage ../tools/networking/mailutils {
#    guile = guile_1_8;
#  };
#
#  email = callPackage ../tools/networking/email { };
#
#  maim = callPackage ../tools/graphics/maim {};
#
#  mairix = callPackage ../tools/text/mairix { };
#
#  makemkv = callPackage ../applications/video/makemkv { };
#
  man = callPackage ../tools/misc/man { };

  man_db = callPackage ../tools/misc/man-db { };
#
#  mawk = callPackage ../tools/text/mawk { };
#
#  mbox = callPackage ../tools/security/mbox { };
#
#  mbuffer = callPackage ../tools/misc/mbuffer { };
#
#  memtest86 = callPackage ../tools/misc/memtest86 { };
#
  memtest86plus = callPackage ../tools/misc/memtest86+ { };
#
#  meo = callPackage ../tools/security/meo {
#    boost = boost155;
#  };
#
#  mc = callPackage ../tools/misc/mc { };
#
#  mcabber = callPackage ../applications/networking/instant-messengers/mcabber { };
#
#  mcron = callPackage ../tools/system/mcron {
#    guile = guile_1_8;
#  };
#
#  mdbtools = callPackage ../tools/misc/mdbtools { };
#
#  mdbtools_git = callPackage ../tools/misc/mdbtools/git.nix {
#    inherit (gnome) scrollkeeper;
#  };
#
#  mdp = callPackage ../applications/misc/mdp { };
#
#  mednafen = callPackage ../misc/emulators/mednafen { };
#
#  mednafen-server = callPackage ../misc/emulators/mednafen/server.nix { };
#
#  megacli = callPackage ../tools/misc/megacli { };
#
#  megatools = callPackage ../tools/networking/megatools { };
#
#  mfcuk = callPackage ../tools/security/mfcuk { };
#
#  mfoc = callPackage ../tools/security/mfoc { };
#
#  mgba = qt5.callPackage ../misc/emulators/mgba { };
#
#  minissdpd = callPackage ../tools/networking/minissdpd { };
#
#  miniupnpc = callPackage ../tools/networking/miniupnpc { };
#
#  miniupnpd = callPackage ../tools/networking/miniupnpd { };
#
#  miniball = callPackage ../development/libraries/miniball { };
#
#  minixml = callPackage ../development/libraries/minixml { };
#
#  mjpegtools = callPackage ../tools/video/mjpegtools { };
#
#  mkcue = callPackage ../tools/cd-dvd/mkcue { };
#
#  mkpasswd = callPackage ../tools/security/mkpasswd { };
#
#  mkrand = callPackage ../tools/security/mkrand { };
#
#  mktemp = callPackage ../tools/security/mktemp { };
#
#  mktorrent = callPackage ../tools/misc/mktorrent { };
#
  modemmanager = callPackage ../tools/networking/modemmanager {};
#
#  modsecurity_standalone = callPackage ../tools/security/modsecurity { };
#
#  monit = callPackage ../tools/system/monit { };
#
#  moreutils = callPackage ../tools/misc/moreutils {
#    inherit (perlPackages) IPCRun TimeDate TimeDuration;
#    docbook-xsl = docbook_xsl;
#  };
#
  mosh = callPackage ../tools/networking/mosh { };
#
#  motuclient = python27Packages.motuclient;
#
#  mpage = callPackage ../tools/text/mpage { };
#
#  mpw = callPackage ../tools/security/mpw { };
#
#  mr = callPackage ../applications/version-management/mr { };
#
#  mrtg = callPackage ../tools/misc/mrtg { };
#
#  mscgen = callPackage ../tools/graphics/mscgen { };
#
#  msf = callPackage ../tools/security/metasploit { };
#
  ms-sys = callPackage ../tools/misc/ms-sys { };
#
#  mtdutils = callPackage ../tools/filesystems/mtdutils { };
#
  mtools = callPackage ../tools/filesystems/mtools { };
#
  mtr = callPackage ../tools/networking/mtr {};
#
#  multitran = recurseIntoAttrs (let callPackage = newScope pkgs.multitran; in rec {
#    multitrandata = callPackage ../tools/text/multitran/data { };
#
#    libbtree = callPackage ../tools/text/multitran/libbtree { };
#
#    libmtsupport = callPackage ../tools/text/multitran/libmtsupport { };
#
#    libfacet = callPackage ../tools/text/multitran/libfacet { };
#
#    libmtquery = callPackage ../tools/text/multitran/libmtquery { };
#
#    mtutils = callPackage ../tools/text/multitran/mtutils { };
#  });
#
#  munge = callPackage ../tools/security/munge { };
#
#  mysql2pgsql = callPackage ../tools/misc/mysql2pgsql { };
#
#  nabi = callPackage ../tools/inputmethods/nabi { };
#
#  namazu = callPackage ../tools/text/namazu { };
#
#  nasty = callPackage ../tools/security/nasty { };
#
#  nbd = callPackage ../tools/networking/nbd { };
#
#  ndjbdns = callPackage ../tools/networking/ndjbdns { };
#
#  nestopia = callPackage ../misc/emulators/nestopia { };
#
#  netatalk = callPackage ../tools/filesystems/netatalk { };
#
#  netcdf = callPackage ../development/libraries/netcdf { };
#
#  netcdfcxx4 = callPackage ../development/libraries/netcdf-cxx4 { };
#
#  nc6 = callPackage ../tools/networking/nc6 { };
#
#  ncat = callPackage ../tools/networking/ncat { };
#
#  ncftp = callPackage ../tools/networking/ncftp { };
#
#  ncompress = callPackage ../tools/compression/ncompress { };
#
#  ndisc6 = callPackage ../tools/networking/ndisc6 { };
#
#  netboot = callPackage ../tools/networking/netboot {};
#
  netcat = callPackage ../tools/networking/netcat { };
#
#  netcat-openbsd = callPackage ../tools/networking/netcat-openbsd { };
#
#  nethogs = callPackage ../tools/networking/nethogs { };
#
#  netkittftp = callPackage ../tools/networking/netkit/tftp { };
#
#  netpbm = callPackage ../tools/graphics/netpbm { };
#
#  netrw = callPackage ../tools/networking/netrw { };
#
#  netselect = callPackage ../tools/networking/netselect { };
#
#  newsbeuter = callPackage ../applications/networking/feedreaders/newsbeuter { };
#
#  newsbeuter-dev = callPackage ../applications/networking/feedreaders/newsbeuter/dev.nix { };
#
#  ngrep = callPackage ../tools/networking/ngrep { };
#
#  ngrok = pkgs.goPackages.ngrok.bin // { outputs = [ "bin" ]; };
#
#  noip = callPackage ../tools/networking/noip { };
#
#  mpack = callPackage ../tools/networking/mpack { };
#
#  pa_applet = callPackage ../tools/audio/pa-applet { };
#
#  pasystray = callPackage ../tools/audio/pasystray { };
#
#  pnmixer = callPackage ../tools/audio/pnmixer { };
#
#  pwsafe = callPackage ../applications/misc/pwsafe {
#    wxGTK = wxGTK30;
#  };
#
#  nifskope = callPackage ../tools/graphics/nifskope { };
#
#  nilfs-utils = callPackage ../tools/filesystems/nilfs-utils {};
#  nilfs_utils = nilfs-utils;
#
#  nitrogen = callPackage ../tools/X11/nitrogen {};
#
#  nkf = callPackage ../tools/text/nkf {};
#
#  nlopt = callPackage ../development/libraries/nlopt {};
#
  npapi_sdk = callPackage ../development/libraries/npapi-sdk { };

  npth = callPackage ../development/libraries/npth { };

#  notify-osd = callPackage ../applications/misc/notify-osd { };
#
#  nox = callPackage ../tools/package-management/nox {
#    pythonPackages = python3Packages;
#  };
#
#  nq = callPackage ../tools/system/nq { };
#
#  nsjail = callPackage ../tools/security/nsjail {};
#
#  nss_pam_ldapd = callPackage ../tools/networking/nss-pam-ldapd {};
#
  ntfs3g = callPackage ../tools/filesystems/ntfs-3g { };

  # ntfsprogs are merged into ntfs-3g
  ntfsprogs = pkgs.ntfs3g;
#
#  ntopng = callPackage ../tools/networking/ntopng { };
#
  ntp = callPackage ../tools/networking/ntp { };
#
#  numdiff = callPackage ../tools/text/numdiff { };
#
#  numlockx = callPackage ../tools/X11/numlockx { };
#
#  nssmdns = callPackage ../tools/networking/nss-mdns { };
#
#  nwdiag = pythonPackages.nwdiag;
#
#  nylon = callPackage ../tools/networking/nylon { };
#
#  nxproxy = callPackage ../tools/admin/nxproxy { };
#
#  nzbget = callPackage ../tools/networking/nzbget { };
#
#  oathToolkit = callPackage ../tools/security/oath-toolkit { };
#
#  obex_data_server = callPackage ../tools/bluetooth/obex-data-server { };
#
#  obexd = callPackage ../tools/bluetooth/obexd { };
#
#  openfortivpn = callPackage ../tools/networking/openfortivpn { };
#
#  obexfs = callPackage ../tools/bluetooth/obexfs { };
#
#  objconv = callPackage ../development/tools/misc/objconv {};
#
#  obnam = callPackage ../tools/backup/obnam { };
#
#  odpdown = callPackage ../tools/typesetting/odpdown {
#    inherit (pythonPackages) lpod lxml mistune pillow pygments;
#  };
#
#  odt2txt = callPackage ../tools/text/odt2txt { };
#
#  offlineimap = callPackage ../tools/networking/offlineimap {
#    inherit (pythonPackages) sqlite3;
#  };
#
#  opencryptoki = callPackage ../tools/security/opencryptoki { };
#
#  opendbx = callPackage ../development/libraries/opendbx { };
#
#  opendkim = callPackage ../development/libraries/opendkim { };
#
#  openjade = callPackage ../tools/text/sgml/openjade { };
#
  openntpd = callPackage ../tools/networking/openntpd { };
#
#  openntpd_nixos = openntpd.override {
#    privsepUser = "ntp";
#    privsepPath = "/var/empty";
#  };
#
#  openopc = callPackage ../tools/misc/openopc {
#    pythonFull = python27.buildEnv.override {
#      extraLibs = [ python27Packages.pyro3 ];
#    };
#  };
#
  openresolv = callPackage ../tools/networking/openresolv { };

#  opensc = callPackage ../tools/security/opensc { };

  openssh = callPackage ../tools/networking/openssh { };

  openssh_hpn = pkgs.appendToName "with-hpn" (openssh.override { hpnSupport = true; });

  openssh_with_kerberos = pkgs.appendToName "with-kerberos" (openssh.override { withKerberos = true; });

  opensp = callPackage ../tools/text/sgml/opensp { };

  spCompat = callPackage ../tools/text/sgml/opensp/compat.nix { };
#
#  opentracker = callPackage ../applications/networking/p2p/opentracker { };
#
#  opentsdb = callPackage ../tools/misc/opentsdb {};
#
#  openvpn_learnaddress = callPackage ../tools/networking/openvpn/openvpn_learnaddress.nix { };
#
#  update-resolv-conf = callPackage ../tools/networking/openvpn/update-resolv-conf.nix { };
#
#  open-pdf-presenter = callPackage ../applications/misc/open-pdf-presenter { };
#
#  openvswitch = callPackage ../os-specific/linux/openvswitch { };
#
#  optipng = callPackage ../tools/graphics/optipng {
#    libpng = libpng12;
#  };
#
#  oslrd = callPackage ../tools/networking/oslrd { };
#
#  ossec = callPackage ../tools/security/ossec {};
#
#  ostree = callPackage ../tools/misc/ostree { };
#
#  otpw = callPackage ../os-specific/linux/otpw { };
#
#  owncloud = owncloud70;
#
#  inherit (callPackages ../servers/owncloud { })
#    owncloud705
#    owncloud70
#    owncloud80
#    owncloud81
#    owncloud82;
#
#  owncloudclient = callPackage ../applications/networking/owncloud-client { };
#
#  p2pvc = callPackage ../applications/video/p2pvc {};
#
#  packagekit = callPackage ../tools/package-management/packagekit { };
#
#  pal = callPackage ../tools/misc/pal { };
#
#  pandoc = haskell.lib.overrideCabal haskellPackages.pandoc (drv: {
#    configureFlags = drv.configureFlags or [] ++ ["-fembed_data_files"];
#    buildTools = drv.buildTools or [] ++ [haskellPackages.hsb2hs];
#    enableSharedExecutables = false;
#    enableSharedLibraries = false;
#    isLibrary = false;
#    doHaddock = false;
#    postFixup = "rm -rf $out/lib $out/nix-support $out/share";
#  });
#
#  panomatic = callPackage ../tools/graphics/panomatic { };
#
#  pamtester = callPackage ../tools/security/pamtester { };
#
#  paper-gtk-theme = callPackage ../misc/themes/gtk3/paper-gtk-theme { };
#
#  par2cmdline = callPackage ../tools/networking/par2cmdline { };
#
#  parcellite = callPackage ../tools/misc/parcellite { };
#
  patchutils = callPackage ../tools/text/patchutils { };
#
  parted = callPackage ../tools/misc/parted { hurd = null; };
#
#  pitivi = callPackage ../applications/video/pitivi {
#    gst = gst_all_1 //
#      { gst-plugins-bad = gst_all_1.gst-plugins-bad.overrideDerivation
#          (attrs: { nativeBuildInputs = attrs.nativeBuildInputs ++ [ gtk3 ]; });
#      };
#  };
#
#  p0f = callPackage ../tools/security/p0f { };
#
#  pngout = callPackage ../tools/graphics/pngout { };
#
#  hurdPartedCross =
#    if crossSystem != null && crossSystem.config == "i586-pc-gnu"
#    then (makeOverridable
#            ({ hurd }:
#              (parted.override {
#                # Needs the Hurd's libstore.
#                inherit hurd;
#
#                # The Hurd wants a libparted.a.
#                enableStatic = true;
#
#                gettext = null;
#                readline = null;
#                devicemapper = null;
#              }).crossDrv)
#           { hurd = gnu.hurdCrossIntermediate; })
#    else null;
#
#  ipsecTools = callPackage ../os-specific/linux/ipsec-tools { };
#
#  pbzip2 = callPackage ../tools/compression/pbzip2 { };
#
#  pcsctools = callPackage ../tools/security/pcsctools {
#    inherit (perlPackages) pcscperl Glib Gtk2 Pango;
#  };
#
#  pdf2djvu = callPackage ../tools/typesetting/pdf2djvu { };
#
#  pdf2svg = callPackage ../tools/graphics/pdf2svg { };
#
#  pdfjam = callPackage ../tools/typesetting/pdfjam { };
#
#  pdfmod = callPackage ../applications/misc/pdfmod { };
#
#  jbig2enc = callPackage ../tools/graphics/jbig2enc { };
#
#  pdfread = callPackage ../tools/graphics/pdfread {
#    inherit (pythonPackages) pillow;
#  };
#
#  briss = callPackage ../tools/graphics/briss { };
#
#  brickd = callPackage ../servers/brickd { };
#
#  bully = callPackage ../tools/networking/bully { };
#
#  pcapc = callPackage ../tools/networking/pcapc { };
#
#  pdnsd = callPackage ../tools/networking/pdnsd { };
#
#  peco = callPackage ../tools/text/peco { };
#
#  pg_top = callPackage ../tools/misc/pg_top { };
#
#  pdsh = callPackage ../tools/networking/pdsh {
#    rsh = true;          # enable internal rsh implementation
#    ssh = openssh;
#  };
#
#  pfstools = callPackage ../tools/graphics/pfstools { };
#
#  philter = callPackage ../tools/networking/philter { };
#
  pinentry = callPackage ../tools/security/pinentry {
    qt4 = null;
  };
#
#  pinentry_ncurses = pinentry.override {
#    gtk2 = null;
#  };
#
#  pinentry_qt4 = pinentry_ncurses.override {
#    inherit qt4;
#  };
#
#  pinentry_qt5 = qt5.callPackage ../tools/security/pinentry/qt5.nix { };
#
#  pinentry_mac = callPackage ../tools/security/pinentry-mac { };
#
#  pingtcp = callPackage ../tools/networking/pingtcp { };
#
#  pius = callPackage ../tools/security/pius { };
#
#  pk2cmd = callPackage ../tools/misc/pk2cmd { };
#
#  plantuml = callPackage ../tools/misc/plantuml { };
#
#  plan9port = callPackage ../tools/system/plan9port { };
#
#  platformioPackages = callPackage ../development/arduino/platformio { };
#  platformio = platformioPackages.platformio-chrootenv.override {};
#
#  plex = callPackage ../servers/plex { };
#
#  ploticus = callPackage ../tools/graphics/ploticus {
#    libpng = libpng12;
#  };
#
#  plotutils = callPackage ../tools/graphics/plotutils { };
#
#  plowshare = callPackage ../tools/misc/plowshare { };
#
#  pngcheck = callPackage ../tools/graphics/pngcheck { };
#
#  pngnq = callPackage ../tools/graphics/pngnq { };
#
#  pngtoico = callPackage ../tools/graphics/pngtoico {
#    libpng = libpng12;
#  };
#
#  pngquant = callPackage ../tools/graphics/pngquant { };
#
#  podiff = callPackage ../tools/text/podiff { };
#
#  poedit = callPackage ../tools/text/poedit { };
#
#  polipo = callPackage ../servers/polipo { };
#
#  polkit_gnome = callPackage ../tools/security/polkit-gnome { };
#
#  popcorntime = callPackage ../applications/video/popcorntime { nwjs = nwjs_0_12; };
#
#  ponysay = callPackage ../tools/misc/ponysay { };
#
#  popfile = callPackage ../tools/text/popfile { };
#
#  povray = callPackage ../tools/graphics/povray {
#    automake = automake113x; # fails with 14
#  };
#
#  ppl = callPackage ../development/libraries/ppl { };
#
  ppp = callPackage ../tools/networking/ppp { };

  pptp = callPackage ../tools/networking/pptp {};
#
#  prey-bash-client = callPackage ../tools/security/prey { };
#
#  profile-cleaner = callPackage ../tools/misc/profile-cleaner { };
#
#  profile-sync-daemon = callPackage ../tools/misc/profile-sync-daemon { };
#
#  projectm = callPackage ../applications/audio/projectm { };
#
#  proot = callPackage ../tools/system/proot { };
#
#  proxychains = callPackage ../tools/networking/proxychains { };
#
#  proxytunnel = callPackage ../tools/misc/proxytunnel { };
#
#  cntlm = callPackage ../tools/networking/cntlm { };
#
#  pastebinit = callPackage ../tools/misc/pastebinit { };
#
#  polygraph = callPackage ../tools/networking/polygraph { };
#
#  progress = callPackage ../tools/misc/progress { };
#
#  pstoedit = callPackage ../tools/graphics/pstoedit { };
#
#  pv = callPackage ../tools/misc/pv { };
#
#  pwgen = callPackage ../tools/security/pwgen { };
#
#  pwnat = callPackage ../tools/networking/pwnat { };
#
#  pyatspi = callPackage ../development/python-modules/pyatspi { };
#
#  pycangjie = pythonPackages.pycangjie;
#
#  pydb = callPackage ../development/tools/pydb { };
#
#  pystringtemplate = callPackage ../development/python-modules/stringtemplate { };

#  pythonIRClib = pythonPackages.pythonIRClib;
#
#  pythonSexy = callPackage ../development/python-modules/libsexy { };
#
#  pytrainer = callPackage ../applications/misc/pytrainer { };
#
#  remarshal = (callPackage ../development/tools/remarshal { }).bin // { outputs = [ "bin" ]; };
#
#  openmpi = callPackage ../development/libraries/openmpi { };
#
#  qarte = callPackage ../applications/video/qarte {
#    sip = pythonPackages.sip_4_16;
#  };
#
#  ocz-ssd-guru = callPackage ../tools/misc/ocz-ssd-guru { };
#
#  qastools = callPackage ../tools/audio/qastools {
#    qt = qt4;
#  };
#
#  qhull = callPackage ../development/libraries/qhull { };
#
#  qjoypad = callPackage ../tools/misc/qjoypad { };
#
#  qpdf = callPackage ../development/libraries/qpdf { };
#
#  qprint = callPackage ../tools/text/qprint { };
#
#  qscintilla = callPackage ../development/libraries/qscintilla {
#    qt = qt4;
#  };
#
#  qshowdiff = callPackage ../tools/text/qshowdiff { };
#
#  quilt = callPackage ../development/tools/quilt { };
#
#  radamsa = callPackage ../tools/security/radamsa { };
#
#  radvd = callPackage ../tools/networking/radvd { };
#
#  ranger = callPackage ../applications/misc/ranger { };
#
#  rarcrack = callPackage ../tools/security/rarcrack { };
#
#  rawdog = callPackage ../applications/networking/feedreaders/rawdog { };
#
#  read-edid = callPackage ../os-specific/linux/read-edid { };
#
#  redir = callPackage ../tools/networking/redir { };
#
#  redmine = callPackage ../applications/version-management/redmine { };
#
#  reaverwps = callPackage ../tools/networking/reaver-wps {};
#
#  recordmydesktop = callPackage ../applications/video/recordmydesktop { };
#
#  recutils = callPackage ../tools/misc/recutils { };
#
#  recoll = callPackage ../applications/search/recoll { };
#
#  reiser4progs = callPackage ../tools/filesystems/reiser4progs { };
#
#  reiserfsprogs = callPackage ../tools/filesystems/reiserfsprogs { };
#
#  relfs = callPackage ../tools/filesystems/relfs {
#    inherit (gnome) gnome_vfs GConf;
#  };
#
#  remarkjs = callPackage ../development/web/remarkjs { };
#
#  remind = callPackage ../tools/misc/remind { };
#
#  remmina = callPackage ../applications/networking/remote/remmina {};
#
#  renameutils = callPackage ../tools/misc/renameutils { };
#
#  replace = callPackage ../tools/text/replace { };
#
#  reposurgeon = callPackage ../applications/version-management/reposurgeon { };
#
#  reptyr = callPackage ../os-specific/linux/reptyr {};
#
#  rescuetime = callPackage ../applications/misc/rescuetime { };
#
#  rdiff-backup = callPackage ../tools/backup/rdiff-backup { };
#
#  rdfind = callPackage ../tools/filesystems/rdfind { };
#
#  rhash = callPackage ../tools/security/rhash { };
#
#  riemann_c_client = callPackage ../tools/misc/riemann-c-client { };
#  riemann-tools = callPackage ../tools/misc/riemann-tools { };
#
#  ripmime = callPackage ../tools/networking/ripmime {};
#
#  rkflashtool = callPackage ../tools/misc/rkflashtool { };
#
#  rkrlv2 = callPackage ../applications/audio/rkrlv2 {};
#
#  rmlint = callPackage ../tools/misc/rmlint {
#    inherit (pythonPackages) sphinx;
#  };
#
  rng_tools = callPackage ../tools/security/rng-tools { };
#
#  rsnapshot = callPackage ../tools/backup/rsnapshot { };
#
#  rlwrap = callPackage ../tools/misc/rlwrap { };
#
#  rockbox_utility = callPackage ../tools/misc/rockbox-utility { };
#
#  rosegarden = callPackage ../applications/audio/rosegarden { };
#
#  rpPPPoE = callPackage ../tools/networking/rp-pppoe { };
#
  rpm = callPackage ../tools/package-management/rpm { };
#
#  rpmextract = callPackage ../tools/archivers/rpmextract { };
#
#  rrdtool = callPackage ../tools/misc/rrdtool { };
#
#  rsstail = callPackage ../applications/networking/feedreaders/rsstail { };
#
#  rubber = callPackage ../tools/typesetting/rubber { };
#
#  runzip = callPackage ../tools/archivers/runzip { };
#
#  rxp = callPackage ../tools/text/xml/rxp { };
#
#  rzip = callPackage ../tools/compression/rzip { };
#
#  s3backer = callPackage ../tools/filesystems/s3backer { };
#
#  s3fs = callPackage ../tools/filesystems/s3fs { };
#
#  s3cmd = callPackage ../tools/networking/s3cmd { };
#
#  s6Dns = callPackage ../tools/networking/s6-dns { };
#
#  s6LinuxUtils = callPackage ../os-specific/linux/s6-linux-utils { };
#
#  s6Networking = callPackage ../tools/networking/s6-networking { };
#
#  s6PortableUtils = callPackage ../tools/misc/s6-portable-utils { };
#
#  sablotron = callPackage ../tools/text/xml/sablotron { };
#
#  safecopy = callPackage ../tools/system/safecopy { };
#
#  safe-rm = callPackage ../tools/system/safe-rm { };
#
#  salut_a_toi = callPackage ../applications/networking/instant-messengers/salut-a-toi {};
#
#  samplicator = callPackage ../tools/networking/samplicator { };
#
#  scanbd = callPackage ../tools/graphics/scanbd { };
#
#  screen = callPackage ../tools/misc/screen { };
#
#  screen-message = callPackage ../tools/X11/screen-message { };
#
#  screencloud = callPackage ../applications/graphics/screencloud {
#    quazip = qt5.quazip.override { qt = qt4; };
#  };
#
#  scrypt = callPackage ../tools/security/scrypt { };
#
#  sdcv = callPackage ../applications/misc/sdcv { };
#
#  sdl-jstest = callPackage ../tools/misc/sdl-jstest { };
#
#  sec = callPackage ../tools/admin/sec { };
#
#  seccure = callPackage ../tools/security/seccure { };
#
#  setroot = callPackage  ../tools/X11/setroot { };
#
#  setserial = callPackage ../tools/system/setserial { };
#
#  seqdiag = pythonPackages.seqdiag;
#
#  screenfetch = callPackage ../tools/misc/screenfetch { };
#
  sg3_utils = callPackage ../tools/system/sg3_utils { };

#  shotwell = callPackage ../applications/graphics/shotwell { };
#
  shout = callPackage ../applications/networking/irc/shout { };
#
#  shellinabox = callPackage ../servers/shellinabox { };
#
#  sic = callPackage ../applications/networking/irc/sic { };
#
#  siege = callPackage ../tools/networking/siege {};
#
#  sigil = qt5.callPackage ../applications/editors/sigil { };
#
#  # aka., gpg-tools
#  signing-party = callPackage ../tools/security/signing-party { };
#
#  silc_client = callPackage ../applications/networking/instant-messengers/silc-client { };
#
#  silc_server = callPackage ../servers/silc-server { };
#
#  silver-searcher = callPackage ../tools/text/silver-searcher { };
#
#  simplescreenrecorder = callPackage ../applications/video/simplescreenrecorder { };
#
#  skippy-xd = callPackage ../tools/X11/skippy-xd {};
#
#  skydns = pkgs.goPackages.skydns.bin // { outputs = [ "bin" ]; };
#
#  sipcalc = callPackage ../tools/networking/sipcalc { };
#
#  sleuthkit = callPackage ../tools/system/sleuthkit {};
#
#  slimrat = callPackage ../tools/networking/slimrat {
#    inherit (perlPackages) WWWMechanize LWP;
#  };
#
#  slsnif = callPackage ../tools/misc/slsnif { };
#
  smartmontools = callPackage ../tools/system/smartmontools { };
#
#  smbldaptools = callPackage ../tools/networking/smbldaptools {
#    inherit (perlPackages) NetLDAP CryptSmbHash DigestSHA1;
#  };
#
#  smbnetfs = callPackage ../tools/filesystems/smbnetfs {};
#
#  snabbswitch = callPackage ../tools/networking/snabbswitch { } ;
#
#  sng = callPackage ../tools/graphics/sng {
#    libpng = libpng12;
#  };
#
#  snort = callPackage ../applications/networking/ids/snort { };
#
#  solr = callPackage ../servers/search/solr { };
#
#  solvespace = callPackage ../applications/graphics/solvespace { };
#
#  sonata = callPackage ../applications/audio/sonata {
#    inherit (python3Packages) buildPythonPackage python isPy3k dbus pygobject3 mpd2;
#  };
#
#  sparsehash = callPackage ../development/libraries/sparsehash { };
#
#  spiped = callPackage ../tools/networking/spiped { };
#
#  sqliteman = callPackage ../applications/misc/sqliteman { };
#
#  stardict = callPackage ../applications/misc/stardict/stardict.nix {
#    inherit (gnome) libgnomeui scrollkeeper;
#  };
#
#  stdman = callPackage ../data/documentation/stdman { };
#
#  storebrowse = callPackage ../tools/system/storebrowse { };
#
#  fusesmb = callPackage ../tools/filesystems/fusesmb { samba = samba3; };
#
  sl = callPackage ../tools/misc/sl { };
#
#  socat = callPackage ../tools/networking/socat { };
#
#  socat2pre = lowPrio (callPackage ../tools/networking/socat/2.x.nix { });
#
#  solaar = callPackage ../applications/misc/solaar {};
#
#  sourceHighlight = callPackage ../tools/text/source-highlight { };
#
#  spaceFM = callPackage ../applications/misc/spacefm { };
#
  squashfs-tools = callPackage ../tools/filesystems/squashfs { };
#
#  sshfsFuse = callPackage ../tools/filesystems/sshfs-fuse { };
#
#  sshuttle = callPackage ../tools/security/sshuttle { };
#
#  sstp = callPackage ../tools/networking/sstp {};
#
  sudo = callPackage ../tools/security/sudo { };
#
#  suidChroot = callPackage ../tools/system/suid-chroot { };
#
#  sundtek = callPackage ../misc/drivers/sundtek { };
#
#  sunxi-tools = callPackage ../development/tools/sunxi-tools { };
#
#  super = callPackage ../tools/security/super { };
#
#  supertux-editor = callPackage ../applications/editors/supertux-editor { };
#
#  super-user-spark = haskellPackages.callPackage ../applications/misc/super_user_spark { };
#
#  ssdeep = callPackage ../tools/security/ssdeep { };
#
#  sshpass = callPackage ../tools/networking/sshpass { };
#
#  sslscan = callPackage ../tools/security/sslscan { };
#
#  sslmate = callPackage ../development/tools/sslmate { };
#
#  ssmtp = callPackage ../tools/networking/ssmtp {
#    tlsSupport = true;
#  };
#
#  ssss = callPackage ../tools/security/ssss { };
#
#  stress = callPackage ../tools/system/stress { };
#
#  stress-ng = callPackage ../tools/system/stress-ng { };
#
#  stoken = callPackage ../tools/security/stoken {
#    withGTK3 = config.stoken.withGTK3 or true;
#  };
#
#  storeBackup = callPackage ../tools/backup/store-backup { };
#
#  stow = callPackage ../tools/misc/stow { };
#
#  stun = callPackage ../tools/networking/stun { };
#
#  stunnel = callPackage ../tools/networking/stunnel { };
#
  strongswan = callPackage ../tools/networking/strongswan { };
#
#  strongswanTNC = callPackage ../tools/networking/strongswan { enableTNC=true; };
#
#  subsonic = callPackage ../servers/misc/subsonic { };
#
#  surfraw = callPackage ../tools/networking/surfraw { };
#
#  swec = callPackage ../tools/networking/swec {
#    inherit (perlPackages) LWP URI HTMLParser HTTPServerSimple Parent;
#  };
#
#  svnfs = callPackage ../tools/filesystems/svnfs { };
#
#  svtplay-dl = callPackage ../tools/misc/svtplay-dl {
#    inherit (pythonPackages) nose mock requests2;
#  };
#
#  sysbench = callPackage ../development/tools/misc/sysbench {};
#
#  system-config-printer = callPackage ../tools/misc/system-config-printer { };
#
#  sitecopy = callPackage ../tools/networking/sitecopy { };
#
#  stricat = callPackage ../tools/security/stricat { };
#
#  privoxy = callPackage ../tools/networking/privoxy { };
#
#  swaks = callPackage ../tools/networking/swaks { };
#
#  swiften = callPackage ../development/libraries/swiften { };
#
#  t = callPackage ../tools/misc/t { };
#
#  t1utils = callPackage ../tools/misc/t1utils { };
#
#  talkfilters = callPackage ../misc/talkfilters {};
#
#  tarsnap = callPackage ../tools/backup/tarsnap { };
#
#  tcpcrypt = callPackage ../tools/security/tcpcrypt { };
#
#  tboot = callPackage ../tools/security/tboot { };
#
  tcpdump = callPackage ../tools/networking/tcpdump { };
#
#  tcpflow = callPackage ../tools/networking/tcpflow { };
#
#  teamviewer = callPackage ../applications/networking/remote/teamviewer {
#    stdenv = pkgs.stdenv_32bit;
#  };
#
#  telnet = callPackage ../tools/networking/telnet { };
#
#  texmacs = callPackage ../applications/editors/texmacs {
#    tex = texlive.combined.scheme-small;
#    extraFonts = true;
#  };
#
#  texmaker = callPackage ../applications/editors/texmaker { };
#
#  texstudio = callPackage ../applications/editors/texstudio { };
#
#  textadept = callPackage ../applications/editors/textadept { };
#
#  thc-hydra = callPackage ../tools/security/thc-hydra { };
#
#  tiled = qt5.callPackage ../applications/editors/tiled { };
#
#  timemachine = callPackage ../applications/audio/timemachine { };
#
  tinc = callPackage ../tools/networking/tinc { };
#
  tinc_pre = callPackage ../tools/networking/tinc/pre.nix { };
#
#  tiny8086 = callPackage ../applications/virtualization/8086tiny { };
#
#  tlsdate = callPackage ../tools/networking/tlsdate { };
#
#  tldr = callPackage ../tools/misc/tldr { };
#
#  tmate = callPackage ../tools/misc/tmate { };
#
#  tmpwatch = callPackage ../tools/misc/tmpwatch  { };
#
  tmux = callPackage ../tools/misc/tmux { };
#
#  tmux-cssh = callPackage ../tools/misc/tmux-cssh { };
#
#  tmuxinator = callPackage ../tools/misc/tmuxinator { };
#
#  tmin = callPackage ../tools/security/tmin { };
#
#  tmsu = callPackage ../tools/filesystems/tmsu { };
#
#  toilet = callPackage ../tools/misc/toilet { };
#
#  tor = callPackage ../tools/security/tor { };
#
#  tor-arm = callPackage ../tools/security/tor/tor-arm.nix { };
#
#  torbutton = callPackage ../tools/security/torbutton { };
#
#  torbrowser = callPackage ../tools/security/tor/torbrowser.nix {
#    stdenv = overrideCC pkgs.stdenv gcc5;
#  };
#
#  touchegg = callPackage ../tools/inputmethods/touchegg { };
#
#  torsocks = callPackage ../tools/security/tor/torsocks.nix { };
#
#  tpmmanager = callPackage ../applications/misc/tpmmanager { };
#
#  tpm-quote-tools = callPackage ../tools/security/tpm-quote-tools { };
#
#  tpm-tools = callPackage ../tools/security/tpm-tools { };
#
#  tpm-luks = callPackage ../tools/security/tpm-luks { };
#
#  tthsum = callPackage ../applications/misc/tthsum { };
#
#  chaps = callPackage ../tools/security/chaps { };
#
#  trace-cmd = callPackage ../os-specific/linux/trace-cmd { };
#
#  traceroute = callPackage ../tools/networking/traceroute { };
#
#  tracebox = callPackage ../tools/networking/tracebox { };
#
#  trash-cli = callPackage ../tools/misc/trash-cli { };
#
#  trickle = callPackage ../tools/networking/trickle {};
#
  trousers = callPackage ../tools/security/trousers { };
#
#  omapd = callPackage ../tools/security/omapd { };
#
#  ttf2pt1 = callPackage ../tools/misc/ttf2pt1 { };
#
#  ttfautohint = callPackage ../tools/misc/ttfautohint { };
#
#  tty-clock = callPackage ../tools/misc/tty-clock { };
#
#  ttyrec = callPackage ../tools/misc/ttyrec { };
#
#  ttysnoop = callPackage ../os-specific/linux/ttysnoop {};
#
#  ttylog = callPackage ../tools/misc/ttylog { };
#
#  twitterBootstrap = callPackage ../development/web/twitter-bootstrap {};
#
#  txt2man = callPackage ../tools/misc/txt2man { };
#
#  txt2tags = callPackage ../tools/text/txt2tags { };
#
#  txtw = callPackage ../tools/misc/txtw { };
#
#  u9fs = callPackage ../servers/u9fs { };
#
#  ucl = callPackage ../development/libraries/ucl { };
#
#  ucspi-tcp = callPackage ../tools/networking/ucspi-tcp { };
#
#  udftools = callPackage ../tools/filesystems/udftools {};
#
#  udptunnel = callPackage ../tools/networking/udptunnel { };
#
#  ufraw = callPackage ../applications/graphics/ufraw { };
#
#  umlet = callPackage ../tools/misc/umlet { };
#
#  unetbootin = callPackage ../tools/cd-dvd/unetbootin { };
#
#  unfs3 = callPackage ../servers/unfs3 { };
#
#  unoconv = callPackage ../tools/text/unoconv { };
#
#  unrtf = callPackage ../tools/text/unrtf { };
#
#  untex = callPackage ../tools/text/untex { };
#
#  upx = callPackage ../tools/compression/upx { };
#
#  uriparser = callPackage ../development/libraries/uriparser {};
#
#  urlview = callPackage ../applications/misc/urlview {};
#
#  uwsgi = callPackage ../servers/uwsgi {
#    plugins = [];
#  };
#
#  vacuum = callPackage ../applications/networking/instant-messengers/vacuum {};
#
#  volatility = callPackage ../tools/security/volatility { };
#
#  vidalia = callPackage ../tools/security/vidalia { };
#
#  vbetool = callPackage ../tools/system/vbetool { };
#
#  vde2 = callPackage ../tools/networking/vde2 { };
#
#  vboot_reference = callPackage ../tools/system/vboot_reference { };
#
#  vcsh = callPackage ../applications/version-management/vcsh { };
#
#  verilator = callPackage ../applications/science/electronics/verilator {};
#
#  verilog = callPackage ../applications/science/electronics/verilog {};
#
#  vfdecrypt = callPackage ../tools/misc/vfdecrypt { };
#
#  vifm = callPackage ../applications/misc/vifm { };
#
#  viking = callPackage ../applications/misc/viking {
#    inherit (gnome) scrollkeeper;
#  };
#
#  vit = callPackage ../applications/misc/vit { };
#
#  vnc2flv = callPackage ../tools/video/vnc2flv {};
#
#  vncrec = callPackage ../tools/video/vncrec { };
#
#  vobcopy = callPackage ../tools/cd-dvd/vobcopy { };
#
  vobsub2srt = callPackage ../tools/cd-dvd/vobsub2srt { };
#
#  vorbisgain = callPackage ../tools/misc/vorbisgain { };
#
  vpnc = callPackage ../tools/networking/vpnc { };

  openconnect = callPackageAlias "openconnect_openssl" { };

  openconnect_openssl = callPackage ../tools/networking/openconnect.nix {
    gnutls = null;
  };
#
#  openconnect_gnutls = lowPrio (openconnect.override {
#    openssl = null;
#    gnutls = gnutls;
#  });
#
#  vtun = callPackage ../tools/networking/vtun { };
#
#  weather = callPackage ../applications/misc/weather { };
#
#  wal_e = callPackage ../tools/backup/wal-e { };
#
#  watchman = callPackage ../development/tools/watchman { };
#
#  wbox = callPackage ../tools/networking/wbox {};
#
#  welkin = callPackage ../tools/graphics/welkin {};
#
#  whois = callPackage ../tools/networking/whois { };
#
#  wsmancli = callPackage ../tools/system/wsmancli {};
#
#  wolfebin = callPackage ../tools/networking/wolfebin {
#    python = python2;
#  };
#
  xl2tpd = callPackage ../tools/networking/xl2tpd { };
#
#  xe = callPackage ../tools/system/xe { };
#
#  testdisk = callPackage ../tools/misc/testdisk { };
#
#  html2text = callPackage ../tools/text/html2text { };
#
#  html-tidy = callPackage ../tools/text/html-tidy { };
#
#  html-xml-utils = callPackage ../tools/text/xml/html-xml-utils { };
#
#  rcm = callPackage ../tools/misc/rcm {};
#
#  tftp-hpa = callPackage ../tools/networking/tftp-hpa {};
#
#  tigervnc = callPackage ../tools/admin/tigervnc {
#    fontDirectories = [ xorg.fontadobe75dpi xorg.fontmiscmisc xorg.fontcursormisc
#      xorg.fontbhlucidatypewriter75dpi ];
#    fltk = fltk13;
#  };
#
#  tightvnc = callPackage ../tools/admin/tightvnc {
#    fontDirectories = [ xorg.fontadobe75dpi xorg.fontmiscmisc xorg.fontcursormisc
#      xorg.fontbhlucidatypewriter75dpi ];
#  };
#
  time = callPackage ../tools/misc/time { };
#
#  tkabber = callPackage ../applications/networking/instant-messengers/tkabber { };
#
#  qfsm = callPackage ../applications/science/electronics/qfsm { };
#
#  tkgate = callPackage ../applications/science/electronics/tkgate/1.x.nix { };
#
#  tm = callPackage ../tools/system/tm { };
#
#  tradcpp = callPackage ../development/tools/tradcpp { };
#
#  trang = callPackage ../tools/text/xml/trang { };
#
  tre = callPackage ../development/libraries/tre { };
#
#  ts = callPackage ../tools/system/ts { };
#
#  transfig = callPackage ../tools/graphics/transfig {
#    libpng = libpng12;
#  };
#
#  truecrypt = callPackage ../applications/misc/truecrypt {
#    wxGUI = config.truecrypt.wxGUI or true;
#  };
#
#  ttmkfdir = callPackage ../tools/misc/ttmkfdir { };
#
#  udunits = callPackage ../development/libraries/udunits { };
#
#  uim = callPackage ../tools/inputmethods/uim {
#    inherit (pkgs.kde4) kdelibs;
#  };
#
#  uhub = callPackage ../servers/uhub { };
#
#  unclutter = callPackage ../tools/misc/unclutter { };
#
#  units = callPackage ../tools/misc/units { };
#
#  xar = callPackage ../tools/compression/xar { };
#
#  xarchive = callPackage ../tools/archivers/xarchive { };
#
#  xarchiver = callPackage ../tools/archivers/xarchiver { };
#
#  xbrightness = callPackage ../tools/X11/xbrightness { };
#
#  xfstests = callPackage ../tools/misc/xfstests { };
#
#  xprintidle-ng = callPackage ../tools/X11/xprintidle-ng {};
#
#  xsettingsd = callPackage ../tools/X11/xsettingsd { };
#
#  xsensors = callPackage ../os-specific/linux/xsensors { };
#
#  xcruiser = callPackage ../applications/misc/xcruiser { };
#
#  xxkb = callPackage ../applications/misc/xxkb { };
#
#  unarj = callPackage ../tools/archivers/unarj { };
#
#  unshield = callPackage ../tools/archivers/unshield { };
#
  unzip = callPackage ../tools/archivers/unzip { };

  unzipNLS = lowPrio (unzip.override { enableNLS = true; });
#
#  uptimed = callPackage ../tools/system/uptimed { };
#
#  urjtag = callPackage ../tools/misc/urjtag {
#    svfSupport = true;
#    bsdlSupport = true;
#    staplSupport = true;
#    jedecSupport = true;
#  };
#
#  urlwatch = callPackage ../tools/networking/urlwatch { };
#
#  valum = callPackage ../development/web/valum { };
#
#  varnish = callPackage ../servers/varnish { };
#
#  venus = callPackage ../tools/misc/venus {
#    python = python27;
#  };
#
#  vlan = callPackage ../tools/networking/vlan { };
#
#  vmtouch = callPackage ../tools/misc/vmtouch { };
#
#  volumeicon = callPackage ../tools/audio/volumeicon { };
#
  waf = callPackage ../development/tools/build-managers/waf { };
#
#  wakelan = callPackage ../tools/networking/wakelan { };
#
#  wavemon = callPackage ../tools/networking/wavemon { };
#
#  wdfs = callPackage ../tools/filesystems/wdfs { };
#
#  wdiff = callPackage ../tools/text/wdiff { };
#
#  webalizer = callPackage ../tools/networking/webalizer { };
#
#  weighttp = callPackage ../tools/networking/weighttp { };
#
  wget = callPackage ../tools/networking/wget { };
#
#  wicd = callPackage ../tools/networking/wicd { };
#
#  wipe = callPackage ../tools/security/wipe { };
#
#  wkhtmltopdf = callPackage ../tools/graphics/wkhtmltopdf {
#    overrideDerivation = lib.overrideDerivation;
#  };
#
#  wml = callPackage ../development/web/wml { };
#
#  wrk = callPackage ../tools/networking/wrk { };
#
#  wv = callPackage ../tools/misc/wv { };
#
#  wv2 = callPackage ../tools/misc/wv2 { };
#
#  wyrd = callPackage ../tools/misc/wyrd {
#    inherit (ocamlPackages) camlp4;
#  };
#
#  x86info = callPackage ../os-specific/linux/x86info { };
#
#  x11_ssh_askpass = callPackage ../tools/networking/x11-ssh-askpass { };
#
#  xbursttools = assert stdenv ? libc; callPackage ../tools/misc/xburst-tools {
#    # It needs a cross compiler for mipsel to build the firmware it will
#    # load into the Ben Nanonote
#    gccCross =
#      let
#        pkgsCross = (import ./all-packages.nix) {
#          inherit system;
#          inherit bootStdenv noSysDirs gccWithCC gccWithProfiling config;
#          # Ben Nanonote system
#          crossSystem = {
#            config = "mipsel-unknown-linux";
#            bigEndian = true;
#            arch = "mips";
#            float = "soft";
#            withTLS = true;
#            libc = "uclibc";
#            platform = {
#              name = "ben_nanonote";
#              kernelMajor = "2.6";
#              # It's not a bcm47xx processor, but for the headers this should work
#              kernelHeadersBaseConfig = "bcm47xx_defconfig";
#              kernelArch = "mips";
#            };
#            gcc = {
#              arch = "mips32";
#            };
#          };
#        };
#      in
#        pkgsCross.gccCrossStageStatic;
#  };
#
#  xclip = callPackage ../tools/misc/xclip { };
#
#  xtitle = callPackage ../tools/misc/xtitle { };
#
#  xdelta = callPackage ../tools/compression/xdelta { };
#  xdeltaUnstable = callPackage ../tools/compression/xdelta/unstable.nix { };
#
#  xdummy = callPackage ../tools/misc/xdummy { };
#
#  xflux = callPackage ../tools/misc/xflux { };
#
#  xml2 = callPackage ../tools/text/xml/xml2 { };
#
#  xmlroff = callPackage ../tools/typesetting/xmlroff { };
#
#  xmlstarlet = callPackage ../tools/text/xml/xmlstarlet { };
#
#  xmpppy = pythonPackages.xmpppy;
#
  xorriso = callPackage ../tools/cd-dvd/xorriso { };
#
#  xsel = callPackage ../tools/misc/xsel { };
#
#  xtreemfs = callPackage ../tools/filesystems/xtreemfs {};
#
#  xurls = callPackage ../tools/text/xurls {};
#
#  xvfb_run = callPackage ../tools/misc/xvfb-run { inherit (texFunctions) fontsConf; };
#
#  xvkbd = callPackage ../tools/X11/xvkbd {};
#
#  xwinmosaic = callPackage ../tools/X11/xwinmosaic {};
#
#  yank = callPackage ../tools/misc/yank { };
#
#  # To expose more packages for Yi, override the extraPackages arg.
#  yi = callPackage ../applications/editors/yi/wrapper.nix { };
#
#  yle-dl = callPackage ../tools/misc/yle-dl {};
#
#  zbackup = callPackage ../tools/backup/zbackup {};
#
#  zbar = callPackage ../tools/graphics/zbar {
#    pygtk = lib.overrideDerivation pygtk (x: {
#      gtk = gtk2;
#    });
#  };
#
#  zdelta = callPackage ../tools/compression/zdelta { };
#
#  zerotierone = callPackage ../tools/networking/zerotierone { };
#
#  zerofree = callPackage ../tools/filesystems/zerofree { };
#
#  zfstools = callPackage ../tools/filesystems/zfstools { };
#
#  zile = callPackage ../applications/editors/zile { };
#
#  zinnia = callPackage ../tools/inputmethods/zinnia { };
#  tegaki-zinnia-japanese = callPackage ../tools/inputmethods/tegaki-zinnia-japanese { };
#
#  zimreader = callPackage ../tools/text/zimreader { };
#
#  zimwriterfs = callPackage ../tools/text/zimwriterfs { };
#
#  zkfuse = callPackage ../tools/filesystems/zkfuse { };
#
#  zpaq = callPackage ../tools/archivers/zpaq { };
#  zpaqd = callPackage ../tools/archivers/zpaq/zpaqd.nix { };
#
#  zsh-navigation-tools = callPackage ../tools/misc/zsh-navigation-tools { };
#
#  zsync = callPackage ../tools/compression/zsync { };
#
#  zxing = callPackage ../tools/graphics/zxing {};
#
#
#  ### SHELLS
#
#
#  ### DEVELOPMENT / COMPILERS
#
#  fetchegg = callPackage ../build-support/fetchegg { };
#
#  eggDerivation = callPackage ../development/compilers/chicken/eggDerivation.nix { };
#
#  egg2nix = callPackage ../development/tools/egg2nix {
#    chickenEggs = callPackage ../development/tools/egg2nix/chicken-eggs.nix { };
#  };
#
#  clangWrapSelf = build: callPackage ../build-support/cc-wrapper {
#    cc = build;
#    isClang = true;
#    stdenv = pkgs.clangStdenv;
#    libc = glibc;
#    extraPackages = [ libcxx libcxxabi ];
#    nativeTools = false;
#    nativeLibc = false;
#  };
#
#  #Use this instead of stdenv to build with clang
  clangStdenv = lowPrio llvmPackages.stdenv;
  libcxxStdenv = stdenvAdapters.overrideCC pkgs.stdenv (clangWrapSelf llvmPackages.clang-unwrapped);
#
#  cython = pythonPackages.cython;
#  cython3 = python3Packages.cython;
#
  gcc = callPackageAlias "gcc5" { };

  gcc_multi =
    if system == "x86_64-linux" then lowPrio (
      let
        extraBuildCommands = ''
          echo "dontMoveLib64=1" >> $out/nix-support/setup-hook
        '';
      in wrapCCWith (callPackage ../build-support/cc-wrapper) glibc_multi extraBuildCommands (gcc.cc.override {
        stdenv = overrideCC pkgs.stdenv (wrapCCWith (callPackage ../build-support/cc-wrapper) glibc_multi "" gcc.cc);
        profiledCompiler = false;
        enableMultilib = true;
      }))
    else throw "Multilib gcc not supported on ‘${system}’";

  gcc_debug = lowPrio (wrapCC (gcc.cc.override {
    stripped = false;
  }));

  gccCrossStageStatic = let
    libcCross1 = null;
    in wrapGCCCross {
      gcc = forceNativeDrv (gcc.cc.override {
        cross = crossSystem;
        crossStageStatic = true;
        langCC = false;
        libcCross = libcCross1;
        enableShared = false;
      });
      libc = libcCross1;
      binutils = binutilsCross;
      cross = crossSystem;
  };
#
#  # Only needed for mingw builds
#  gccCrossMingw2 = wrapGCCCross {
#    gcc = gccCrossStageStatic.gcc;
#    libc = windows.mingw_headers2;
#    binutils = binutilsCross;
#    cross = assert crossSystem != null; crossSystem;
#  };
#
  gccCrossStageFinal = wrapGCCCross {
    gcc = forceNativeDrv (gcc.cc.override {
      cross = crossSystem;
      crossStageStatic = false;
#
#      # XXX: We have troubles cross-compiling libstdc++ on MinGW (see
#      # <http://hydra.nixos.org/build/4268232>), so don't even try.
      langCC = crossSystem.config != "i686-pc-mingw32";
    });
    libc = libcCross;
    binutils = binutilsCross;
    cross = crossSystem;
  };
#
  gcc48 = lowPrio (wrapCC (callPackage ../development/compilers/gcc/4.8 {
    noSysDirs = true;

    # PGO seems to speed up compilation by gcc by ~10%, see #445 discussion
    profiledCompiler = true;

    # When building `gcc.crossDrv' (a "Canadian cross", with host == target
    # and host != build), `cross' must be null but the cross-libc must still
    # be passed.
    cross = null;
    libcCross = null;

    isl = isl_0_14;
  }));
#
  gcc5 = lowPrio (wrapCC (callPackage ../development/compilers/gcc/5 {
    noSysDirs = true;

    # PGO seems to speed up compilation by gcc by ~10%, see #445 discussion
    profiledCompiler = true;

    # When building `gcc.crossDrv' (a "Canadian cross", with host == target
    # and host != build), `cross' must be null but the cross-libc must still
    # be passed.
    cross = null;
    libcCross = null;
  }));
#
#  gfortran = gfortran5;
#  gfortran5 = wrapCC (gcc5.cc.override {
#    name = "gfortran";
#    langFortran = true;
#    langCC = false;
#    langC = false;
#    profiledCompiler = false;
#  });
#
#  gcj = gcj5;
#  gcj5 = wrapCC (gcc5.cc.override {
#    name = "gcj";
#    langJava = true;
#    langFortran = false;
#    langCC = false;
#    langC = false;
#    profiledCompiler = false;
#    inherit zip unzip zlib boehmgc gettext pkgconfig perl;
#    inherit gtk;
#    inherit (gnome) libart_lgpl;
#  });
#
#  ghdl = wrapCC (gcc.cc.override {
#    name = "ghdl";
#    langVhdl = true;
#    langCC = false;
#    langC = false;
#    profiledCompiler = false;
#    enableMultilib = false;
#  });
#
#  # Haskell and GHC
#
  haskell = callPackage ./haskell-packages.nix { };
#
  haskellPackages = pkgs.haskell.packages.ghc7103.override {
    overrides = config.haskellPackageOverrides or (self: super: {});
  };
#  inherit (haskellPackages) ghc cabal-install stack;
#
#  hhvm = callPackage ../development/compilers/hhvm { };
#  hiphopvm = hhvm; /* Compatibility alias */
#
#  hop = callPackage ../development/compilers/hop { };
#
#  dotnetPackages = callPackage ./dotnet-packages.nix {};
#
#  go-repo-root = pkgs.goPackages.go-repo-root.bin // { outputs = [ "bin" ]; };
#
#  gox = pkgs.goPackages.gox.bin // { outputs = [ "bin" ]; };
#
#  icedtea7_web = callPackage ../development/compilers/icedtea-web {
#    jdk = jdk7;
#    xulrunner = firefox-unwrapped;
#  };
#
  icedtea8_web = callPackage ../development/compilers/icedtea-web {
    jdk = pkgs.jdk8;
    xulrunner = pkgs.firefox-unwrapped;
  };

  icedtea_web = pkgs.icedtea8_web;
#
#  openjdk7-bootstrap = callPackage ../development/compilers/openjdk/bootstrap.nix { version = "7"; };
  openjdk8-bootstrap = callPackage ../development/compilers/openjdk/bootstrap.nix { version = "8"; };
#
#  openjdk7-make-bootstrap = callPackage ../development/compilers/openjdk/make-bootstrap.nix {
#    openjdk = openjdk7.override { minimal = true; };
#  };
  openjdk8-make-bootstrap = callPackage ../development/compilers/openjdk/make-bootstrap.nix {
    openjdk = openjdk8.override { minimal = true; };
  };
#
#  openjdk7 = callPackage ../development/compilers/openjdk/7.nix {
#    bootjdk = openjdk7-bootstrap;
#  };
#  openjdk7_jdk = openjdk7 // { outputs = [ "out" ]; };
#  openjdk7_jre = openjdk7.jre // { outputs = [ "jre" ]; };
#
  openjdk8 = callPackage ../development/compilers/openjdk/8.nix {
    bootjdk = pkgs.openjdk8-bootstrap;
  };
  openjdk8_jdk = pkgs.openjdk8 // { outputs = [ "out" ]; };
  openjdk8_jre = pkgs.openjdk8.jre // { outputs = [ "jre" ]; };

  openjdk = callPackageAlias "openjdk8" { };
#
#  java7 = openjdk7;
#  jdk7 = java7 // { outputs = [ "out" ]; };
#  jre7 = java7.jre // { outputs = [ "jre" ]; };
#
  java8 = callPackageAlias "openjdk8" { };
  jdk8 = pkgs.java8 // { outputs = [ "out" ]; };
  jre8 = pkgs.java8.jre // { outputs = [ "jre" ]; };
#
  java = callPackageAlias "java8" { };
  jdk = pkgs.java // { outputs = [ "out" ]; };
  jre = pkgs.java.jre // { outputs = [ "jre" ]; };
#
#  lessc = callPackage ../development/compilers/lessc { };
#
  llvmPackages = recurseIntoAttrs (callPackageAlias "llvmPackages_37" { });
#
  llvmPackages_37 = callPackage ../development/compilers/llvm/3.7 {
    inherit (stdenvAdapters) overrideCC;
  };
#
#  mono = callPackage ../development/compilers/mono { };
#
#  monoDLLFixer = callPackage ../build-support/mono-dll-fixer { };
#
#  nvidia_cg_toolkit = callPackage ../development/compilers/nvidia-cg-toolkit { };
#
#  ocaml = ocamlPackages.ocaml;
#  ocaml_4_02 = callPackage ../development/compilers/ocaml/4.02.nix { };
#
  orc = callPackage ../development/compilers/orc { };
#
#  mkOcamlPackages = ocaml: self:
#    let
#      callPackage = newScope self;
#      ocaml_version = (builtins.parseDrvName ocaml.name).version;
#    in rec {
#    inherit ocaml;
#    buildOcaml = callPackage ../build-support/ocaml { };
#
#    alcotest = callPackage ../development/ocaml-modules/alcotest {};
#
#    ansiterminal = callPackage ../development/ocaml-modules/ansiterminal { };
#
#    asn1-combinators = callPackage ../development/ocaml-modules/asn1-combinators { };
#
#    async_extra = callPackage ../development/ocaml-modules/async_extra { };
#
#    async_find = callPackage ../development/ocaml-modules/async_find { };
#
#    async_kernel = callPackage ../development/ocaml-modules/async_kernel { };
#
#    async_shell = callPackage ../development/ocaml-modules/async_shell { };
#
#    async_ssl = callPackage ../development/ocaml-modules/async_ssl { };
#
#    async_unix = callPackage ../development/ocaml-modules/async_unix { };
#
#    async =
#      if lib.versionOlder "4.02" ocaml_version
#      then callPackage ../development/ocaml-modules/async { }
#      else null;
#
#    atd = callPackage ../development/ocaml-modules/atd { };
#
#    atdgen = callPackage ../development/ocaml-modules/atdgen { };
#
#    base64 = callPackage ../development/ocaml-modules/base64 { };
#
#    bolt = callPackage ../development/ocaml-modules/bolt { };
#
#    bitstring_2_0_4 = callPackage ../development/ocaml-modules/bitstring/2.0.4.nix { };
#    bitstring_git   = callPackage ../development/ocaml-modules/bitstring { };
#
#    bitstring =
#      if lib.versionOlder "4.02" ocaml_version
#      then bitstring_git
#      else bitstring_2_0_4;
#
#    camlidl = callPackage ../development/tools/ocaml/camlidl { };
#
#    camlp4 =
#      if lib.versionOlder "4.02" ocaml_version
#      then callPackage ../development/tools/ocaml/camlp4 { }
#      else null;
#
#    camlp5_6_strict = callPackage ../development/tools/ocaml/camlp5 { };
#
#    camlp5_6_transitional = callPackage ../development/tools/ocaml/camlp5 {
#      transitional = true;
#    };
#
#    camlp5_strict = camlp5_6_strict;
#
#    camlp5_transitional = camlp5_6_transitional;
#
#    camlpdf = callPackage ../development/ocaml-modules/camlpdf { };
#
#    calendar = callPackage ../development/ocaml-modules/calendar { };
#
#    camlzip = callPackage ../development/ocaml-modules/camlzip { };
#
#    camomile_0_8_2 = callPackage ../development/ocaml-modules/camomile/0.8.2.nix { };
#    camomile = callPackage ../development/ocaml-modules/camomile { };
#
#    camlimages_4_0 = callPackage ../development/ocaml-modules/camlimages/4.0.nix {
#      libpng = libpng12;
#      giflib = giflib_4_1;
#    };
#    camlimages_4_1 = callPackage ../development/ocaml-modules/camlimages/4.1.nix {
#      giflib = giflib_4_1;
#    };
#    camlimages = camlimages_4_1;
#
#    conduit = callPackage ../development/ocaml-modules/conduit {
#       lwt = ocaml_lwt;
#    };
#
#    biniou = callPackage ../development/ocaml-modules/biniou { };
#
#    bin_prot = callPackage ../development/ocaml-modules/bin_prot { };
#
#    ocaml_cairo = callPackage ../development/ocaml-modules/ocaml-cairo { };
#
#    ocaml_cairo2 = callPackage ../development/ocaml-modules/ocaml-cairo2 { };
#
#    cil = callPackage ../development/ocaml-modules/cil { };
#
#    cmdliner = callPackage ../development/ocaml-modules/cmdliner { };
#
#    cohttp = callPackage ../development/ocaml-modules/cohttp {
#      lwt = ocaml_lwt;
#    };
#
#    config-file = callPackage ../development/ocaml-modules/config-file { };
#
#    cpdf = callPackage ../development/ocaml-modules/cpdf { };
#
#    cppo = callPackage ../development/tools/ocaml/cppo { };
#
#    cryptokit = callPackage ../development/ocaml-modules/cryptokit { };
#
#    cstruct = callPackage ../development/ocaml-modules/cstruct {
#      lwt = ocaml_lwt;
#    };
#
#    csv = callPackage ../development/ocaml-modules/csv { };
#
#    custom_printf = callPackage ../development/ocaml-modules/custom_printf { };
#
#    ctypes = callPackage ../development/ocaml-modules/ctypes { };
#
#    dolog = callPackage ../development/ocaml-modules/dolog { };
#
#    easy-format = callPackage ../development/ocaml-modules/easy-format { };
#
#    eliom = callPackage ../development/ocaml-modules/eliom { };
#
#    enumerate = callPackage ../development/ocaml-modules/enumerate { };
#
#    erm_xml = callPackage ../development/ocaml-modules/erm_xml { };
#
#    erm_xmpp = callPackage ../development/ocaml-modules/erm_xmpp { };
#
#    ezjsonm = callPackage ../development/ocaml-modules/ezjsonm {
#      lwt = ocaml_lwt;
#    };
#
#    faillib = callPackage ../development/ocaml-modules/faillib { };
#
#    fieldslib = callPackage ../development/ocaml-modules/fieldslib { };
#
#    fileutils = callPackage ../development/ocaml-modules/fileutils { };
#
#    findlib = callPackage ../development/tools/ocaml/findlib { };
#
#    fix = callPackage ../development/ocaml-modules/fix { };
#
#    fontconfig = callPackage ../development/ocaml-modules/fontconfig {
#      inherit (pkgs) fontconfig;
#    };
#
#    functory = callPackage ../development/ocaml-modules/functory { };
#
#    herelib = callPackage ../development/ocaml-modules/herelib { };
#
#    io-page = callPackage ../development/ocaml-modules/io-page { };
#
#    ipaddr = callPackage ../development/ocaml-modules/ipaddr { };
#
#    iso8601 = callPackage ../development/ocaml-modules/iso8601 { };
#
#    javalib = callPackage ../development/ocaml-modules/javalib {
#      extlib = ocaml_extlib_maximal;
#    };
#
#    dypgen = callPackage ../development/ocaml-modules/dypgen { };
#
#    patoline = callPackage ../tools/typesetting/patoline { };
#
#    gapi_ocaml = callPackage ../development/ocaml-modules/gapi-ocaml { };
#
#    gg = callPackage ../development/ocaml-modules/gg { };
#
#    gmetadom = callPackage ../development/ocaml-modules/gmetadom { };
#
#    gtktop = callPackage ../development/ocaml-modules/gtktop { };
#
#    hex = callPackage ../development/ocaml-modules/hex { };
#
#    jingoo = callPackage ../development/ocaml-modules/jingoo {
#      batteries = ocaml_batteries;
#      pcre = ocaml_pcre;
#    };
#
#    js_of_ocaml = callPackage ../development/tools/ocaml/js_of_ocaml { };
#
#    jsonm = callPackage ../development/ocaml-modules/jsonm { };
#
#    lablgl = callPackage ../development/ocaml-modules/lablgl { };
#
#    lablgtk_2_14 = callPackage ../development/ocaml-modules/lablgtk/2.14.0.nix {
#      inherit (gnome) libgnomecanvas libglade gtksourceview;
#    };
#    lablgtk = callPackage ../development/ocaml-modules/lablgtk {
#      inherit (gnome) libgnomecanvas libglade gtksourceview;
#    };
#
#    lablgtk-extras =
#      if lib.versionOlder "4.02" ocaml_version
#      then callPackage ../development/ocaml-modules/lablgtk-extras { }
#      else callPackage ../development/ocaml-modules/lablgtk-extras/1.4.nix { };
#
#    lablgtkmathview = callPackage ../development/ocaml-modules/lablgtkmathview {
#      gtkmathview = callPackage ../development/libraries/gtkmathview { };
#    };
#
#    lambdaTerm-1_6 = callPackage ../development/ocaml-modules/lambda-term/1.6.nix { };
#    lambdaTerm =
#      if lib.versionOlder "4.01" ocaml_version
#      then callPackage ../development/ocaml-modules/lambda-term { }
#      else lambdaTerm-1_6;
#
#    llvm = callPackage ../development/ocaml-modules/llvm { };
#
#    macaque = callPackage ../development/ocaml-modules/macaque { };
#
#    magic-mime = callPackage ../development/ocaml-modules/magic-mime { };
#
#    magick = callPackage ../development/ocaml-modules/magick { };
#
#    menhir = callPackage ../development/ocaml-modules/menhir { };
#
#    merlin = callPackage ../development/tools/ocaml/merlin { };
#
#    mlgmp =  callPackage ../development/ocaml-modules/mlgmp { };
#
#    nocrypto =  callPackage ../development/ocaml-modules/nocrypto { };
#
#    ocaml_batteries = callPackage ../development/ocaml-modules/batteries { };
#
#    comparelib = callPackage ../development/ocaml-modules/comparelib { };
#
#    core_extended = callPackage ../development/ocaml-modules/core_extended { };
#
#    core_kernel = callPackage ../development/ocaml-modules/core_kernel { };
#
#    core = callPackage ../development/ocaml-modules/core { };
#
#    ocaml_cryptgps = callPackage ../development/ocaml-modules/cryptgps { };
#
#    ocaml_data_notation = callPackage ../development/ocaml-modules/odn { };
#
#    ocaml_expat = callPackage ../development/ocaml-modules/expat { };
#
#    ocamlfuse = callPackage ../development/ocaml-modules/ocamlfuse { };
#
#    ocamlgraph = callPackage ../development/ocaml-modules/ocamlgraph { };
#
#    ocaml_http = callPackage ../development/ocaml-modules/http { };
#
#    ocamlify = callPackage ../development/tools/ocaml/ocamlify { };
#
#    ocaml_lwt = callPackage ../development/ocaml-modules/lwt { };
#
#    ocamlmod = callPackage ../development/tools/ocaml/ocamlmod { };
#
#    ocaml_mysql = callPackage ../development/ocaml-modules/mysql { };
#
#    ocamlnet = callPackage ../development/ocaml-modules/ocamlnet { };
#
#    ocaml_oasis = callPackage ../development/tools/ocaml/oasis { };
#
#    ocaml_optcomp = callPackage ../development/ocaml-modules/optcomp { };
#
#    ocaml_pcre = callPackage ../development/ocaml-modules/pcre {};
#
#    pgocaml = callPackage ../development/ocaml-modules/pgocaml {};
#
#    ocaml_react = callPackage ../development/ocaml-modules/react { };
#    reactivedata = callPackage ../development/ocaml-modules/reactivedata {};
#
#    ocamlscript = callPackage ../development/tools/ocaml/ocamlscript { };
#
#    ocamlsdl= callPackage ../development/ocaml-modules/ocamlsdl { };
#
#    ocaml_sqlite3 = callPackage ../development/ocaml-modules/sqlite3 { };
#
#    ocaml_ssl = callPackage ../development/ocaml-modules/ssl { };
#
#    ocaml_text = callPackage ../development/ocaml-modules/ocaml-text { };
#
#    ocpBuild = callPackage ../development/tools/ocaml/ocp-build { };
#
#    ocpIndent = callPackage ../development/tools/ocaml/ocp-indent { };
#
#    ocp-index = callPackage ../development/tools/ocaml/ocp-index { };
#
#    ocplib-endian = callPackage ../development/ocaml-modules/ocplib-endian { };
#
#    ocsigen_server = callPackage ../development/ocaml-modules/ocsigen-server { };
#
#    ojquery = callPackage ../development/ocaml-modules/ojquery { };
#
#    otfm = callPackage ../development/ocaml-modules/otfm { };
#
#    ounit = callPackage ../development/ocaml-modules/ounit { };
#
#    piqi = callPackage ../development/ocaml-modules/piqi { };
#    piqi-ocaml = callPackage ../development/ocaml-modules/piqi-ocaml { };
#
#    re2 = callPackage ../development/ocaml-modules/re2 { };
#
#    tuntap = callPackage ../development/ocaml-modules/tuntap { };
#
#    tyxml = callPackage ../development/ocaml-modules/tyxml { };
#
#    ulex = callPackage ../development/ocaml-modules/ulex { };
#
#    ulex08 = callPackage ../development/ocaml-modules/ulex/0.8 {
#      camlp5 = camlp5_transitional;
#    };
#
#    textutils = callPackage ../development/ocaml-modules/textutils { };
#
#    type_conv_108_08_00 = callPackage ../development/ocaml-modules/type_conv/108.08.00.nix { };
#    type_conv_109_60_01 = callPackage ../development/ocaml-modules/type_conv/109.60.01.nix { };
#    type_conv_112_01_01 = callPackage ../development/ocaml-modules/type_conv/112.01.01.nix { };
#    type_conv =
#      if lib.versionOlder "4.02" ocaml_version
#      then type_conv_112_01_01
#      else if lib.versionOlder "4.00" ocaml_version
#      then type_conv_109_60_01
#      else if lib.versionOlder "3.12" ocaml_version
#      then type_conv_108_08_00
#      else null;
#
#    sexplib_108_08_00 = callPackage ../development/ocaml-modules/sexplib/108.08.00.nix { };
#    sexplib_111_25_00 = callPackage ../development/ocaml-modules/sexplib/111.25.00.nix { };
#    sexplib_112_24_01 = callPackage ../development/ocaml-modules/sexplib/112.24.01.nix { };
#
#    sexplib =
#      if lib.versionOlder "4.02" ocaml_version
#      then sexplib_112_24_01
#      else if lib.versionOlder "4.00" ocaml_version
#      then sexplib_111_25_00
#      else if lib.versionOlder "3.12" ocaml_version
#      then sexplib_108_08_00
#      else null;
#
#    ocaml_extlib = callPackage ../development/ocaml-modules/extlib { };
#    ocaml_extlib_maximal = callPackage ../development/ocaml-modules/extlib {
#      minimal = false;
#    };
#
#    ocurl = callPackage ../development/ocaml-modules/ocurl { };
#
#    pa_ounit = callPackage ../development/ocaml-modules/pa_ounit { };
#
#    pa_bench = callPackage ../development/ocaml-modules/pa_bench { };
#
#    pa_test = callPackage ../development/ocaml-modules/pa_test { };
#
#    pipebang = callPackage ../development/ocaml-modules/pipebang { };
#
#    pprint = callPackage ../development/ocaml-modules/pprint { };
#
#    ppx_tools =
#      if lib.versionAtLeast ocaml_version "4.02"
#      then callPackage ../development/ocaml-modules/ppx_tools {}
#      else null;
#
#    pycaml = callPackage ../development/ocaml-modules/pycaml { };
#
#    qcheck = callPackage ../development/ocaml-modules/qcheck {
#      oasis = ocaml_oasis;
#    };
#
#    qtest = callPackage ../development/ocaml-modules/qtest {
#      oasis = ocaml_oasis;
#    };
#
#    re = callPackage ../development/ocaml-modules/re { };
#
#    safepass = callPackage ../development/ocaml-modules/safepass { };
#
#    sqlite3EZ = callPackage ../development/ocaml-modules/sqlite3EZ { };
#
#    stringext = callPackage ../development/ocaml-modules/stringext { };
#
#    twt = callPackage ../development/ocaml-modules/twt { };
#
#    typerep = callPackage ../development/ocaml-modules/typerep { };
#
#    utop = callPackage ../development/tools/ocaml/utop { };
#
#    uuidm = callPackage ../development/ocaml-modules/uuidm { };
#
#    sawja = callPackage ../development/ocaml-modules/sawja { };
#
#    uucd = callPackage ../development/ocaml-modules/uucd { };
#    uucp = callPackage ../development/ocaml-modules/uucp { };
#    uunf = callPackage ../development/ocaml-modules/uunf { };
#
#    uri = callPackage ../development/ocaml-modules/uri { };
#
#    uuseg = callPackage ../development/ocaml-modules/uuseg { };
#    uutf = callPackage ../development/ocaml-modules/uutf { };
#
#    variantslib = callPackage ../development/ocaml-modules/variantslib { };
#
#    vg = callPackage ../development/ocaml-modules/vg { };
#
#    why3 = callPackage ../development/ocaml-modules/why3 {
#      why3 = pkgs.why3;
#    };
#
#    x509 = callPackage ../development/ocaml-modules/x509 { };
#
#    xmlm = callPackage ../development/ocaml-modules/xmlm { };
#
#    xml-light = callPackage ../development/ocaml-modules/xml-light { };
#
#    yojson = callPackage ../development/ocaml-modules/yojson { };
#
#    zarith = callPackage ../development/ocaml-modules/zarith { };
#
#    zed = callPackage ../development/ocaml-modules/zed { };
#
#    ocsigen_deriving = callPackage ../development/ocaml-modules/ocsigen-deriving {
#      oasis = ocaml_oasis;
#    };
#
#  };
#
#  ocamlPackages = ocamlPackages_latest;
#  ocamlPackages_4_02 = mkOcamlPackages ocaml_4_02 pkgs.ocamlPackages_4_02;
#  ocamlPackages_latest = ocamlPackages_4_02;
#
#  ocaml_make = callPackage ../development/ocaml-modules/ocamlmake { };
#
#  ocaml-top = callPackage ../development/tools/ocaml/ocaml-top { };
#
#  opam = callPackage ../development/tools/ocaml/opam { };
#
  rustcMaster = callPackage ../development/compilers/rustc/head.nix { };
  rustc = callPackage ../development/compilers/rustc { };
#
  rustPlatform = pkgs.rustStable;
#
  rustStable = recurseIntoAttrs (pkgs.makeRustPlatform pkgs.cargo);
  rustUnstable = recurseIntoAttrs (pkgs.makeRustPlatform pkgs.cargoUnstable);
#
#  # rust platform to build cargo itself (with cargoSnapshot)
  rustCargoPlatform = pkgs.makeRustPlatform (pkgs.cargoSnapshot pkgs.rustc);
#  rustUnstableCargoPlatform = pkgs.makeRustPlatform (pkgs.cargoSnapshot pkgs.rustcMaster);
#
  makeRustPlatform = cargo:
    let
      callPackage = pkgs.newScope self;

      self = {
        inherit cargo;

        rustc = cargo.rustc;

        rustRegistry = callPackage ./rust-packages.nix { };

        buildRustPackage = callPackage ../build-support/rust {
          inherit cargo;
        };
      };
    in self;
#
#  rustfmt = callPackage ../development/tools/rust/rustfmt { };
#
#  sbclBootstrap = callPackage ../development/compilers/sbcl/bootstrap.nix {};
#  sbcl = callPackage ../development/compilers/sbcl {};
#
#  scala = callPackage ../development/compilers/scala { };
#
#  sqldeveloper = callPackage ../development/tools/database/sqldeveloper { };
#
#  metaBuildEnv = callPackage ../development/compilers/meta-environment/meta-build-env { };
#
#  tbb = callPackage ../development/libraries/tbb { };
#
#  thrust = callPackage ../development/tools/thrust { };
#
#  trv = callPackage ../development/tools/misc/trv {
#   inherit (ocamlPackages_4_02) findlib camlp4 core async async_unix
#     async_extra sexplib async_shell core_extended async_find cohttp uri;
#    ocaml = ocaml_4_02;
#  };
#
#  wrapGCCCross =
#    {gcc, libc, binutils, cross, shell ? "", name ? "gcc-cross-wrapper"}:
#
#    forceNativeDrv (callPackage ../build-support/gcc-cross-wrapper {
#      nativeTools = false;
#      nativeLibc = false;
#      noLibc = (libc == null);
#      inherit gcc binutils libc shell name cross;
#    });
#
#  ### DEVELOPMENT / INTERPRETERS
#
#  erlangR18 = callPackage ../development/interpreters/erlang/R18.nix { };
#  erlang = erlangR18;
#
#  fetchHex = callPackage ../development/tools/build-managers/rebar3/fetch-hex.nix { };
#
#  erlangPackages = callPackage ../development/erlang-modules { };
#  hex2nix = erlangPackages.callPackage ../development/tools/erlang/hex2nix { };
#
  guile = callPackage ../development/interpreters/guile { };
#
#  jmeter = callPackage ../applications/networking/jmeter {};
#
#  davmail = callPackage ../applications/networking/davmail {};
#
#  lxappearance = callPackage ../applications/misc/lxappearance {};
#
#  ### LUA MODULES
#
#  lua5_2 = callPackage ../development/interpreters/lua-5/5.2.nix { };
#  lua5_2_compat = callPackage ../development/interpreters/lua-5/5.2.nix {
#    compat = true;
#  };
  lua5_3 = callPackage ../development/interpreters/lua-5/5.3.nix { };
  lua5_3_compat = callPackage ../development/interpreters/lua-5/5.3.nix {
    compat = true;
  };
  lua5 = callPackageAlias "lua5_3_compat" { };
  lua = callPackageAlias "lua5" { };
#
#  lua52Packages = callPackage ./lua-packages.nix { lua = lua5_2; };
  lua53Packages = callPackage ./lua-packages.nix {
    lua = callPackageAlias "lua5_3" { };
  };
  luaPackages = callPackageAlias "lua53Packages" { };
#
#  lua5_expat = callPackage ../development/interpreters/lua-5/expat.nix {};
#  lua5_sec = callPackage ../development/interpreters/lua-5/sec.nix { };
#
#  luajit = callPackage ../development/interpreters/luajit {};
#
#  luarocks = luaPackages.luarocks;
#
#  toluapp = callPackage ../development/tools/toluapp { };
#
#  ### END OF LUA
#
#  mesos-dns = pkgs.goPackages.mesos-dns.bin // { outputs = [ "bin" ]; };
#
#  nix-exec = callPackage ../development/interpreters/nix-exec {
#    nix = nixUnstable;
#  };
#
#  octave = callPackage ../development/interpreters/octave {
#    fltk = fltk13.override { cfg.xftSupport = true; };
#    qt = null;
#    ghostscript = null;
#    hdf5 = null;
#    glpk = null;
#    suitesparse = null;
#    jdk = null;
#    openblas = openblasCompat;
#  };
#  octaveFull = (lowPrio (callPackage ../development/interpreters/octave {
#    fltk = fltk13.override { cfg.xftSupport = true; };
#    qt = qt4;
#  }));
#
#  ocropus = callPackage ../applications/misc/ocropus { };
#
  php = pkgs.php70;
#
#  phpPackages = recurseIntoAttrs (callPackage ./php-packages.nix {});
#
  inherit (callPackages ../development/interpreters/php { })
    php70;
#
#  python2nix = callPackage ../tools/package-management/python2nix { };
#
#  pythonDocs = recurseIntoAttrs (callPackage ../development/interpreters/python/docs {});
#
#  pypi2nix = python27Packages.pypi2nix;
#
#  bundix = callPackage ../development/interpreters/ruby/bundix {
#    ruby = ruby_2_1_3;
#  };
#  bundler = callPackage ../development/interpreters/ruby/bundler.nix { };
#  bundler_HEAD = bundler;
#  defaultGemConfig = callPackage ../development/interpreters/ruby/gemconfig/default.nix { };
#  buildRubyGem = callPackage ../development/interpreters/ruby/build-ruby-gem { };
#  bundlerEnv = callPackage ../development/interpreters/ruby/bundler-env { };
#
  inherit (callPackage ../development/interpreters/ruby {})
    ruby_2_3_0;

  # Ruby aliases
  ruby = callPackageAlias "ruby_2_3" { };
  ruby_2_3 = callPackageAlias "ruby_2_3_0" { };
#
#  rubygems = hiPrio (callPackage ../development/interpreters/ruby/rubygems.nix {});
#
#  rq = callPackage ../applications/networking/cluster/rq { };
#
#  scsh = callPackage ../development/interpreters/scsh { };
#
  inherit (callPackages ../development/interpreters/spidermonkey { })
    spidermonkey_17
    spidermonkey_24;
  spidermonkey = callPackageAlias "spidermonkey_24" { };
#
#  tcl = tcl-8_6;
#  tcl-8_6 = callPackage ../development/interpreters/tcl/8.6.nix { };
#
#  xulrunner = callPackage ../development/interpreters/xulrunner {
#    inherit (gnome) libIDL;
#    inherit (pythonPackages) pysqlite;
#  };
#
#  ### DEVELOPMENT / MISC
#
#  amdadlsdk = callPackage ../development/misc/amdadl-sdk { };
#
#  amdappsdk26 = callPackage ../development/misc/amdapp-sdk {
#    version = "2.6";
#  };
#
#  amdappsdk27 = callPackage ../development/misc/amdapp-sdk {
#    version = "2.7";
#  };
#
#  amdappsdk28 = callPackage ../development/misc/amdapp-sdk {
#    version = "2.8";
#  };
#
#  amdappsdk = amdappsdk28;
#
#  amdappsdkFull = callPackage ../development/misc/amdapp-sdk {
#    version = "2.8";
#    samples = true;
#  };
#
#  avrgcclibc = callPackage ../development/misc/avr-gcc-with-avr-libc {};
#
#  avr8burnomat = callPackage ../development/misc/avr8-burn-omat { };
#
#  sourceFromHead = callPackage ../build-support/source-from-head-fun.nix {};
#
#  ecj = callPackage ../development/eclipse/ecj { };
#
#  jdtsdk = callPackage ../development/eclipse/jdt-sdk { };
#
#  pharo-vms = callPackage_i686 ../development/pharo/vm { };
#  pharo-vm  = pharo-vms.pharo-no-spur;
#  pharo-vm5 = pharo-vms.pharo-spur;
#
#  pharo-launcher = callPackage ../development/pharo/launcher { };
#
#  srecord = callPackage ../development/tools/misc/srecord { };
#
#  windowssdk = (
#    callPackage ../development/misc/windows-sdk {});
#
#  xidel = callPackage ../tools/text/xidel { };
#
#  ### DEVELOPMENT / TOOLS
#
#  activator = callPackage ../development/tools/activator { };
#
#  alloy = callPackage ../development/tools/alloy { };
#
#  augeas = callPackage ../tools/system/augeas { };
#
#  ansible = pythonPackages.ansible;
#
#  ansible2 = pythonPackages.ansible2;
#
#  antlr = callPackage ../development/tools/parsing/antlr/2.7.7.nix { };
#
#  antlr3 = callPackage ../development/tools/parsing/antlr { };
#
  ant = callPackageAlias "apacheAnt" { };

  apacheAnt = callPackage ../development/tools/build-managers/apache-ant { };
#
#  apacheKafka = callPackage ../servers/apache-kafka { };
#
#  astyle = callPackage ../development/tools/misc/astyle { };
#
  electron = callPackage ../development/tools/electron { };
#
#
#  autobuild = callPackage ../development/tools/misc/autobuild { };
#
  autoconf-archive = callPackage ../development/tools/misc/autoconf-archive { };

#  autocutsel = callPackage ../tools/X11/autocutsel{ };
#
  automoc4 = callPackage ../development/tools/misc/automoc4 { };
#
#  avrdude = callPackage ../development/tools/misc/avrdude { };
#
#  avarice = callPackage ../development/tools/misc/avarice { };
#
#  babeltrace = callPackage ../development/tools/misc/babeltrace { };
#
#  bam = callPackage ../development/tools/build-managers/bam {};
#
#  bazel = callPackage ../development/tools/build-managers/bazel { jdk = openjdk8; };
#
#  bin_replace_string = callPackage ../development/tools/misc/bin_replace_string { };
#
  binutils = callPackage ../development/tools/misc/binutils { };
#
#  bossa = callPackage ../development/tools/misc/bossa {
#    wxGTK = wxGTK30;
#  };
#
#  buildbot = callPackage ../development/tools/build-managers/buildbot {
#    inherit (pythonPackages) twisted jinja2 sqlalchemy sqlalchemy_migrate_0_7;
#    dateutil = pythonPackages.dateutil_1_5;
#  };
#
#  buildbot-slave = callPackage ../development/tools/build-managers/buildbot-slave {
#    inherit (pythonPackages) twisted;
#  };
#
#  byacc = callPackage ../development/tools/parsing/byacc { };
#
  cargo = callPackage ../development/tools/build-managers/cargo {
    # cargo needs to be built with rustCargoPlatform, which uses cargoSnapshot
    rustPlatform = pkgs.rustCargoPlatform;
  };
#
#  cargoUnstable = callPackage ../development/tools/build-managers/cargo/head.nix {
#    rustPlatform = rustUnstableCargoPlatform;
#  };
#
  cargoSnapshot = rustc:
    callPackage ../development/tools/build-managers/cargo/snapshot.nix {
      inherit rustc;
    };
#
#  casperjs = callPackage ../development/tools/casperjs { };
#
#  cbrowser = callPackage ../development/tools/misc/cbrowser { };
#
#  ccache = callPackage ../development/tools/misc/ccache { };
#
#  # Wrapper that works as gcc or g++
#  # It can be used by setting in nixpkgs config like this, for example:
#  #    replaceStdenv = { pkgs }: pkgs.ccacheStdenv;
#  # But if you build in chroot, you should have that path in chroot
#  # If instantiated directly, it will use the HOME/.ccache as cache directory.
#  # You can use an override in packageOverrides to set extraConfig:
#  #    packageOverrides = pkgs: {
#  #     ccacheWrapper = pkgs.ccacheWrapper.override {
#  #       extraConfig = ''
#  #         CCACHE_COMPRESS=1
#  #         CCACHE_DIR=/bin/.ccache
#  #       '';
#  #     };
#  #
#  ccacheWrapper = makeOverridable ({ extraConfig ? "" }:
#     wrapCC (ccache.links extraConfig)) {};
#  ccacheStdenv = lowPrio (overrideCC stdenv ccacheWrapper);
#
#  cccc = callPackage ../development/tools/analysis/cccc { };
#
#  cgdb = callPackage ../development/tools/misc/cgdb { };
#
#  chefdk = callPackage ../development/tools/chefdk {
#    ruby = ruby_2_0_0;
#  };
#
#  cfr = callPackage ../development/tools/java/cfr { };
#
#  checkstyle = callPackage ../development/tools/analysis/checkstyle { };
#
#  chromedriver = callPackage ../development/tools/selenium/chromedriver { };
#
#  chrpath = callPackage ../development/tools/misc/chrpath { };
#
#  chruby = callPackage ../development/tools/misc/chruby { rubies = null; };
#
#  "cl-launch" = callPackage ../development/tools/misc/cl-launch {};
#
#  coan = callPackage ../development/tools/analysis/coan { };
#
#  complexity = callPackage ../development/tools/misc/complexity { };
#
#  cookiecutter = pythonPackages.cookiecutter;
#
#  ctags = callPackage ../development/tools/misc/ctags { };
#
#  ctagsWrapped = callPackage ../development/tools/misc/ctags/wrapped.nix {};
#
#  ctodo = callPackage ../applications/misc/ctodo { };
#
#  coccinelle = callPackage ../development/tools/misc/coccinelle { };
#
#  cpptest = callPackage ../development/libraries/cpptest { };
#
#  cppi = callPackage ../development/tools/misc/cppi { };
#
#  cproto = callPackage ../development/tools/misc/cproto { };
#
#  cflow = callPackage ../development/tools/misc/cflow { };
#
#  cov-build = callPackage ../development/tools/analysis/cov-build {};
#
#  cppcheck = callPackage ../development/tools/analysis/cppcheck { };
#
#  cscope = callPackage ../development/tools/misc/cscope { };
#
#  csslint = callPackage ../development/web/csslint { };
#
#  libsigrok = callPackage ../development/tools/libsigrok { };
#
#  libsigrokdecode = callPackage ../development/tools/libsigrokdecode { };
#
  dejagnu = callPackage ../development/tools/misc/dejagnu { };
#
#  dfeet = callPackage ../development/tools/misc/d-feet {
#    inherit (pythonPackages) pep8;
#  };
#
#  dfu-programmer = callPackage ../development/tools/misc/dfu-programmer { };
#
#  dfu-util = callPackage ../development/tools/misc/dfu-util { };
#
#  ddd = callPackage ../development/tools/misc/ddd { };
#
#  distcc = callPackage ../development/tools/misc/distcc { };
#
#  # distccWrapper: wrapper that works as gcc or g++
#  # It can be used by setting in nixpkgs config like this, for example:
#  #    replaceStdenv = { pkgs }: pkgs.distccStdenv;
#  # But if you build in chroot, a default 'nix' will create
#  # a new net namespace, and won't have network access.
#  # You can use an override in packageOverrides to set extraConfig:
#  #    packageOverrides = pkgs: {
#  #     distccWrapper = pkgs.distccWrapper.override {
#  #       extraConfig = ''
#  #         DISTCC_HOSTS="myhost1 myhost2"
#  #       '';
#  #     };
#  #
#  distccWrapper = makeOverridable ({ extraConfig ? "" }:
#     wrapCC (distcc.links extraConfig)) {};
#  distccStdenv = lowPrio (overrideCC stdenv distccWrapper);
#
#  distccMasquerade = callPackage ../development/tools/misc/distcc/masq.nix {
#    gccRaw = gcc.cc;
#    binutils = binutils;
#  };
#
#  doclifter = callPackage ../development/tools/misc/doclifter { };
#
#  dot2tex = pythonPackages.dot2tex;
#
  doxygen = callPackage ../development/tools/documentation/doxygen {
    qt4 = null;
  };
#
#  doxygen_gui = lowPrio (doxygen.override { inherit qt4; });
#
#  drush = callPackage ../development/tools/misc/drush { };
#
#  editorconfig-core-c = callPackage ../development/tools/misc/editorconfig-core-c { };
#
#  eggdbus = callPackage ../development/tools/misc/eggdbus { };
#
#  egypt = callPackage ../development/tools/analysis/egypt { };
#
#  emma = callPackage ../development/tools/analysis/emma { };
#
#  epm = callPackage ../development/tools/misc/epm { };
#
#  eweb = callPackage ../development/tools/literate-programming/eweb { };
#
#  eztrace = callPackage ../development/tools/profiling/EZTrace { };
#
#  findbugs = callPackage ../development/tools/analysis/findbugs { };
#
#  flow = callPackage ../development/tools/analysis/flow { };
#
#  framac = callPackage ../development/tools/analysis/frama-c { };
#
#  frame = callPackage ../development/libraries/frame { };
#
#  fswatch = callPackage ../development/tools/misc/fswatch { };
#
#  funnelweb = callPackage ../development/tools/literate-programming/funnelweb { };
#
#  pmd = callPackage ../development/tools/analysis/pmd { };
#
#  jdepend = callPackage ../development/tools/analysis/jdepend { };
#
  flexcpp = callPackage ../development/tools/parsing/flexc++ { };

#
#  geis = callPackage ../development/libraries/geis { };
#
#  global = callPackage ../development/tools/misc/global { };
#
  gnome_doc_utils = callPackage ../development/tools/documentation/gnome-doc-utils {};

#  gob2 = callPackage ../development/tools/misc/gob2 { };
#
#  gotty = pkgs.goPackages.gotty.bin // { outputs = [ "bin" ]; };
#
#  gradleGen = callPackage ../development/tools/build-managers/gradle { };
#  gradle = self.gradleGen.gradleLatest;
#  gradle25 = self.gradleGen.gradle25;
#
#  grail = callPackage ../development/libraries/grail { };
#
#  gtkdialog = callPackage ../development/tools/misc/gtkdialog { };
#
#  guileLint = callPackage ../development/tools/guile/guile-lint { };
#
#  gwrap = callPackage ../development/tools/guile/g-wrap { };
#
#  heroku = callPackage ../development/tools/heroku { };
#
#  hyenae = callPackage ../tools/networking/hyenae { };
#
#  icestorm = callPackage ../development/tools/icestorm { };
#
#  icmake = callPackage ../development/tools/build-managers/icmake { };
#
#  iconnamingutils = callPackage ../development/tools/misc/icon-naming-utils {
#    inherit (perlPackages) XMLSimple;
#  };
#
#  include-what-you-use = callPackage ../development/tools/analysis/include-what-you-use { };
#
#  indent = callPackage ../development/tools/misc/indent { };
#
#  ino = callPackage ../development/arduino/ino { };
#
  inotify-tools = callPackage ../development/tools/misc/inotify-tools { };
#
#  intel-gpu-tools = callPackage ../development/tools/misc/intel-gpu-tools {};
#
#  iozone = callPackage ../development/tools/misc/iozone { };
#
#  ired = callPackage ../development/tools/analysis/radare/ired.nix { };
#
  itstool = callPackage ../development/tools/misc/itstool { };

#  jikespg = callPackage ../development/tools/parsing/jikespg { };
#
#  jenkins = callPackage ../development/tools/continuous-integration/jenkins { };
#
#  jenkins-job-builder = pythonPackages.jenkins-job-builder;
#
#  kcov = callPackage ../development/tools/analysis/kcov { };
#
#  lcov = callPackage ../development/tools/analysis/lcov { };
#
#  leiningen = callPackage ../development/tools/build-managers/leiningen { };
#
#  lemon = callPackage ../development/tools/parsing/lemon { };
#
#
#  mlibtool = callPackage ../development/tools/misc/mlibtool { };
#
#  lsof = callPackage ../development/tools/misc/lsof { };
#
#  ltrace = callPackage ../development/tools/misc/ltrace { };
#
#  lttng-tools = callPackage ../development/tools/misc/lttng-tools { };
#
#  lttng-ust = callPackage ../development/tools/misc/lttng-ust { };
#
#  lttv = callPackage ../development/tools/misc/lttv { };
#
#  maven = maven3;
#  maven3 = callPackage ../development/tools/build-managers/apache-maven { };
#
#  multi-ghc-travis = callPackage ../development/tools/haskell/multi-ghc-travis { };
#
#  neoload = callPackage ../development/tools/neoload {
#    licenseAccepted = (config.neoload.accept_license or false);
#    fontsConf = makeFontsConf {
#      fontDirectories = [
#        xorg.fontbhttf
#      ];
#    };
#  };
#
#  nant = callPackage ../development/tools/build-managers/nant { };
#
#  nixbang = callPackage ../development/tools/misc/nixbang {
#      pythonPackages = python3Packages;
#  };
#
#  node_webkit = node_webkit_0_9;
#
#  nwjs_0_12 = callPackage ../development/tools/node-webkit/nw12.nix { };
#
#  node_webkit_0_11 = callPackage ../development/tools/node-webkit/nw11.nix { };
#
#  node_webkit_0_9 = callPackage ../development/tools/node-webkit/nw9.nix { };
#
#  noweb = callPackage ../development/tools/literate-programming/noweb { };
#  nuweb = callPackage ../development/tools/literate-programming/nuweb { tex = texlive.combined.scheme-small; };
#
#  omake = callPackage ../development/tools/ocaml/omake { };
#  omake_rc1 = callPackage ../development/tools/ocaml/omake/0.9.8.6-rc1.nix { };
#
#  omniorb = callPackage ../development/tools/omniorb { };
#
#  opengrok = callPackage ../development/tools/misc/opengrok { };
#
#  openocd = callPackage ../development/tools/misc/openocd { };
#
#  oprofile = callPackage ../development/tools/profiling/oprofile { };
#
#  parse-cli-bin = callPackage ../development/tools/parse-cli-bin { };
#
#  peg = callPackage ../development/tools/parsing/peg { };
#
#  phantomjs = callPackage ../development/tools/phantomjs { };
#
#  phantomjs2 = callPackage ../development/tools/phantomjs2 { };
#
#  pmccabe = callPackage ../development/tools/misc/pmccabe { };
#
#  prelink = callPackage ../development/tools/misc/prelink { };
#
#  premake3 = callPackage ../development/tools/misc/premake/3.nix { };
#
#  premake4 = callPackage ../development/tools/misc/premake { };
#
#  premake = premake4;
#
#  racerRust = callPackage ../development/tools/rust/racer { };
#
#  radare = callPackage ../development/tools/analysis/radare {
#    inherit (gnome) vte;
#    useX11 = config.radare.useX11 or false;
#    pythonBindings = config.radare.pythonBindings or false;
#    rubyBindings = config.radare.rubyBindings or false;
#    luaBindings = config.radare.luaBindings or false;
#  };
#  radare2 = callPackage ../development/tools/analysis/radare2 {
#    inherit (gnome) vte;
#    useX11 = config.radare.useX11 or false;
#    pythonBindings = config.radare.pythonBindings or false;
#    rubyBindings = config.radare.rubyBindings or false;
#    luaBindings = config.radare.luaBindings or false;
#  };
#
#
#  ragel = callPackage ../development/tools/parsing/ragel { };
#
#  hammer = callPackage ../development/tools/parsing/hammer { };
#
  re2c = callPackage ../development/tools/parsing/re2c { };
#
#  remake = callPackage ../development/tools/build-managers/remake { };
#
#  rhc = callPackage ../development/tools/rhc { };
#
#  rman = callPackage ../development/tools/misc/rman { };
#
#  rr = callPackage ../development/tools/analysis/rr {
#    stdenv = stdenv_32bit;
#  };
#
#  saleae-logic = callPackage ../development/tools/misc/saleae-logic { };
#
#  sauce-connect = callPackage ../development/tools/sauce-connect { };
#
#  # couldn't find the source yet
#  seleniumRCBin = callPackage ../development/tools/selenium/remote-control {
#    jre = jdk;
#  };
#
#  selenium-server-standalone = callPackage ../development/tools/selenium/server { };
#
#  selendroid = callPackage ../development/tools/selenium/selendroid { };
#
  scons = callPackage ../development/tools/build-managers/scons { };
#
#  sbt = callPackage ../development/tools/build-managers/sbt { };
#  simpleBuildTool = sbt;
#
#  sigrok-cli = callPackage ../development/tools/sigrok-cli { };
#
#  simpleTpmPk11 = callPackage ../tools/security/simple-tpm-pk11 { };
#
#  slimerjs = callPackage ../development/tools/slimerjs {};
#
#  sloccount = callPackage ../development/tools/misc/sloccount { };
#
#  sloc = nodePackages.sloc;
#
#  smatch = callPackage ../development/tools/analysis/smatch {
#    buildllvmsparse = false;
#    buildc2xml = false;
#  };
#
#  smc = callPackage ../tools/misc/smc { };
#
#  sparse = callPackage ../development/tools/analysis/sparse { };
#
  speedtest-cli = callPackage ../tools/networking/speedtest-cli { };
#
#  spin = callPackage ../development/tools/analysis/spin { };
#
#  splint = callPackage ../development/tools/analysis/splint {
#    flex = flex_2_5_35;
#  };
#
#  sqlitebrowser = callPackage ../development/tools/database/sqlitebrowser { };
#
#  sselp = callPackage ../tools/X11/sselp{ };
#
#  stm32flash = callPackage ../development/tools/misc/stm32flash { };
#
  strace = callPackage ../development/tools/misc/strace { };
#
#  swfmill = callPackage ../tools/video/swfmill { };
#
#  swftools = callPackage ../tools/video/swftools { };
#
#  tcptrack = callPackage ../development/tools/misc/tcptrack { };
#
#  teensy-loader-cli = callPackage ../development/tools/misc/teensy-loader-cli { };
#
#  texi2html = callPackage ../development/tools/misc/texi2html { };
#
#  uhd = callPackage ../development/tools/misc/uhd {
#    boost = boost155;
#  };
#
#  uisp = callPackage ../development/tools/misc/uisp { };
#
#  uncrustify = callPackage ../development/tools/misc/uncrustify { };
#
#  vagrant = callPackage ../development/tools/vagrant {
#    ruby = ruby_2_2_2;
#  };
#
  gdb = callPackage ../development/tools/misc/gdb {
    guile = null;
  };
#
  valgrind = callPackage ../development/tools/analysis/valgrind { };
#
#  valkyrie = callPackage ../development/tools/analysis/valkyrie { };
#
#  xc3sprog = callPackage ../development/tools/misc/xc3sprog { };
#
#  xmlindent = callPackage ../development/web/xmlindent {};
#
#  xpwn = callPackage ../development/mobile/xpwn {};
#
#  xxdiff = callPackage ../development/tools/misc/xxdiff {
#    bison = bison2;
#  };
#
#  ycmd = callPackage ../development/tools/misc/ycmd { };
#
#  yodl = callPackage ../development/tools/misc/yodl { };
#
#  winpdb = callPackage ../development/tools/winpdb { };
#
#  grabserial = callPackage ../development/tools/grabserial { };
#
#
#  ### DEVELOPMENT / LIBRARIES
#
  a52dec = callPackage ../development/libraries/a52dec { };
#
#  aacskeys = callPackage ../development/libraries/aacskeys { };
#
  aalib = callPackage ../development/libraries/aalib { };
#
  accelio = callPackage ../development/libraries/accelio { };
#
#  activemq = callPackage ../development/libraries/apache-activemq { };
#
#  afflib = callPackage ../development/libraries/afflib { };
#
#  agg = callPackage ../development/libraries/agg { };
#
#  allegro = callPackage ../development/libraries/allegro {};
#  allegro5 = callPackage ../development/libraries/allegro/5.nix {};
#  allegro5unstable = callPackage
#    ../development/libraries/allegro/5-unstable.nix {};
#
#  appstream = callPackage ../development/libraries/appstream { };
#
#  assimp = callPackage ../development/libraries/assimp { };
#
#  asio = callPackage ../development/libraries/asio { };
#
  aspell = callPackage ../development/libraries/aspell { };
#
#  aspellDicts = recurseIntoAttrs (callPackages ../development/libraries/aspell/dictionaries.nix {});
#
#  aterm = aterm25;
#
#  aterm25 = callPackage ../development/libraries/aterm/2.5.nix { };
#
#  attica = callPackage ../development/libraries/attica { };
#
#  aqbanking = callPackage ../development/libraries/aqbanking { };
#
#  aubio = callPackage ../development/libraries/aubio { };
#
  audiofile = callPackage ../development/libraries/audiofile { };

  babl = callPackage ../development/libraries/babl { };
#
#  beecrypt = callPackage ../development/libraries/beecrypt { };
#
#  belle-sip = callPackage ../development/libraries/belle-sip { };
#
#  bobcat = callPackage ../development/libraries/bobcat { };
#
  boehmgc = callPackage ../development/libraries/boehm-gc { };
#
#  boolstuff = callPackage ../development/libraries/boolstuff { };
#
#  boost_process = callPackage ../development/libraries/boost-process { };
#
#  botan = callPackage ../development/libraries/botan { };
#  botanUnstable = callPackage ../development/libraries/botan/unstable.nix { };
#
#  box2d = callPackage ../development/libraries/box2d { };
#  box2d_2_0_1 = callPackage ../development/libraries/box2d/2.0.1.nix { };
#
#  buddy = callPackage ../development/libraries/buddy { };
#
#  bwidget = callPackage ../development/libraries/bwidget { };
#
#  capnproto = callPackage ../development/libraries/capnproto { };
#
#  ccnx = callPackage ../development/libraries/ccnx { };
#
#  ndn-cxx = callPackage ../development/libraries/ndn-cxx { };
#
#  cdk = callPackage ../development/libraries/cdk {};
#
#  cimg = callPackage  ../development/libraries/cimg { };
#
#  scmccid = callPackage ../development/libraries/scmccid { };
#
#  ccrtp = callPackage ../development/libraries/ccrtp { };
#
#  ccrtp_1_8 = callPackage ../development/libraries/ccrtp/1.8.nix { };
#
  celt = callPackage ../development/libraries/celt {};
  celt_0_7 = callPackage ../development/libraries/celt/0.7.nix {};
  celt_0_5_1 = callPackage ../development/libraries/celt/0.5.1.nix {};
#
#  cgal = callPackage ../development/libraries/CGAL {};
#
#  cgui = callPackage ../development/libraries/cgui {};
#
#  chipmunk = callPackage ../development/libraries/chipmunk {};
#
#  chmlib = callPackage ../development/libraries/chmlib { };
#
#  cilaterm = callPackage ../development/libraries/cil-aterm {
#    stdenv = overrideInStdenv stdenv [gnumake380];
#  };
#
#  clanlib = callPackage ../development/libraries/clanlib { };
#
#  classads = callPackage ../development/libraries/classads { };
#
#  classpath = callPackage ../development/libraries/java/classpath {
#    javac = gcj;
#    jvm = gcj;
#  };
#
#  clearsilver = callPackage ../development/libraries/clearsilver { };
#
#  cln = callPackage ../development/libraries/cln { };
#
#  clucene_core_2 = callPackage ../development/libraries/clucene-core/2.x.nix { };
#
#  clucene_core_1 = callPackage ../development/libraries/clucene-core { };
#
#  clucene_core = clucene_core_1;
#
#  cminpack = callPackage ../development/libraries/cminpack { };
#
#  cmocka = callPackage ../development/libraries/cmocka { };
#
#  coin3d = callPackage ../development/libraries/coin3d { };
#
#  CoinMP = callPackage ../development/libraries/CoinMP { };
#
#  commoncpp2 = callPackage ../development/libraries/commoncpp2 { };
#
#  confuse = callPackage ../development/libraries/confuse { };
#
#  coredumper = callPackage ../development/libraries/coredumper { };
#
#  ctl = callPackage ../development/libraries/ctl { };
#
#  ctpp2 = callPackage ../development/libraries/ctpp2 { };
#
#  ctpl = callPackage ../development/libraries/ctpl { };
#
#  cpp-netlib = callPackage ../development/libraries/cpp-netlib { };
#
  cppunit = callPackage ../development/libraries/cppunit { };

#  cwiid = callPackage ../development/libraries/cwiid { };
#
#  dhex = callPackage ../applications/editors/dhex { };
#
#  double_conversion = callPackage ../development/libraries/double-conversion { };
#
#  dclib = callPackage ../development/libraries/dclib { };
#
#  directfb = callPackage ../development/libraries/directfb { };
#
#  dlib = callPackage ../development/libraries/dlib { };
#
  dotconf = callPackage ../development/libraries/dotconf { };
#
#  dssi = callPackage ../development/libraries/dssi {};
#
#  dxflib = callPackage ../development/libraries/dxflib {};
#
#  eigen = callPackage ../development/libraries/eigen {};
#
#  eigen2 = callPackage ../development/libraries/eigen/2.0.nix {};
#
  enchant = callPackage ../development/libraries/enchant { };
#
#  enet = callPackage ../development/libraries/enet { };
#
#  enginepkcs11 = callPackage ../development/libraries/enginepkcs11 { };
#
  epoxy = callPackage ../development/libraries/epoxy {};
#
#  esdl = callPackage ../development/libraries/esdl { };
#
  exiv2 = callPackage ../development/libraries/exiv2 { };

#  eventlog = callPackage ../development/libraries/eventlog { };
#
#  facile = callPackage ../development/libraries/facile { };

  faad2 = callPackage ../development/libraries/faad2 { };
#
#  farbfeld = callPackage ../development/libraries/farbfeld { };
#
#  farsight2 = callPackage ../development/libraries/farsight2 { };
#
#  farstream = callPackage ../development/libraries/farstream { };
#
  fcgi = callPackage ../development/libraries/fcgi { };
#
#  ffmpegthumbnailer = callPackage ../development/libraries/ffmpegthumbnailer { };
#
  ffms = callPackage ../development/libraries/ffms { };
#
#  filter-audio = callPackage ../development/libraries/filter-audio {};
#
#  flann = callPackage ../development/libraries/flann { };
#
  flite = callPackage ../development/libraries/flite { };
#
#  fltk13 = callPackage ../development/libraries/fltk/fltk13.nix { };
#
#  fltk20 = callPackage ../development/libraries/fltk { };
#
#  fmod = callPackage ../development/libraries/fmod { };
#
#  fmod42416 = callPackage ../development/libraries/fmod/4.24.16.nix { };
#
#  freeimage = callPackage ../development/libraries/freeimage { };
#
#  freetts = callPackage ../development/libraries/freetts { };
#
#  cfitsio = callPackage ../development/libraries/cfitsio { };
#
#  fontconfig_210 = callPackage ../development/libraries/fontconfig/2.10.nix { };

  fontconfig = callPackage ../development/libraries/fontconfig { };

  fontconfig-ultimate = callPackage ../development/libraries/fontconfig-ultimate {};
#
#  folly = callPackage ../development/libraries/folly { };
#
  makeFontsConf = let fontconfig_ = pkgs.fontconfig; in {fontconfig ? fontconfig_, fontDirectories}:
    callPackage ../development/libraries/fontconfig/make-fonts-conf.nix {
      inherit fontconfig fontDirectories;
    };
#
  makeFontsCache = let fontconfig_ = pkgs.fontconfig; in {fontconfig ? fontconfig_, fontDirectories}:
    callPackage ../development/libraries/fontconfig/make-fonts-cache.nix {
      inherit fontconfig fontDirectories;
    };
#
#  freealut = callPackage ../development/libraries/freealut { };
#
#  freeglut = callPackage ../development/libraries/freeglut { };
#
#  freenect = callPackage ../development/libraries/freenect { };

  freetype = callPackage ../development/libraries/freetype { };

  frei0r = callPackage ../development/libraries/frei0r { };

  fribidi = callPackage ../development/libraries/fribidi { };
#
#  funambol = callPackage ../development/libraries/funambol { };
#
#  ganv = callPackage ../development/libraries/ganv { };
#
#  gdome2 = callPackage ../development/libraries/gdome2 {
#    inherit (gnome) gtkdoc;
#  };
#
  gdbm = callPackage ../development/libraries/gdbm { };
#
#  gecode_3 = callPackage ../development/libraries/gecode/3.nix { };
#  gecode_4 = callPackage ../development/libraries/gecode { };
#  gecode = gecode_4;
#
#  geoclue = callPackage ../development/libraries/geoclue {};
#
  geoclue2 = callPackage ../development/libraries/geoclue/2.0.nix {};
#
#  geoipWithDatabase = makeOverridable (callPackage ../development/libraries/geoip) {
#    drvName = "geoip-tools";
#    geoipDatabase = geolite-legacy;
#  };
#
#  geoipjava = callPackage ../development/libraries/java/geoipjava { };
#
#  geos = callPackage ../development/libraries/geos { };
#
#  getdata = callPackage ../development/libraries/getdata { };
#
  gd = callPackage ../development/libraries/gd { };
#
#  gdal = callPackage ../development/libraries/gdal { };
#
#  gdal_1_11 = callPackage ../development/libraries/gdal/gdal-1_11.nix { };
#
#  gdcm = callPackage ../development/libraries/gdcm { };
#
#  ggz_base_libs = callPackage ../development/libraries/ggz_base_libs {};
#
  giblib = callPackage ../development/libraries/giblib { };
#
#  libgit2 = callPackage ../development/libraries/git2 { };
#
#  libgit2_0_21 = callPackage ../development/libraries/git2/0.21.nix { };
#
#  glew = callPackage ../development/libraries/glew { };
#  glew110 = callPackage ../development/libraries/glew/1.10.nix { };
#
#  glfw = glfw3;
#  glfw2 = callPackage ../development/libraries/glfw/2.x.nix { };
#  glfw3 = callPackage ../development/libraries/glfw/3.x.nix { };
#
  glibc = callPackage ../development/libraries/glibc { };

  # Only supported on Linux
  glibcLocales = callPackage ../development/libraries/glibc/locales.nix { };

#  glm = callPackage ../development/libraries/glm { };
#  glm_0954 = callPackage ../development/libraries/glm/0954.nix { };
#
#  glog = callPackage ../development/libraries/glog { };
#
#  gloox = callPackage ../development/libraries/gloox { };
#
#  glpk = callPackage ../development/libraries/glpk { };
#
  gmime = callPackage ../development/libraries/gmime { };
#
#  gmm = callPackage ../development/libraries/gmm { };
#
#  goocanvas = callPackage ../development/libraries/goocanvas { };
#
#  grib-api = callPackage ../development/libraries/grib-api { };
#
#  qt-mobility = callPackage ../development/libraries/qt-mobility {};
#
#  qt_gstreamer = callPackage ../development/libraries/gstreamer/legacy/qt-gstreamer {};
#
#  qt_gstreamer1 = callPackage ../development/libraries/gstreamer/qt-gstreamer { boost = boost155;};
#
#  gnet = callPackage ../development/libraries/gnet { };
#
  gnu-efi = callPackage ../development/libraries/gnu-efi { };

  gom = callPackage ../all-pkgs/gom { };
#
#  gpac = callPackage ../applications/video/gpac { };
#
  gpgme = callPackage ../development/libraries/gpgme { };
#
#  gpgstats = callPackage ../tools/security/gpgstats { };
#
#  grantlee = callPackage ../development/libraries/grantlee { };
#
#  gsasl = callPackage ../development/libraries/gsasl { };
#
  gsl = callPackage ../development/libraries/gsl { };
#
#  gsl_1 = callPackage ../development/libraries/gsl/gsl-1_16.nix { };
#
#  gsoap = callPackage ../development/libraries/gsoap { };
#
  gss = callPackage ../development/libraries/gss { };
#
#  gtkimageview = callPackage ../development/libraries/gtkimageview { };
#
#  gtkmathview = callPackage ../development/libraries/gtkmathview { };
#
  gtkLibs = {
    inherit (pkgs) glib glibmm atk atkmm cairo pango pangomm gdk-pixbuf gtk2
      gtkmm2;
  };
#
#  gnome-sharp = callPackage ../development/libraries/gnome-sharp {};
#
#  gtk-sharp = callPackage ../development/libraries/gtk-sharp-2 {
#    inherit (gnome) libglade libgtkhtml gtkhtml
#              libgnomecanvas libgnomeui libgnomeprint
#              libgnomeprintui GConf gnomepanel;
#  };
#
#  gtkspellmm = callPackage ../development/libraries/gtkspellmm { };
#
  gts = callPackage ../development/libraries/gts { };
#
#  gwenhywfar = callPackage ../development/libraries/gwenhywfar { };
#
#  hamlib = callPackage ../development/libraries/hamlib { };
#
#  # TODO : Let admin choose.
#  # We are using mit-krb5 because it is better maintained
  heimdal_full = callPackage ../development/libraries/kerberos/heimdal.nix { };

  heimdal_lib = callPackageAlias "heimdal_full" {
    type = "lib";
  };
#
#  hawknl = callPackage ../development/libraries/hawknl { };
#
#  herqq = callPackage ../development/libraries/herqq { };
#
#  heyefi = haskellPackages.heyefi;
#
#  hidapi = callPackage ../development/libraries/hidapi { };
#
#  hiredis = callPackage ../development/libraries/hiredis { };
#
#  hivex = callPackage ../development/libraries/hivex {
#    inherit (perlPackages) IOStringy;
#  };
#
  hspell = callPackage ../development/libraries/hspell { };
#
#  hspellDicts = callPackage ../development/libraries/hspell/dicts.nix { };
#
#  hsqldb = callPackage ../development/libraries/java/hsqldb { };
#
#  hstr = callPackage ../applications/misc/hstr { };
#
#  htmlcxx = callPackage ../development/libraries/htmlcxx { };
#
#  http-parser = callPackage ../development/libraries/http-parser { inherit (pythonPackages) gyp; };
#
  hunspell = callPackage ../development/libraries/hunspell { };
#
#  hunspellDicts = recurseIntoAttrs (callPackages ../development/libraries/hunspell/dictionaries.nix {});
#
#  hwloc = callPackage ../development/libraries/hwloc {};
#
#  hydraAntLogger = callPackage ../development/libraries/java/hydra-ant-logger { };
#
#  hyena = callPackage ../development/libraries/hyena { };
#
#  iksemel = callPackage ../development/libraries/iksemel { };
#
#  ilbc = callPackage ../development/libraries/ilbc { };
#
#  ilixi = callPackage ../development/libraries/ilixi { };
#
  ilmbase = callPackage ../development/libraries/ilmbase { };
#
#  imv = callPackage ../applications/graphics/imv/default.nix { };
#
  imlib2 = callPackage ../development/libraries/imlib2 { };

  ijs = callPackage ../development/libraries/ijs { };
#
#  incrtcl = callPackage ../development/libraries/incrtcl { };
#
#  indicator-application-gtk2 = callPackage ../development/libraries/indicator-application/gtk2.nix { };
#  indicator-application-gtk3 = callPackage ../development/libraries/indicator-application/gtk3.nix { };
#
#  indilib = callPackage ../development/libraries/indilib { };
#
iniparser = callPackage ../development/libraries/iniparser { };
#
#  ip2location-c = callPackage ../development/libraries/ip2location-c { };
#
#  irrlicht = callPackage ../development/libraries/irrlicht { };
#  irrlicht3843 = callPackage ../development/libraries/irrlicht/irrlicht3843.nix { };
#
isocodes = callPackage ../development/libraries/iso-codes { };
#
#  itk = callPackage ../development/libraries/itk { };
#
  jasper = callPackage ../development/libraries/jasper { };
#
#  jama = callPackage ../development/libraries/jama { };
#
#  jansson = callPackage ../development/libraries/jansson { };
#
  jbig2dec = callPackage ../development/libraries/jbig2dec { };

  jbigkit = callPackage ../development/libraries/jbigkit { };

#  jetty_gwt = callPackage ../development/libraries/java/jetty-gwt { };
#
#  jetty_util = callPackage ../development/libraries/java/jetty-util { };
#
#  jshon = callPackage ../development/tools/parsing/jshon { };
#
#  json-c-0-11 = callPackage ../development/libraries/json-c/0.11.nix { }; # vulnerable
  json-c = callPackage ../development/libraries/json-c { };
#
#  jsoncpp = callPackage ../development/libraries/jsoncpp { };
#
#  libjson = callPackage ../development/libraries/libjson { };
#
#  libb64 = callPackage ../development/libraries/libb64 { };
#
  judy = callPackage ../development/libraries/judy { };
#
#  keybinder = callPackage ../development/libraries/keybinder {
#    automake = automake111x;
#  };
#
#  keybinder3 = callPackage ../development/libraries/keybinder3 {
#    automake = automake111x;
#  };
#
#  kinetic-cpp-client = callPackage ../development/libraries/kinetic-cpp-client { };
#
#  LASzip = callPackage ../development/libraries/LASzip { };
#
  lcms = callPackageAlias "lcms1" { };

  lcms1 = callPackage ../development/libraries/lcms { };

  lcms2 = callPackage ../development/libraries/lcms2 { };

#  lensfun = callPackage ../development/libraries/lensfun {};
#
  lesstif = callPackage ../development/libraries/lesstif { };

  leveldb = callPackage ../development/libraries/leveldb { };

  lmdb = callPackage ../development/libraries/lmdb { };
#
#  levmar = callPackage ../development/libraries/levmar { };
#
  leptonica = callPackage ../development/libraries/leptonica { };

  letsencrypt = callPackage ../tools/admin/letsencrypt { };
#
#  lib3ds = callPackage ../development/libraries/lib3ds { };
#
  libaacs = callPackage ../development/libraries/libaacs { };
#
#  libaal = callPackage ../development/libraries/libaal { };
#
  libaccounts-glib = callPackage ../development/libraries/libaccounts-glib { };

  libao = callPackage ../development/libraries/libao {
    usePulseAudio = config.pulseaudio or true;
  };
#
#  libabw = callPackage ../development/libraries/libabw { };
#
#  libantlr3c = callPackage ../development/libraries/libantlr3c {};
#
#  libappindicator-gtk2 = callPackage ../development/libraries/libappindicator { gtkVersion = "2"; };
#  libappindicator-gtk3 = callPackage ../development/libraries/libappindicator { gtkVersion = "3"; };
#
#  libasr = callPackage ../development/libraries/libasr { };
#
  libassuan = callPackage ../development/libraries/libassuan { };
#
  libasyncns = callPackage ../development/libraries/libasyncns { };
#
  libatomic_ops = callPackage ../development/libraries/libatomic_ops {};
#
#  libaudclient = callPackage ../development/libraries/libaudclient { };
#
#  libav = libav_11; # branch 11 is API-compatible with branch 10
#  libav_all = callPackage ../development/libraries/libav { };
#  inherit (libav_all) libav_0_8 libav_9 libav_11;
#
  libavc1394 = callPackage ../development/libraries/libavc1394 { };
#
#  libb2 = callPackage ../development/libraries/libb2 { };
#
#  libbluedevil = callPackage ../development/libraries/libbluedevil { };
#
  libbdplus = callPackage ../development/libraries/libbdplus { };

  libbs2b = callPackage ../development/libraries/audio/libbs2b { };
#
#  libbson = callPackage ../development/libraries/libbson { };
#
  libcaca = callPackage ../development/libraries/libcaca { };
#
#  libcacard = callPackage ../development/libraries/libcacard { };
#
#  libcec = callPackage ../development/libraries/libcec { };
#  libcec_platform = callPackage ../development/libraries/libcec/platform.nix { };
#
#  libcello = callPackage ../development/libraries/libcello {};
#
#  libcdaudio = callPackage ../development/libraries/libcdaudio { };
#
  libcddb = callPackage ../development/libraries/libcddb { };

  libcdio = callPackage ../development/libraries/libcdio { };
#  libcdio082 = callPackage ../development/libraries/libcdio/0.82.nix { };
#
  libcdr = callPackage ../development/libraries/libcdr { lcms = callPackageAlias "lcms2" { }; };
#
#  libchamplain = callPackage ../development/libraries/libchamplain { };
#
#  libchardet = callPackage ../development/libraries/libchardet { };
#
#  libchewing = callPackage ../development/libraries/libchewing { };
#
#  libcrafter = callPackage ../development/libraries/libcrafter { };
#
#  libuchardet = callPackage ../development/libraries/libuchardet { };
#
#  libchop = callPackage ../development/libraries/libchop { };
#
#  libcli = callPackage ../development/libraries/libcli { };
#
#  libclthreads = callPackage ../development/libraries/libclthreads  { };
#
#  libclxclient = callPackage ../development/libraries/libclxclient  { };
#
#  libcm = callPackage ../development/libraries/libcm { };
#
#  libcommuni = callPackage ../development/libraries/libcommuni { };
#
#  libconfuse = callPackage ../development/libraries/libconfuse { };
#
#  libcangjie = callPackage ../development/libraries/libcangjie { };
#
#  libcredis = callPackage ../development/libraries/libcredis { };
#
#  libctemplate = callPackage ../development/libraries/libctemplate { };
#
#  libctemplate_2_2 = callPackage ../development/libraries/libctemplate/2.2.nix { };
#
#  libcouchbase = callPackage ../development/libraries/libcouchbase { };
#
#  libcutl = callPackage ../development/libraries/libcutl { };
#
  libdaemon = callPackage ../development/libraries/libdaemon { };
#
#  libdbi = callPackage ../development/libraries/libdbi { };
#
#  libdbiDriversBase = callPackage ../development/libraries/libdbi-drivers {
#    libmysql = null;
#    sqlite = null;
#  };
#
#  libdbiDrivers = libdbiDriversBase.override {
#    inherit sqlite libmysql;
#  };
#
#  libdbusmenu-glib = callPackage ../development/libraries/libdbusmenu { };
#  libdbusmenu-gtk2 = callPackage ../development/libraries/libdbusmenu { gtkVersion = "2"; };
#  libdbusmenu-gtk3 = callPackage ../development/libraries/libdbusmenu { gtkVersion = "3"; };
#
#  libdbusmenu_qt = callPackage ../development/libraries/libdbusmenu-qt { };
#
  libdc1394 = callPackage ../development/libraries/libdc1394 { };

  libdiscid = callPackage ../development/libraries/libdiscid { };
#
#  libdivsufsort = callPackage ../development/libraries/libdivsufsort { };
#
#  libdmtx = callPackage ../development/libraries/libdmtx { };
#
#  libdnet = callPackage ../development/libraries/libdnet { };
#
#  libdv = callPackage ../development/libraries/libdv { };
#
  libdvbpsi = callPackage ../development/libraries/libdvbpsi { };
#
#  libdwg = callPackage ../development/libraries/libdwg { };
#
  libdvdcss = callPackage ../development/libraries/libdvdcss { };

  libdvdnav = callPackage ../development/libraries/libdvdnav { };
#  libdvdnav_4_2_1 = callPackage ../development/libraries/libdvdnav/4.2.1.nix {
#    libdvdread = libdvdread_4_9_9;
#  };
#
  libdvdread = callPackage ../development/libraries/libdvdread { };
#  libdvdread_4_9_9 = callPackage ../development/libraries/libdvdread/4.9.9.nix { };
#
#  libdwarf = callPackage ../development/libraries/libdwarf { };
#
#  libeatmydata = callPackage ../development/libraries/libeatmydata { };
#
#  libeb = callPackage ../development/libraries/libeb { };
#
#  libebur128 = callPackage ../development/libraries/libebur128 { };
#
  libedit = callPackage ../development/libraries/libedit { };
#
#  libetpan = callPackage ../development/libraries/libetpan { };
#
  libfaketime = callPackage ../development/libraries/libfaketime { };
#
#  libfakekey = callPackage ../development/libraries/libfakekey { };
#
#  libfm = callPackage ../development/libraries/libfm { };
#  libfm-extra = callPackage ../development/libraries/libfm {
#    extraOnly = true;
#  };
#
#  libfprint = callPackage ../development/libraries/libfprint { };
#
  libfpx = callPackage ../development/libraries/libfpx { };
#
#  libgadu = callPackage ../development/libraries/libgadu { };
#
#  libgig = callPackage ../development/libraries/libgig { };
#
  libgnome-keyring = callPackage ../development/libraries/libgnome-keyring { };
#
#  libgnurl = callPackage ../development/libraries/libgnurl { };
#
#  libgringotts = callPackage ../development/libraries/libgringotts { };
#
#  libgroove = callPackage ../development/libraries/libgroove { };
#
  libseccomp = callPackage ../development/libraries/libseccomp { };
#
#  libserialport = callPackage ../development/libraries/libserialport { };
#
#  libsoundio = callPackage ../development/libraries/libsoundio { };
#
  libgtop = callPackage ../development/libraries/libgtop {};
#
#  libLAS = callPackage ../development/libraries/libLAS { };
#
#  liblaxjson = callPackage ../development/libraries/liblaxjson { };
#
#  liblo = callPackage ../development/libraries/liblo { };
#
#  liblrdf = librdf;
#
#  liblscp = callPackage ../development/libraries/liblscp { };
#
#  libe-book = callPackage ../development/libraries/libe-book {};
#
#  libechonest = callPackage ../development/libraries/libechonest { };
#
#  libewf = callPackage ../development/libraries/libewf { };
#
  libexif = callPackage ../development/libraries/libexif { };
#
#  libexosip = callPackage ../development/libraries/exosip {};
#
#  libexosip_3 = callPackage ../development/libraries/exosip/3.x.nix {
#    libosip = libosip_3;
#  };
#
#  libextractor = callPackage ../development/libraries/libextractor {
#    libmpeg2 = mpeg2dec;
#  };
#
#  libexttextcat = callPackage ../development/libraries/libexttextcat {};
#
#  libf2c = callPackage ../development/libraries/libf2c {};
#
#  libfixposix = callPackage ../development/libraries/libfixposix {};
#
#  libffcall = callPackage ../development/libraries/libffcall { };
#
#
#  libfreefare = callPackage ../development/libraries/libfreefare { };
#
#  libftdi = callPackage ../development/libraries/libftdi { };
#
#  libftdi1 = callPackage ../development/libraries/libftdi/1.x.nix { };
#
#  libgdiplus = callPackage ../development/libraries/libgdiplus { };
#
#  libgsystem = callPackage ../development/libraries/libgsystem { };
#
#  libguestfs = callPackage ../development/libraries/libguestfs {
#    inherit (perlPackages) libintlperl GetoptLong SysVirt;
#  };
#
#  libhangul = callPackage ../development/libraries/libhangul { };
#
#  libharu = callPackage ../development/libraries/libharu { };
#
#  libHX = callPackage ../development/libraries/libHX { };
#
#  libibmad = callPackage ../development/libraries/libibmad { };
#
#  libibumad = callPackage ../development/libraries/libibumad { };
#
  libical = callPackage ../development/libraries/libical { };
#
#  libicns = callPackage ../development/libraries/libicns { };
#
  libimobiledevice = callPackage ../development/libraries/libimobiledevice { };
#
#  libindicate-gtk2 = callPackage ../development/libraries/libindicate { gtkVersion = "2"; };
#  libindicate-gtk3 = callPackage ../development/libraries/libindicate { gtkVersion = "3"; };
#
#  libindicator-gtk2 = callPackage ../development/libraries/libindicator { gtkVersion = "2"; };
#  libindicator-gtk3 = callPackage ../development/libraries/libindicator { gtkVersion = "3"; };
#
#  libiodbc = callPackage ../development/libraries/libiodbc {
#    useGTK = config.libiodbc.gtk or false;
#  };
#
#  libivykis = callPackage ../development/libraries/libivykis { };
#
#  liblastfmSF = callPackage ../development/libraries/liblastfmSF { };
#
#  liblastfm = callPackage ../development/libraries/liblastfm { };
#
  liblqr1 = callPackage ../development/libraries/liblqr-1 { };
#
#  liblockfile = callPackage ../development/libraries/liblockfile { };
#
#  liblogging = callPackage ../development/libraries/liblogging { };
#
#  liblognorm = callPackage ../development/libraries/liblognorm { };
#
#  libltc = callPackage ../development/libraries/libltc { };
#
  libmediainfo = callPackage ../development/libraries/libmediainfo { };
#
#  libmodbus = callPackage ../development/libraries/libmodbus {};
#
  libmtp = callPackage ../development/libraries/libmtp { };
#
  libnatspec = callPackage ../development/libraries/libnatspec { };
#
  libndp = callPackage ../development/libraries/libndp { };
#
#  libnfc = callPackage ../development/libraries/libnfc { };
#
#  libnfsidmap = callPackage ../development/libraries/libnfsidmap { };
#
#  libnice = callPackage ../development/libraries/libnice { };
#
#  liboping = callPackage ../development/libraries/liboping { };
#
  libplist = callPackage ../development/libraries/libplist { };
#
#  libqglviewer = callPackage ../development/libraries/libqglviewer { };
#
#  libre = callPackage ../development/libraries/libre {};
#  librem = callPackage ../development/libraries/librem {};
#
#  librelp = callPackage ../development/libraries/librelp { };
#
#  libresample = callPackage ../development/libraries/libresample {};
#
  librevenge = callPackage ../development/libraries/librevenge {};
#
#  librevisa = callPackage ../development/libraries/librevisa { };
#
  libsamplerate = callPackage ../development/libraries/libsamplerate { };
#
#  libsieve = callPackage ../development/libraries/libsieve { };
#
  libgsf = callPackage ../development/libraries/libgsf { };

  libid3tag = callPackage ../development/libraries/libid3tag { };

  libidn = callPackage ../development/libraries/libidn { };

  idnkit = callPackage ../development/libraries/idnkit { };

  libiec61883 = callPackage ../development/libraries/libiec61883 { };
#
#  libinfinity = callPackage ../development/libraries/libinfinity {
#    inherit (gnome) gtkdoc;
#  };
#
#  libiptcdata = callPackage ../development/libraries/libiptcdata { };
#
#  libjreen = callPackage ../development/libraries/libjreen { };
#
#  libjson_rpc_cpp = callPackage ../development/libraries/libjson-rpc-cpp { };
#
  libkate = callPackage ../development/libraries/libkate { };

  libksba = callPackage ../development/libraries/libksba { };
#
#  libksi = callPackage ../development/libraries/libksi { };
#
  libmad = callPackage ../development/libraries/libmad { };
#
#  libmatchbox = callPackage ../development/libraries/libmatchbox { };
#
#  libmatthew_java = callPackage ../development/libraries/java/libmatthew-java { };
#
#  libmcs = callPackage ../development/libraries/libmcs { };
#
#  libmemcached = callPackage ../development/libraries/libmemcached { };
#
  libmikmod = callPackage ../development/libraries/libmikmod { };
#
#  libmilter = callPackage ../development/libraries/libmilter { };
#
#  libmkv = callPackage ../development/libraries/libmkv { };
#
  libmms = callPackage ../development/libraries/libmms { };
#
#  libmowgli = callPackage ../development/libraries/libmowgli { };
#
  libmng = callPackage ../development/libraries/libmng { };

  libmodplug = callPackage ../development/libraries/libmodplug {};
#
#  libmp3splt = callPackage ../development/libraries/libmp3splt { };
#
#  libmrss = callPackage ../development/libraries/libmrss { };
#
#  libmsn = callPackage ../development/libraries/libmsn { };
#
#  libmspack = callPackage ../development/libraries/libmspack { };
#
#  libmusicbrainz2 = callPackage ../development/libraries/libmusicbrainz/2.x.nix { };
#
  libmusicbrainz3 = callPackage ../development/libraries/libmusicbrainz { };

  libmusicbrainz5 = callPackage ../development/libraries/libmusicbrainz/5.x.nix { };

  libmusicbrainz = libmusicbrainz3;
#
#  libmwaw = callPackage ../development/libraries/libmwaw { };
#
#  libmx = callPackage ../development/libraries/libmx { };
#
#  libnet = callPackage ../development/libraries/libnet { };
#
  libnetfilter_conntrack = callPackage ../development/libraries/libnetfilter_conntrack { };
#
#  libnetfilter_cthelper = callPackage ../development/libraries/libnetfilter_cthelper { };
#
#  libnetfilter_cttimeout = callPackage ../development/libraries/libnetfilter_cttimeout { };
#
#  libnetfilter_queue = callPackage ../development/libraries/libnetfilter_queue { };
#
  libnfnetlink = callPackage ../development/libraries/libnfnetlink { };

  libnftnl = callPackage ../development/libraries/libnftnl { };
#
#  libnih = callPackage ../development/libraries/libnih { };
#
#  libnova = callPackage ../development/libraries/libnova { };
#
#  libnxml = callPackage ../development/libraries/libnxml { };
#
#  libodfgen = callPackage ../development/libraries/libodfgen { };
#
#  libofa = callPackage ../development/libraries/libofa { };
#
#  libofx = callPackage ../development/libraries/libofx { };
#
  liboggz = callPackage ../development/libraries/liboggz { };
#
#  liboil = callPackage ../development/libraries/liboil { };
#
#  liboop = callPackage ../development/libraries/liboop { };
#
  libopus = callPackage ../development/libraries/libopus { };
#
#  libosip = callPackage ../development/libraries/osip {};
#
#  libosip_3 = callPackage ../development/libraries/osip/3.nix {};
#
#  libosmpbf = callPackage ../development/libraries/libosmpbf {};
#
#  libotr = callPackage ../development/libraries/libotr { };
#
#  libotr_3_2 = callPackage ../development/libraries/libotr/3.2.nix { };
#
#  libp11 = callPackage ../development/libraries/libp11 { };
#
#  libpar2 = callPackage ../development/libraries/libpar2 { };
#
  libpcap = callPackage ../development/libraries/libpcap { };

  libpipeline = callPackage ../development/libraries/libpipeline { };
#
#  libpgf = callPackage ../development/libraries/libpgf { };
#
  libpaper = callPackage ../development/libraries/libpaper { };
#
#  libpfm = callPackage ../development/libraries/libpfm { };
#
#  libpqxx = callPackage ../development/libraries/libpqxx { };
#
  libproxy = callPackage ../development/libraries/libproxy { };
#
#  libpseudo = callPackage ../development/libraries/libpseudo { };
#
#  libpsl = callPackage ../development/libraries/libpsl { };
#
#  libpst = callPackage ../development/libraries/libpst { };
#
  libpwquality = callPackage ../development/libraries/libpwquality { };
#
#  libqalculate = callPackage ../development/libraries/libqalculate { };
#
  libs3 = callPackage ../development/libraries/libs3 { };
#
#  libsearpc = callPackage ../development/libraries/libsearpc { };
#
libsndfile = callPackage ../development/libraries/libsndfile { };
#
libstartup_notification = callPackage ../development/libraries/startup-notification { };
#
#  libstroke = callPackage ../development/libraries/libstroke { };
#
#  libstrophe = callPackage ../development/libraries/libstrophe { };
#
#  libspatialindex = callPackage ../development/libraries/libspatialindex { };
#
#  libspatialite = callPackage ../development/libraries/libspatialite { };
#
#  libstatgrab = callPackage ../development/libraries/libstatgrab { };
#
#  libsvm = callPackage ../development/libraries/libsvm { };
#
#  libtar = callPackage ../development/libraries/libtar { };
#
libtasn1 = callPackage ../development/libraries/libtasn1 { };
#
libtiff = callPackage ../development/libraries/libtiff { };

  libtiger = callPackage ../development/libraries/libtiger { };
#
#  libtommath = callPackage ../development/libraries/libtommath { };
#
#  libtomcrypt = callPackage ../development/libraries/libtomcrypt { };
#
#  libtoxcore = callPackage ../development/libraries/libtoxcore/old-api { };
#
#  libtoxcore-dev = callPackage ../development/libraries/libtoxcore/new-api { };
#
#  libtap = callPackage ../development/libraries/libtap { };
#
#  libtsm = callPackage ../development/libraries/libtsm {
#    automake = automake114x;
#  };
#
#  libtunepimp = callPackage ../development/libraries/libtunepimp { };
#
  libtxc_dxtn = callPackage ../development/libraries/libtxc_dxtn { };
#
  libtxc_dxtn_s2tc = callPackage ../development/libraries/libtxc_dxtn_s2tc { };
#
#  libgeotiff = callPackage ../development/libraries/libgeotiff { };
#
#  libu2f-host = callPackage ../development/libraries/libu2f-host { };
#
#  libu2f-server = callPackage ../development/libraries/libu2f-server { };
#
  libunistring = callPackage ../development/libraries/libunistring { };

  libupnp = callPackage ../development/libraries/pupnp { };

  giflib = callPackageAlias "giflib_5_1" { };
  giflib_4_1 = callPackage ../development/libraries/giflib/4.1.nix { };
  giflib_5_1 = callPackage ../development/libraries/giflib/5.1.nix { };

  libungif = callPackage ../development/libraries/giflib/libungif.nix { };
#
#  libunibreak = callPackage ../development/libraries/libunibreak { };
#
  liburcu = callPackage ../development/libraries/liburcu { };
#
#  libutempter = callPackage ../development/libraries/libutempter { };
#
  libunwind = callPackage ../development/libraries/libunwind { };
#
  libuvVersions = recurseIntoAttrs (callPackage ../development/libraries/libuv { });

  libuv = libuvVersions.v1_8_0;

  v4l_lib = lowPrio (callPackageAlias "v4l_utils" {
    alsa-lib = null;
    libX11 = null;
    qt4 = null;
    qt5 = null;
  });
#
#  libvdpau-va-gl = callPackage ../development/libraries/libvdpau-va-gl { };
#
#  libvirt = callPackage ../development/libraries/libvirt { };
#
#  libvirt-glib = callPackage ../development/libraries/libvirt-glib { };
#
  libvisio = callPackage ../development/libraries/libvisio { };

  libvisual = callPackage ../development/libraries/libvisual { };
#
#  libvncserver = callPackage ../development/libraries/libvncserver {};
#
#  libviper = callPackage ../development/libraries/libviper { };
#
#  libvterm = callPackage ../development/libraries/libvterm { };
#
  libwebp = callPackage ../development/libraries/libwebp { };

  libwmf = callPackage ../development/libraries/libwmf { };
#
#  libwnck = libwnck2;
#  libwnck2 = callPackage ../development/libraries/libwnck { };
#  libwnck3 = callPackage ../development/libraries/libwnck/3.x.nix { };
#
  libwpd = callPackage ../development/libraries/libwpd { };
#
#  libwpd_08 = callPackage ../development/libraries/libwpd/0.8.nix { };
#
  libwpg = callPackage ../development/libraries/libwpg { };
#
#  libx86 = callPackage ../development/libraries/libx86 {};
#
#  libxdg_basedir = callPackage ../development/libraries/libxdg-basedir { };
#
  libxklavier = callPackage ../development/libraries/libxklavier { };
#
#  libxls = callPackage ../development/libraries/libxls { };
#
#  libxmi = callPackage ../development/libraries/libxmi { };
#
#  libxmlxx = callPackage ../development/libraries/libxmlxx { };
#
#  libxmp = callPackage ../development/libraries/libxmp { };
#
#  libixp_hg = callPackage ../development/libraries/libixp-hg { };
#
  libyaml = callPackage ../development/libraries/libyaml { };
#
#  libyamlcpp = callPackage ../development/libraries/libyaml-cpp { };
#
#  libykneomgr = callPackage ../development/libraries/libykneomgr { };
#
#  libyubikey = callPackage ../development/libraries/libyubikey { };
#
  libzen = callPackage ../development/libraries/libzen { };

  libzip = callPackage ../development/libraries/libzip { };
#
#  libzdb = callPackage ../development/libraries/libzdb { };
#
#  libzrtpcpp = callPackage ../development/libraries/libzrtpcpp { };
#
#  lightning = callPackage ../development/libraries/lightning { };
#
#  lightlocker = callPackage ../misc/screensavers/light-locker { };
#
  lirc = callPackage ../development/libraries/lirc { };
#
#  liquidfun = callPackage ../development/libraries/liquidfun { };
#
#  log4cpp = callPackage ../development/libraries/log4cpp { };
#
#  log4cxx = callPackage ../development/libraries/log4cxx { };
#
#  log4cplus = callPackage ../development/libraries/log4cplus { };
#
#  loudmouth = callPackage ../development/libraries/loudmouth { };
#
#  luabind = callPackage ../development/libraries/luabind { };
#
#  luabind_luajit = callPackage ../development/libraries/luabind { lua = luajit; };
#
#  mapnik = callPackage ../development/libraries/mapnik { };
#
#  matio = callPackage ../development/libraries/matio { };
#
#  mbedtls = callPackage ../development/libraries/mbedtls { };
#
#  mdds_0_7_1 = callPackage ../development/libraries/mdds/0.7.1.nix { };
#  mdds = callPackage ../development/libraries/mdds { };
#
#  mediastreamer = callPackage ../development/libraries/mediastreamer { };
#
#  mediastreamer-openh264 = callPackage ../development/libraries/mediastreamer/msopenh264.nix { };
#
#  menu-cache = callPackage ../development/libraries/menu-cache { };
#
#  meterbridge = callPackage ../applications/audio/meterbridge { };
#
#  mhddfs = callPackage ../tools/filesystems/mhddfs { };
#
#  ming = callPackage ../development/libraries/ming { };
#
#  minmay = callPackage ../development/libraries/minmay { };
#
#  miro = callPackage ../applications/video/miro {
#    inherit (pythonPackages) pywebkitgtk pycurl mutagen;
#  };
#
#  mlt-qt4 = callPackage ../development/libraries/mlt {
#    qt = qt4;
#  };
#
#  movit = callPackage ../development/libraries/movit { };
#
#  mosquitto = callPackage ../servers/mqtt/mosquitto { };
#
#  mps = callPackage ../development/libraries/mps { };
#
  libmpeg2 = callPackage ../development/libraries/libmpeg2 { };

#  msilbc = callPackage ../development/libraries/msilbc { };
#
#  mpich2 = callPackage ../development/libraries/mpich2 { };
#
#  mstpd = callPackage ../os-specific/linux/mstpd { };
#
  mtdev = callPackage ../development/libraries/mtdev { };
#
#  mtpfs = callPackage ../tools/filesystems/mtpfs { };
#
#  mueval = callPackage ../development/tools/haskell/mueval { };
#
#  muparser = callPackage ../development/libraries/muparser { };
#
#  mygpoclient = pythonPackages.mygpoclient;
#
#  mygui = callPackage ../development/libraries/mygui {};
#
#  mysocketw = callPackage ../development/libraries/mysocketw { };
#
#  mythes = callPackage ../development/libraries/mythes { };
#
#  nanomsg = callPackage ../development/libraries/nanomsg { };
#
#  neardal = callPackage ../development/libraries/neardal { };
#
  neon = callPackage ../development/libraries/neon {
    compressionSupport = true;
    sslSupport = true;
  };
#
#  neon_0_29 = callPackage ../development/libraries/neon/0.29.nix {
#    compressionSupport = true;
#    sslSupport = true;
#  };
#
  newt = callPackage ../development/libraries/newt { };

#
#  nix-plugins = callPackage ../development/libraries/nix-plugins {
#    nix = pkgs.nixUnstable;
#  };
#
#  nntp-proxy = callPackage ../applications/networking/nntp-proxy { };
#
#  non = callPackage ../applications/audio/non { };
#
  nspr = callPackage ../development/libraries/nspr { };

  nss = lowPrio (callPackage ../development/libraries/nss { });

  nss_wrapper = callPackage ../development/libraries/nss_wrapper { };
#
#  nssTools = callPackage ../development/libraries/nss {
#    includeTools = true;
#  };
#
#  ntk = callPackage ../development/libraries/audio/ntk { };
#
#  ntrack = callPackage ../development/libraries/ntrack { };
#
#  nvidia-texture-tools = callPackage ../development/libraries/nvidia-texture-tools { };
#
#  ode = callPackage ../development/libraries/ode { };
#
#  ogre = callPackage ../development/libraries/ogre {};
#
#  ogrepaged = callPackage ../development/libraries/ogrepaged { };
#
  oniguruma = callPackage ../development/libraries/oniguruma { };

  openal = callPackageAlias "openalSoft" { };
  openalSoft = callPackage ../development/libraries/openal-soft { };
#
#  openbabel = callPackage ../development/libraries/openbabel { };
#
#  opencascade = callPackage ../development/libraries/opencascade {
#    tcl = tcl-8_5;
#    tk = tk-8_5;
#  };
#
#  opencascade_6_5 = callPackage ../development/libraries/opencascade/6.5.nix {
#    automake = automake111x;
#    ftgl = ftgl212;
#  };
#
#  opencascade_oce = callPackage ../development/libraries/opencascade/oce.nix { };
#
#  opencollada = callPackage ../development/libraries/opencollada { };
#
#  opencsg = callPackage ../development/libraries/opencsg { };
#
#  openct = callPackage ../development/libraries/openct { };
#
  opencv = callPackage ../development/libraries/opencv { };
#
#  opencv3 = callPackage ../development/libraries/opencv/3.x.nix { };
#
#  # this ctl version is needed by openexr_viewers
#  openexr_ctl = ctl;
#
  openexr = callPackage ../development/libraries/openexr { };

#  opencolorio = callPackage ../development/libraries/opencolorio { };
#
#  ois = callPackage ../development/libraries/ois {};
#
#  opal = callPackage ../development/libraries/opal {};
#
  openh264 = callPackage ../development/libraries/openh264 { };
#
#  openjpeg_1 = callPackage ../development/libraries/openjpeg/1.x.nix { };
  openjpeg_2_0 = callPackage ../development/libraries/openjpeg/2.0.nix { };
  openjpeg_2_1 = callPackage ../development/libraries/openjpeg/2.1.nix { };
  openjpeg = callPackageAlias "openjpeg_2_1" { };
#
#  openscenegraph = callPackage ../development/libraries/openscenegraph {
#    giflib = giflib_4_1;
#    ffmpeg = ffmpeg_0;
#  };
#
#  openslp = callPackage ../development/libraries/openslp {};
#
#  # 2.3 breaks some backward-compability
#  libressl = libressl_2_2;
#  libressl_2_2 = callPackage ../development/libraries/libressl/2.2.nix { };
#  libressl_2_3 = callPackage ../development/libraries/libressl/2.3.nix { };
#
#  boringssl = callPackage ../development/libraries/boringssl { };
#
#  wolfssl = callPackage ../development/libraries/wolfssl { };
#
#  opensubdiv = callPackage ../development/libraries/opensubdiv { };
#
#  openwsman = callPackage ../development/libraries/openwsman {};
#
#  ortp = callPackage ../development/libraries/ortp { };
#
  p11_kit = callPackage ../development/libraries/p11-kit { };
#
#  paperkey = callPackage ../tools/security/paperkey { };
#
#  pangoxsl = callPackage ../development/libraries/pangoxsl { };
#
#  pcg_c = callPackage ../development/libraries/pcg-c { };
#
#  pcl = callPackage ../development/libraries/pcl {
#    vtk = vtkWithQt4;
#  };
#
  phonon = callPackage ../development/libraries/phonon/qt4 {};
#
#  phonon_backend_gstreamer = callPackage ../development/libraries/phonon-backend-gstreamer/qt4 {};
#
#  phonon_backend_vlc = callPackage ../development/libraries/phonon-backend-vlc/qt4 {};
#
#  physfs = callPackage ../development/libraries/physfs { };
#
#  pipelight = callPackage ../tools/misc/pipelight {
#    stdenv = stdenv_32bit;
#    wineStaging = pkgsi686Linux.wineStaging;
#  };
#
#  pkcs11helper = callPackage ../development/libraries/pkcs11helper { };
#
#  plib = callPackage ../development/libraries/plib { };
#
#  pocketsphinx = callPackage ../development/libraries/pocketsphinx { };
#
#  podofo = callPackage ../development/libraries/podofo { };
#
#  poker-eval = callPackage ../development/libraries/poker-eval { };
#
#  polarssl = mbedtls;
#
  polkit = callPackage ../development/libraries/polkit { };
#
#  polkit_qt4 = callPackage ../development/libraries/polkit-qt-1 { };
#
  popt = callPackage ../development/libraries/popt { };

  portaudio = callPackage ../development/libraries/portaudio { };
#
#  portaudioSVN = callPackage ../development/libraries/portaudio/svn-head.nix { };
#
  portmidi = callPackage ../development/libraries/portmidi { };
#
#  prison = callPackage ../development/libraries/prison { };
#
#  proj = callPackage ../development/libraries/proj { };
#
#  postgis = callPackage ../development/libraries/postgis { };
#
  protobuf = callPackageAlias "protobuf2_6" { };
  protobuf3_0 = lowPrio (callPackage ../development/libraries/protobuf/3.0.nix { });
  protobuf2_6 = callPackage ../development/libraries/protobuf/2.6.nix { };
#  protobuf2_5 = callPackage ../development/libraries/protobuf/2.5.nix { };
#
#  protobufc = protobufc1_1;
#  protobufc1_1 = callPackage ../development/libraries/protobufc/1.1.nix { };
#  protobufc1_0 = callPackage ../development/libraries/protobufc/1.0.nix { };
#
  pth = callPackage ../development/libraries/pth { };
#
#  ptlib = callPackage ../development/libraries/ptlib {};
#
#  re2 = callPackage ../development/libraries/re2 { };
#
#  qca2 = callPackage ../development/libraries/qca2 { qt = qt4; };
#
#  qimageblitz = callPackage ../development/libraries/qimageblitz {};
#
#  qjson = callPackage ../development/libraries/qjson { };
#
#  qoauth = callPackage ../development/libraries/qoauth { };
#
#  qt3 = callPackage ../development/libraries/qt-3 {
#    libpng = libpng12;
#  };

  qt54 =
    let imported = import ../development/libraries/qt-5/5.4 { inherit pkgs; };
    in recurseIntoAttrs (imported.override (super: pkgs.qt5LibsFun));

  qt55 =
    let imported = import ../development/libraries/qt-5/5.5 { inherit pkgs; };
    in recurseIntoAttrs (imported.override (super: pkgs.qt5LibsFun));

  qt5 = pkgs.qt55;

  qt5LibsFun = self: let inherit (self) callPackage; in {

#    accounts-qt = callPackage ../development/libraries/accounts-qt { };
#
#    grantlee = callPackage ../development/libraries/grantlee/5.x.nix { };
#
    libdbusmenu = callPackage ../development/libraries/libdbusmenu-qt/qt-5.5.nix { };
#
#    libkeyfinder = callPackage ../development/libraries/libkeyfinder { };
#
#    mlt = callPackage ../development/libraries/mlt/qt-5.nix {};
#
#    openbr = callPackage ../development/libraries/openbr { };
#
#    phonon = callPackage ../development/libraries/phonon/qt5 { };
#
#    phonon-backend-gstreamer = callPackage ../development/libraries/phonon-backend-gstreamer/qt5 { };
#
#    phonon-backend-vlc = callPackage ../development/libraries/phonon-backend-vlc/qt5 { };
#
    polkit-qt = callPackage ../development/libraries/polkit-qt-1 {
      withQt5 = true;
    };
#
#    poppler = callPackage ../development/libraries/poppler {
#      lcms = lcms2;
#      qt5Support = true;
#      suffix = "qt5";
#    };
#
    qca-qt5 = callPackage ../development/libraries/qca-qt5 { };
#
#    qmltermwidget = callPackage ../development/libraries/qmltermwidget { };
#
#    qtcreator = callPackage ../development/qtcreator {
#      withDocumentation = true;
#    };
#
    quazip = callPackage ../development/libraries/quazip {
      qt = qtbase;
    };
#
#    qwt = callPackage ../development/libraries/qwt/6.nix { };
#
#    signon = callPackage ../development/libraries/signon { };
#
#    telepathy = callPackage ../development/libraries/telepathy/qt { };

  };
#
  qtEnv = qt5.env;
  qt5Full = qt5.full;
#
#  qtkeychain = callPackage ../development/libraries/qtkeychain { };
#
#  qtscriptgenerator = callPackage ../development/libraries/qtscriptgenerator { };
#
#  quesoglc = callPackage ../development/libraries/quesoglc { };
#
#  quicksynergy = callPackage ../applications/misc/quicksynergy { };
#
#  qwt = callPackage ../development/libraries/qwt {};
#
#  qxt = callPackage ../development/libraries/qxt {};
#
#  rabbitmq-c = callPackage ../development/libraries/rabbitmq-c {};
#
#  rabbitmq-c_0_4 = callPackage ../development/libraries/rabbitmq-c/0.4.nix {};
#
#  rabbitmq-java-client = callPackage ../development/libraries/rabbitmq-java-client {};
#
#  raul = callPackage ../development/libraries/audio/raul { };
#
#  readosm = callPackage ../development/libraries/readosm { };
#
#  lambdabot = callPackage ../development/tools/haskell/lambdabot {
#    haskell-lib = haskell.lib;
#  };
#
#  leksah = callPackage ../development/tools/haskell/leksah {
#    inherit (haskellPackages) ghcWithPackages;
#  };
#
#  librdf_raptor = callPackage ../development/libraries/librdf/raptor.nix { };
#
  librdf_raptor2 = callPackage ../development/libraries/librdf/raptor2.nix { };
#
#  librdf_rasqal = callPackage ../development/libraries/librdf/rasqal.nix { };
#
#  librdf_redland = callPackage ../development/libraries/librdf/redland.nix { };
#
#  librdf = callPackage ../development/libraries/librdf { };
#
#  libsmf = callPackage ../development/libraries/audio/libsmf { };
#
#  lilv = callPackage ../development/libraries/audio/lilv { };
#  lilv-svn = callPackage ../development/libraries/audio/lilv/lilv-svn.nix { };
#
#  lv2 = callPackage ../development/libraries/audio/lv2 { };
#
#  lvtk = callPackage ../development/libraries/audio/lvtk { };
#
#  qrupdate = callPackage ../development/libraries/qrupdate { };
#
#  redland = pkgs.librdf_redland;
#
  resolv_wrapper = callPackage ../development/libraries/resolv_wrapper { };
#
#  rhino = callPackage ../development/libraries/java/rhino {
#    javac = gcj;
#    jvm = gcj;
#  };
#
#  rlog = callPackage ../development/libraries/rlog { };
#
#  rote = callPackage ../development/libraries/rote { };
#
  rubberband = callPackage ../development/libraries/rubberband { };
#
  sbc = callPackage ../development/libraries/sbc { };
#
  schroedinger = callPackage ../development/libraries/schroedinger { };

  SDL = callPackage ../development/libraries/SDL { };
#
#  SDL_gfx = callPackage ../development/libraries/SDL_gfx { };
#
  SDL_image = callPackage ../development/libraries/SDL_image { };
#
#  SDL_mixer = callPackage ../development/libraries/SDL_mixer { };
#
#  SDL_net = callPackage ../development/libraries/SDL_net { };
#
#  SDL_sound = callPackage ../development/libraries/SDL_sound { };
#
#  SDL_stretch= callPackage ../development/libraries/SDL_stretch { };
#
#  SDL_ttf = callPackage ../development/libraries/SDL_ttf { };
#
  SDL2 = callPackage ../development/libraries/SDL2 { };
#
#  SDL2_image = callPackage ../development/libraries/SDL2_image { };
#
#  SDL2_mixer = callPackage ../development/libraries/SDL2_mixer { };
#
#  SDL2_net = callPackage ../development/libraries/SDL2_net { };
#
#  SDL2_gfx = callPackage ../development/libraries/SDL2_gfx { };
#
#  SDL2_ttf = callPackage ../development/libraries/SDL2_ttf { };
#
#  sblim-sfcc = callPackage ../development/libraries/sblim-sfcc {};
#
#  serd = callPackage ../development/libraries/serd {};
#
#  sfsexp = callPackage ../development/libraries/sfsexp {};
#
#  shhmsg = callPackage ../development/libraries/shhmsg { };
#
#  shhopt = callPackage ../development/libraries/shhopt { };
#
#  silgraphite = callPackage ../development/libraries/silgraphite {};
  graphite2 = callPackage ../development/libraries/silgraphite/graphite2.nix {};
#
#  simgear = callPackage ../development/libraries/simgear { };
#
#  simp_le = callPackage ../tools/admin/simp_le { };
#
#  sfml = callPackage ../development/libraries/sfml { };
#
#  skalibs = callPackage ../development/libraries/skalibs { };
#
  slang = callPackage ../development/libraries/slang { };
#
#  smpeg = callPackage ../development/libraries/smpeg { };
#
#  snack = callPackage ../development/libraries/snack {
#        # optional
#  };
#
  socket_wrapper = callPackage ../development/libraries/socket_wrapper { };
#
#  sofia_sip = callPackage ../development/libraries/sofia-sip { };
#
#  soprano = callPackage ../development/libraries/soprano { };
#
#  soqt = callPackage ../development/libraries/soqt { };
#
#  sord = callPackage ../development/libraries/sord {};
#  sord-svn = callPackage ../development/libraries/sord/sord-svn.nix {};
#
  soundtouch = callPackage ../development/libraries/soundtouch {};

  spandsp = callPackage ../development/libraries/spandsp {};
#
#  spatialite_tools = callPackage ../development/libraries/spatialite-tools { };
#
  speechd = callPackage ../development/libraries/speechd { };
#
#  speech_tools = callPackage ../development/libraries/speech-tools {};
#
  speex = callPackage ../development/libraries/speex { };

  speexdsp = callPackage ../development/libraries/speexdsp { };
#
#  sphinxbase = callPackage ../development/libraries/sphinxbase { };
#
#  sphinxsearch = callPackage ../servers/search/sphinxsearch { };
#
#  spice = callPackage ../development/libraries/spice {
#    celt = celt_0_5_1;
#    inherit (pythonPackages) pyparsing;
#  };
#
#  spice_gtk = callPackage ../development/libraries/spice-gtk { };
#
#  spice_protocol = callPackage ../development/libraries/spice-protocol { };
#
#  sratom = callPackage ../development/libraries/audio/sratom { };
#
#  srm = callPackage ../tools/security/srm { };
#
#  srtp = callPackage ../development/libraries/srtp { };
#
#  stxxl = callPackage ../development/libraries/stxxl { parallel = true; };
#
#  sqlite-amalgamation = callPackage ../development/libraries/sqlite-amalgamation { };
#
  sqlite-interactive = sqlite;

#  sqlcipher = lowPrio (callPackage ../development/libraries/sqlcipher {
#    readline = null;
#    ncurses = null;
#  });
#
#  stfl = callPackage ../development/libraries/stfl { };
#
#  stlink = callPackage ../development/tools/misc/stlink { };
#
#  steghide = callPackage ../tools/security/steghide {};
#
#  stlport = callPackage ../development/libraries/stlport { };
#
#  strigi = callPackage ../development/libraries/strigi { clucene_core = clucene_core_2; };
#
#  subtitleeditor = callPackage ../applications/video/subtitleeditor { };
#
#  suil = callPackage ../development/libraries/audio/suil { };
#
#  sutils = callPackage ../tools/misc/sutils { };
#
#  svrcore = callPackage ../development/libraries/svrcore { };
#
#  sword = callPackage ../development/libraries/sword { };
#
#  biblesync = callPackage ../development/libraries/biblesync { };
#
#  szip = callPackage ../development/libraries/szip { };
#
  t1lib = callPackage ../development/libraries/t1lib { };

  taglib = callPackage ../development/libraries/taglib { };
#  taglib_1_9 = callPackage ../development/libraries/taglib/1.9.nix { };
#
#  taglib_extras = callPackage ../development/libraries/taglib-extras { };
#
#  tclap = callPackage ../development/libraries/tclap {};
#
#  tclgpg = callPackage ../development/libraries/tclgpg { };
#
#  tcllib = callPackage ../development/libraries/tcllib { };
#
#  tcltls = callPackage ../development/libraries/tcltls { };
#
#  ntdb = callPackage ../development/libraries/ntdb { };
#
#  tecla = callPackage ../development/libraries/tecla { };
#
  telepathy_glib = callPackage ../development/libraries/telepathy/glib { };
#
#  telepathy_farstream = callPackage ../development/libraries/telepathy/farstream {};
#
#  telepathy_qt = callPackage ../development/libraries/telepathy/qt { qtbase = qt4; };
#
#  tet = callPackage ../development/tools/misc/tet { };
#
#  thrift = callPackage ../development/libraries/thrift {
#    inherit (pythonPackages) twisted;
#  };
#
#  tidyp = callPackage ../development/libraries/tidyp { };
#
  tinyxml2 = callPackage ../development/libraries/tinyxml/2.6.2.nix { };
#
#  tk = tk-8_6;
#
#  tk-8_6 = callPackage ../development/libraries/tk/8.6.nix { };
#  tk-8_5 = callPackage ../development/libraries/tk/8.5.nix { tcl = tcl-8_5; };
#
#  tnt = callPackage ../development/libraries/tnt { };
#
  kyotocabinet = callPackage ../development/libraries/kyotocabinet { };
#
#  tokyocabinet = callPackage ../development/libraries/tokyo-cabinet { };
#
#  tokyotyrant = callPackage ../development/libraries/tokyo-tyrant { };
#
  uid_wrapper = callPackage ../development/libraries/uid_wrapper { };
#
#  unibilium = callPackage ../development/libraries/unibilium { };
#
#  unicap = callPackage ../development/libraries/unicap {};
#
#  tsocks = callPackage ../development/libraries/tsocks { };
#
unixODBC = callPackage ../development/libraries/unixODBC { };
#
#  unixODBCDrivers = recurseIntoAttrs (callPackages ../development/libraries/unixODBCDrivers {});
#
#  urt = callPackage ../development/libraries/urt { };
#
#  ustr = callPackage ../development/libraries/ustr { };
#
#  usbredir = callPackage ../development/libraries/usbredir { };
#
  uthash = callPackage ../development/libraries/uthash { };
#
#  ucommon = ucommon_openssl;
#
#  ucommon_openssl = callPackage ../development/libraries/ucommon {
#    gnutls = null;
#  };
#
#  ucommon_gnutls = lowPrio (ucommon.override {
#    openssl = null;
#    zlib = null;
#    gnutls = gnutls;
#  });
#
#  v8_3_16_14 = callPackage ../development/libraries/v8/3.16.14.nix {
#    inherit (pythonPackages) gyp;
#    # The build succeeds using gcc5 but it fails to build pkgs.consul-ui
#    stdenv = overrideCC stdenv gcc48;
#  };
#
#  v8_3_24_10 = callPackage ../development/libraries/v8/3.24.10.nix {
#    inherit (pythonPackages) gyp;
#  };
#
#  v8_4_5 = callPackage ../development/libraries/v8/4.5.nix {
#    inherit (pythonPackages) gyp;
#  };
#
#  v8 = callPackage ../development/libraries/v8 {
#    inherit (pythonPackages) gyp;
#  };
#
  vaapiIntel = callPackage ../development/libraries/vaapi-intel { };
#
  vaapiVdpau = callPackage ../development/libraries/vaapi-vdpau { };
#
  vamp = callPackage ../development/libraries/audio/vamp { };
#
#  vc = callPackage ../development/libraries/vc { };
#
#  vc_0_7 = callPackage ../development/libraries/vc/0.7.nix { };
#
#  vcdimager = callPackage ../development/libraries/vcdimager { };
#
#  vid-stab = callPackage ../development/libraries/vid-stab { };
#
#  virglrenderer = callPackage ../development/libraries/virglrenderer { };
#
#  vigra = callPackage ../development/libraries/vigra {
#    inherit (pkgs.pythonPackages) numpy;
#  };
#
#  vlock = callPackage ../misc/screensavers/vlock { };
#
#  vmime = callPackage ../development/libraries/vmime { };
#
#  vrpn = callPackage ../development/libraries/vrpn { };
#
#  vtk = callPackage ../development/libraries/vtk { };
#
#  vtkWithQt4 = vtk.override { qtLib = qt4; };
#
#  vxl = callPackage ../development/libraries/vxl {
#    libpng = libpng12;
#  };
#
  wavpack = callPackage ../development/libraries/wavpack { };
#
#  websocketpp = callPackage ../development/libraries/websocket++ { };
#
  webrtc-audio-processing = callPackage ../development/libraries/webrtc-audio-processing { };
#
#  wildmidi = callPackage ../development/libraries/wildmidi { };
#
#  wiredtiger = callPackage ../development/libraries/wiredtiger { };
#
#  wxGTK28 = callPackage ../development/libraries/wxGTK-2.8 { };
#
#  wxGTK29 = callPackage ../development/libraries/wxGTK-2.9/default.nix { };
#
#  wxmac = callPackage ../development/libraries/wxmac { };
#
#  wtk = callPackage ../development/libraries/wtk { };
#
#  xapian = callPackage ../development/libraries/xapian { };
#
#  xapianBindings = callPackage ../development/libraries/xapian/bindings {  # TODO perl php Java, tcl, C#, python
#  };
#
#  xapian10 = callPackage ../development/libraries/xapian/1.0.x.nix { };
#
#  xapianBindings10 = callPackage ../development/libraries/xapian/bindings/1.0.x.nix {  # TODO perl php Java, tcl, C#, python
#  };
#
#  xapian-omega = callPackage ../tools/misc/xapian-omega {};
#
#  xavs = callPackage ../development/libraries/xavs { };
#
#  Xaw3d = callPackage ../development/libraries/Xaw3d { };
#
#  xbase = callPackage ../development/libraries/xbase { };
#
#  xcb-util-cursor-HEAD = callPackage ../development/libraries/xcb-util-cursor/HEAD.nix { };
#
#  xdo = callPackage ../tools/misc/xdo { };
#
#  xautolock = callPackage ../misc/screensavers/xautolock { };
#
#  xercesc = callPackage ../development/libraries/xercesc {};
#
#  # Avoid using this. It isn't really a wrapper anymore, but we keep the name.
  xlibsWrapper = callPackage ../development/libraries/xlibs-wrapper {
    packages = with pkgs; [
      freetype fontconfig xorg.xproto xorg.libX11 xorg.libXt
      xorg.libXft xorg.libXext xorg.libSM xorg.libICE
      xorg.xextproto
    ];
  };
#
  xmlrpc_c = callPackage ../development/libraries/xmlrpc-c { };
#
#  xmlsec = callPackage ../development/libraries/xmlsec { };
#
#  xlslib = callPackage ../development/libraries/xlslib { };
#
  xvidcore = callPackage ../development/libraries/xvidcore { };
#
#  xylib = callPackage ../development/libraries/xylib { };
#
  yajl = callPackage ../development/libraries/yajl { };
#
#  yubico-piv-tool = callPackage ../tools/misc/yubico-piv-tool { };
#
#  yubikey-personalization = callPackage ../tools/misc/yubikey-personalization { };
#
#  yubikey-personalization-gui = callPackage ../tools/misc/yubikey-personalization-gui {
#    qt = qt4;
#  };
#
#  zlog = callPackage ../development/libraries/zlog { };
#
#  zlibStatic = lowPrio (appendToName "static" (callPackage ../development/libraries/zlib {
#    static = true;
#  }));
#
#  zeromq2 = callPackage ../development/libraries/zeromq/2.x.nix {};
#  zeromq3 = callPackage ../development/libraries/zeromq/3.x.nix {};
#  zeromq4 = callPackage ../development/libraries/zeromq/4.x.nix {};
#  zeromq = zeromq4;
#
#  cppzmq = callPackage ../development/libraries/cppzmq {};
#
#  czmq = callPackage ../development/libraries/czmq { };
#
#  zimlib = callPackage ../development/libraries/zimlib { };
#
#  zita-convolver = callPackage ../development/libraries/audio/zita-convolver { };
#
#  zita-alsa-pcmi = callPackage ../development/libraries/audio/zita-alsa-pcmi { };
#
#  zita-resampler = callPackage ../development/libraries/audio/zita-resampler { };
#
  zziplib = callPackage ../development/libraries/zziplib { };
#
#  ### DEVELOPMENT / LIBRARIES / JAVA
#
#  atermjava = callPackage ../development/libraries/java/aterm {
#    stdenv = overrideInStdenv stdenv [gnumake380];
#  };
#
#  commonsBcel = callPackage ../development/libraries/java/commons/bcel { };
#
#  commonsBsf = callPackage ../development/libraries/java/commons/bsf { };
#
#  commonsCompress = callPackage ../development/libraries/java/commons/compress { };
#
#  commonsFileUpload = callPackage ../development/libraries/java/commons/fileupload { };
#
#  commonsLang = callPackage ../development/libraries/java/commons/lang { };
#
#  commonsLogging = callPackage ../development/libraries/java/commons/logging { };
#
#  commonsIo = callPackage ../development/libraries/java/commons/io { };
#
#  commonsMath = callPackage ../development/libraries/java/commons/math { };
#
#  fastjar = callPackage ../development/tools/java/fastjar { };
#
#  httpunit = callPackage ../development/libraries/java/httpunit { };
#
#  gwtdragdrop = callPackage ../development/libraries/java/gwt-dragdrop { };
#
#  gwtwidgets = callPackage ../development/libraries/java/gwt-widgets { };
#
#  javaCup = callPackage ../development/libraries/java/cup { };
#
#  javasvn = callPackage ../development/libraries/java/javasvn { };
#
#  jclasslib = callPackage ../development/tools/java/jclasslib { };
#
#  jdom = callPackage ../development/libraries/java/jdom { };
#
#  jflex = callPackage ../development/libraries/java/jflex { };
#
#  jjtraveler = callPackage ../development/libraries/java/jjtraveler {
#    stdenv = overrideInStdenv stdenv [gnumake380];
#  };
#
#  junit = callPackage ../development/libraries/java/junit { antBuild = releaseTools.antBuild; };
#
#  junixsocket = callPackage ../development/libraries/java/junixsocket { };
#
#  jzmq = callPackage ../development/libraries/java/jzmq { };
#
#  lucene = callPackage ../development/libraries/java/lucene { };
#
#  lucenepp = callPackage ../development/libraries/lucene++ {
#    boost = boost155;
#  };
#
#  mockobjects = callPackage ../development/libraries/java/mockobjects { };
#
#  saxon = callPackage ../development/libraries/java/saxon { };
#
#  saxonb = callPackage ../development/libraries/java/saxon/default8.nix { };
#
#  sharedobjects = callPackage ../development/libraries/java/shared-objects {
#    stdenv = overrideInStdenv stdenv [gnumake380];
#  };
#
#  smack = callPackage ../development/libraries/java/smack { };
#
#  swt = callPackage ../development/libraries/java/swt { };
#
#
#  ### DEVELOPMENT / LIBRARIES / JAVASCRIPT
#
#  jquery = callPackage ../development/libraries/javascript/jquery { };
#
#  jquery-ui = callPackage ../development/libraries/javascript/jquery-ui { };
#
#  yuicompressor = callPackage ../development/tools/yuicompressor { };
#
#  ### DEVELOPMENT / GO MODULES
#
  go16Packages = callPackage ./go-packages.nix {
    go = callPackageAlias "go_1_6" { };
    buildGoPackage = callPackage ../development/go-modules/generic {
      go = callPackageAlias "go_1_6" { };
      govers = (callPackageAlias "go16Packages" { }).govers.bin;
    };
    overrides = (config.goPackageOverrides or (p: {})) pkgs;
  };

  goPackages = callPackageAlias "go16Packages" { };
#
#  ### DEVELOPMENT / LISP MODULES
#
#  asdf = callPackage ../development/lisp-modules/asdf {
#    texLive = null;
#  };
#
#  clwrapperFunction = callPackage ../development/lisp-modules/clwrapper;
#
#  wrapLisp = lisp: clwrapperFunction { inherit lisp; };
#
#  lispPackagesFor = clwrapper: callPackage ../development/lisp-modules/lisp-packages.nix {
#    inherit clwrapper;
#  };
#
#  lispPackagesSBCL = lispPackagesFor (wrapLisp sbcl);
#  lispPackages = recurseIntoAttrs lispPackagesSBCL;
#
#
#  ### DEVELOPMENT / PERL MODULES
#
  buildPerlPackage = callPackage ../development/perl-modules/generic { };

  perlPackages = recurseIntoAttrs (callPackage ./perl-packages.nix {
    overrides = (config.perlPackageOverrides or (p: {})) pkgs;
  });

#  ack = perlPackages.ack;
#
#  perlcritic = perlPackages.PerlCritic;
#
#  sqitchPg = callPackage ../development/tools/misc/sqitch {
#    name = "sqitch-pg";
#    databaseModule = perlPackages.DBDPg;
#    sqitchModule = perlPackages.AppSqitch;
#  };
#
#  ### DEVELOPMENT / PYTHON MODULES
#
#  foursuite = pythonPackages.foursuite;
#
#  bsddb3 = pythonPackages.bsddb3;
#
#  ecdsa = pythonPackages.ecdsa;
#
#  pycairo = pythonPackages.pycairo;
#
#  pycapnp = pythonPackages.pycapnp;
#
#  pycrypto = pythonPackages.pycrypto;
#
#  pycups = pythonPackages.pycups;
#
#  pyexiv2 = callPackage ../development/python-modules/pyexiv2 { };
#
#  pygame = pythonPackages.pygame;
#
#  pygtksourceview = pythonPackages.pygtksourceview;
#
#  pyGtkGlade = pythonPackages.pyGtkGlade;
#
#  pylint = pythonPackages.pylint;
#
#  pyopenssl = pythonPackages.pyopenssl;
#
#  rhpl = callPackage ../development/python-modules/rhpl { };
#
#  pyqt4 = pythonPackages.pyqt4;
#
#  pysideApiextractor = pythonPackages.pysideApiextractor;
#
#  pysideGeneratorrunner = pythonPackages.pysideGeneratorrunner;
#
#  pyside = pythonPackages.pyside;
#
#  pysideTools = pythonPackages.pysideTools;
#
#  pysideShiboken = pythonPackages.pysideShiboken;
#
  pyxml = callPackage ../development/python-modules/pyxml { };
#
#  rbtools = pythonPackages.rbtools;
#
#  setuptools = pythonPackages.setuptools;
#
#  slowaes = pythonPackages.slowaes;
#
#  wxPython = pythonPackages.wxPython;
#  wxPython28 = pythonPackages.wxPython28;
#
#  twisted = pythonPackages.twisted;
#
#  ZopeInterface = pythonPackages.zope_interface;
#
#  ### SERVERS
#
#  "389-ds-base" = callPackage ../servers/ldap/389 { };
#
#  rdf4store = callPackage ../servers/http/4store { };
#
  apache-httpd = callPackage ../all-pkgs/apache-httpd  { };

  apacheHttpdPackagesFor = apacheHttpd: self: let callPackage = newScope self; in {
    inherit apacheHttpd;

    mod_dnssd = callPackage ../servers/http/apache-modules/mod_dnssd { };
#
#    mod_evasive = callPackage ../servers/http/apache-modules/mod_evasive { };
#
#    mod_fastcgi = callPackage ../servers/http/apache-modules/mod_fastcgi { };
#
#    mod_python = callPackage ../servers/http/apache-modules/mod_python { };
#
#    mod_wsgi = callPackage ../servers/http/apache-modules/mod_wsgi { };
#
#    php = pkgs.php.override { inherit apacheHttpd; };
#
#    subversion = pkgs.subversion.override { httpServer = true; inherit apacheHttpd; };
  };
#
  apacheHttpdPackages = pkgs.apacheHttpdPackagesFor pkgs.apacheHttpd pkgs.apacheHttpdPackages;
#
#  archiveopteryx = callPackage ../servers/mail/archiveopteryx/default.nix { };
#
#  cadvisor = callPackage ../servers/monitoring/cadvisor { };
#
#  cassandra_1_2 = callPackage ../servers/nosql/cassandra/1.2.nix { };
#  cassandra_2_0 = callPackage ../servers/nosql/cassandra/2.0.nix { };
#  cassandra_2_1 = callPackage ../servers/nosql/cassandra/2.1.nix { };
#  cassandra = cassandra_2_1;
#
#  apache-jena = callPackage ../servers/nosql/apache-jena/binary.nix {
#    java = jdk;
#  };
#
#  apcupsd = callPackage ../servers/apcupsd { };
#
#  asterisk = callPackage ../servers/asterisk { };
#
#  sabnzbd = callPackage ../servers/sabnzbd { };
#
  bind = callPackage ../servers/dns/bind { };

  dnsutils = callPackageAlias "bind" {
    suffix = "tools";
  };
#
#  bird = callPackage ../servers/bird { };
#
#  bosun = (callPackage ../servers/monitoring/bosun { }).bin // { outputs = [ "bin" ]; };
#  scollector = bosun;
#
#  charybdis = callPackage ../servers/irc/charybdis {};
#
#  couchdb = callPackage ../servers/http/couchdb {
#    python = python27;
#    sphinx = python27Packages.sphinx;
#    erlang = erlangR16;
#  };
#
#  dico = callPackage ../servers/dico { };
#
#  dict = callPackage ../servers/dict {
#      libmaa = callPackage ../servers/dict/libmaa.nix {};
#  };
#
#  dictdDBs = recurseIntoAttrs (callPackages ../servers/dict/dictd-db.nix {});
#
#  dictDBCollector = callPackage ../servers/dict/dictd-db-collector.nix {};
#
#  dictdWiktionary = callPackage ../servers/dict/dictd-wiktionary.nix {};
#
#  dictdWordnet = callPackage ../servers/dict/dictd-wordnet.nix {};
#
#  diod = callPackage ../servers/diod { };
#
#  dnschain = callPackage ../servers/dnschain { };
#
#  dovecot = dovecot22;
#
#  dovecot21 = callPackage ../servers/mail/dovecot { };
#
#  dovecot22 = callPackage ../servers/mail/dovecot/2.2.x.nix { };
#
#  dovecot_pigeonhole = callPackage ../servers/mail/dovecot/plugins/pigeonhole {
#    dovecot = dovecot22;
#  };
#
#  dovecot_antispam = callPackage ../servers/mail/dovecot/plugins/antispam { };
#
#  dspam = callPackage ../servers/mail/dspam {
#    inherit (perlPackages) NetSMTP;
#  };
#
#  etcd = pkgs.goPackages.etcd.bin // { outputs = [ "bin" ]; };
#
#  ejabberd = callPackage ../servers/xmpp/ejabberd { };
#
#  prosody = callPackage ../servers/xmpp/prosody {
#    inherit (lua51Packages) luasocket luasec luaexpat luafilesystem luabitop luaevent luazlib;
#  };
#
#  elasticmq = callPackage ../servers/elasticmq { };
#
#  eventstore = callPackage ../servers/nosql/eventstore {
#    v8 = v8_3_24_10;
#  };
#
#  etcdctl = etcd;
#
#  exim = callPackage ../servers/mail/exim { };
#
#  fcgiwrap = callPackage ../servers/fcgiwrap { };
#
#  felix = callPackage ../servers/felix { };
#
#  felix_remoteshell = callPackage ../servers/felix/remoteshell.nix { };
#
#  fingerd_bsd = callPackage ../servers/fingerd/bsd-fingerd { };
#
#  firebird = callPackage ../servers/firebird { icu = null; };
#  firebirdSuper = callPackage ../servers/firebird { superServer = true; };
#
#  fleet = callPackage ../servers/fleet { };
#
#  freepops = callPackage ../servers/mail/freepops { };
#
#  freeswitch = callPackage ../servers/sip/freeswitch { };
#
#  gatling = callPackage ../servers/http/gatling { };
#
#  grafana = (callPackage ../servers/monitoring/grafana { }).bin // { outputs = ["bin"]; };
#
#  groovebasin = callPackage ../applications/audio/groovebasin { };
#
#  haka = callPackage ../tools/security/haka { };
#
#  heapster = (callPackage ../servers/monitoring/heapster { }).bin // { outputs = ["bin"]; };
#
#  hbase = callPackage ../servers/hbase {};
#
#  ircdHybrid = callPackage ../servers/irc/ircd-hybrid { };
#
#  jboss = callPackage ../servers/http/jboss { };
#
#  jboss_mysql_jdbc = callPackage ../servers/http/jboss/jdbc/mysql { };
#
#  jetty = callPackage ../servers/http/jetty { };
#
#  jetty61 = callPackage ../servers/http/jetty/6.1 { };
#
#  jetty92 = callPackage ../servers/http/jetty/9.2.nix { };
#
#  joseki = callPackage ../servers/http/joseki {};
#
#  rdkafka = callPackage ../development/libraries/rdkafka { };
#
#  leafnode = callPackage ../servers/news/leafnode { };
#
#  lighttpd = callPackage ../servers/http/lighttpd { };
#
#  mailman = callPackage ../servers/mail/mailman { };
#
#  mediatomb = callPackage ../servers/mediatomb { };
#
#  memcached = callPackage ../servers/memcached {};
#
#  meteor = callPackage ../servers/meteor/default.nix { };
#
#  # Backwards compatibility.
  mod_dnssd = pkgs.apacheHttpdPackages.mod_dnssd;
#  mod_evasive = pkgs.apacheHttpdPackages.mod_evasive;
#  mod_fastcgi = pkgs.apacheHttpdPackages.mod_fastcgi;
#  mod_python = pkgs.apacheHttpdPackages.mod_python;
#  mod_wsgi = pkgs.apacheHttpdPackages.mod_wsgi;
#
#  mpdscribble = callPackage ../tools/misc/mpdscribble { };
#
#  micro-httpd = callPackage ../servers/http/micro-httpd { };
#
#  miniHttpd = callPackage ../servers/http/mini-httpd {};
#
#  mlmmj = callPackage ../servers/mail/mlmmj { };
#
#  myserver = callPackage ../servers/http/myserver { };
#
#  neard = callPackage ../servers/neard { };
#
#  ngircd = callPackage ../servers/irc/ngircd { };
#
#  nix-binary-cache = callPackage ../servers/http/nix-binary-cache {};
#
#  nsd = callPackage ../servers/dns/nsd (config.nsd or {});
#
#  nsq = pkgs.goPackages.nsq.bin // { outputs = [ "bin" ]; };
#
#  oauth2_proxy = pkgs.goPackages.oauth2_proxy.bin // { outputs = [ "bin" ]; };
#
#  openpts = callPackage ../servers/openpts { };
#
#  openresty = callPackage ../servers/http/openresty { };
#
#  opensmtpd = callPackage ../servers/mail/opensmtpd { };
#  opensmtpd-extras = callPackage ../servers/mail/opensmtpd/extras.nix { };
#
#  openxpki = callPackage ../servers/openxpki { };
#
#  osrm-backend = callPackage ../servers/osrm-backend { };
#
#  osrm-backend_luajit = callPackage ../servers/osrm-backend { luabind = luabind_luajit; };
#
#  p910nd = callPackage ../servers/p910nd { };
#
#  petidomo = callPackage ../servers/mail/petidomo { };
#
#  popa3d = callPackage ../servers/mail/popa3d { };
#
#  postfix28 = callPackage ../servers/mail/postfix { };
#  postfix211 = callPackage ../servers/mail/postfix/2.11.nix { };
#  postfix30 = callPackage ../servers/mail/postfix/3.0.nix { };
#  postfix = postfix30;
#
#  postsrsd = callPackage ../servers/mail/postsrsd { };
#
#  rmilter = callPackage ../servers/mail/rmilter { };
#
#  rspamd = callPackage ../servers/mail/rspamd { };
#
#  pfixtools = callPackage ../servers/mail/postfix/pfixtools.nix { };
#
#  pshs = callPackage ../servers/http/pshs { };
#
#  tomcat_connectors = callPackage ../servers/http/apache-modules/tomcat-connectors { };
#
#  pies = callPackage ../servers/pies { };
#
#  portmap = callPackage ../servers/portmap { };
#
#  rpcbind = callPackage ../servers/rpcbind { };
#
#  #monetdb = callPackage ../servers/sql/monetdb { };
#
  mariadb = callPackage ../servers/sql/mariadb { };

  mongodb = callPackage ../servers/nosql/mongodb { };
#
#  riak = callPackage ../servers/nosql/riak/1.3.1.nix { };
#  riak2 = callPackage ../servers/nosql/riak/2.1.1.nix { };
#
#  influxdb = (callPackage ../servers/nosql/influxdb { }).bin // { outputs = [ "bin" ]; };
#
#  hyperdex = callPackage ../servers/nosql/hyperdex { };
#
  mysql = callPackageAlias "mariadb" { };
  mysql_lib = callPackageAlias "mysql" { };

#  nagios = callPackage ../servers/monitoring/nagios { };
#
#  munin = callPackage ../servers/monitoring/munin { };
#
#  nagiosPluginsOfficial = callPackage ../servers/monitoring/nagios/plugins/official-2.x.nix { };
#
#  neo4j = callPackage ../servers/nosql/neo4j { };
#
  net_snmp = callPackage ../servers/monitoring/net-snmp { };
#
#  newrelic-sysmond = callPackage ../servers/monitoring/newrelic-sysmond { };
#
#  riemann = callPackage ../servers/monitoring/riemann { };
#  riemann-dash = callPackage ../servers/monitoring/riemann-dash { };
#
#  oidentd = callPackage ../servers/identd/oidentd { };
#
#  openfire = callPackage ../servers/xmpp/openfire { };
#
#  oracleXE = callPackage ../servers/sql/oracle-xe { };
#
  softether_4_18 = callPackage ../servers/softether/4.18.nix { };
  softether = callPackageAlias "softether_4_18" { };
#
#  qboot = callPackage ../applications/virtualization/qboot { stdenv = stdenv_32bit; };
#
#  OVMF = callPackage ../applications/virtualization/OVMF { seabios=false; openssl=null; };
#  OVMF-CSM = callPackage ../applications/virtualization/OVMF { openssl=null; };
#  #WIP: OVMF-secureBoot = callPackage ../applications/virtualization/OVMF { seabios=false; secureBoot=true; };
#
#  cbfstool = callPackage ../applications/virtualization/cbfstool { };
#
#  pgpool92 = pgpool.override { postgresql = postgresql92; };
#  pgpool93 = pgpool.override { postgresql = postgresql93; };
#  pgpool94 = pgpool.override { postgresql = postgresql94; };
#  pgpool95 = pgpool.override { postgresql = postgresql95; };
#
#  pgpool = callPackage ../servers/sql/pgpool/default.nix {
#    libmemcached = null; # Detection is broken upstream
#  };
#
#  postgresql_jdbc = callPackage ../servers/sql/postgresql/jdbc { };
#
#  prom2json = pkgs.goPackages.prometheus.prom2json.bin // { outputs = [ "bin" ]; };
#  prometheus = pkgs.goPackages.prometheus.prometheus.bin // { outputs = [ "bin" ]; };
#  prometheus-alertmanager = pkgs.goPackages.prometheus.alertmanager.bin // { outputs = [ "bin" ]; };
#  prometheus-cli = pkgs.goPackages.prometheus.cli.bin // { outputs = [ "bin" ]; };
#  prometheus-collectd-exporter = pkgs.goPackages.prometheus.collectd-exporter.bin // { outputs = [ "bin" ]; };
#  prometheus-haproxy-exporter = pkgs.goPackages.prometheus.haproxy-exporter.bin // { outputs = [ "bin" ]; };
#  prometheus-mesos-exporter = pkgs.goPackages.prometheus.mesos-exporter.bin // { outputs = [ "bin" ]; };
#  prometheus-mysqld-exporter = pkgs.goPackages.prometheus.mysqld-exporter.bin // { outputs = [ "bin" ]; };
#  prometheus-nginx-exporter = pkgs.goPackages.prometheus.nginx-exporter.bin // { outputs = [ "bin" ]; };
#  prometheus-node-exporter = pkgs.goPackages.prometheus.node-exporter.bin // { outputs = [ "bin" ]; };
#  prometheus-pushgateway = pkgs.goPackages.prometheus.pushgateway.bin // { outputs = [ "bin" ]; };
#  prometheus-statsd-bridge = pkgs.goPackages.prometheus.statsd-bridge.bin // { outputs = [ "bin" ]; };
#
#  psqlodbc = callPackage ../servers/sql/postgresql/psqlodbc { };
#
#  pumpio = callPackage ../servers/web-apps/pump.io { };
#
#  pyIRCt = callPackage ../servers/xmpp/pyIRCt {};
#
#  pyMAILt = callPackage ../servers/xmpp/pyMAILt {};
#
#  qpid-cpp = callPackage ../servers/amqp/qpid-cpp {
#    boost = boost155;
#  };
#
#  quagga = callPackage ../servers/quagga { };
#
#  rabbitmq_server = callPackage ../servers/amqp/rabbitmq-server { };
#
#  redstore = callPackage ../servers/http/redstore { };
#
#  restund = callPackage ../servers/restund {};
#
#  rethinkdb = callPackage ../servers/nosql/rethinkdb { };
#
#  rippled = callPackage ../servers/rippled {
#    boost = boost159;
#  };
#
#  ripple-rest = callPackage ../servers/rippled/ripple-rest.nix { };
#
#  s6 = callPackage ../tools/system/s6 { };
#
#  s6-rc = callPackage ../tools/system/s6-rc { };
#
#  spamassassin = callPackage ../servers/mail/spamassassin {
#    inherit (perlPackages) HTMLParser NetDNS NetAddrIP DBFile
#      HTTPDate MailDKIM LWP IOSocketSSL;
#  };
#
#  shairport-sync = callPackage ../servers/shairport-sync { };
#
#  serfdom = pkgs.goPackages.serf.bin // { outputs = [ "bin" ]; };
#
#  seyren = callPackage ../servers/monitoring/seyren { };
#
#  sensu = callPackage ../servers/monitoring/sensu {
#    ruby = ruby_2_1;
#  };
#
#  shishi = callPackage ../servers/shishi { };
#
#  sipcmd = callPackage ../applications/networking/sipcmd { };
#
#  sipwitch = callPackage ../servers/sip/sipwitch { };
#
#  spawn_fcgi = callPackage ../servers/http/spawn-fcgi { };
#
#  squids = recurseIntoAttrs (callPackages ../servers/squid/squids.nix {});
#  squid = squids.squid31; # has ipv6 support
#
#  sslh = callPackage ../servers/sslh { };
#
#  thttpd = callPackage ../servers/http/thttpd { };
#
#  storm = callPackage ../servers/computing/storm { };
#
#  slurm-llnl = callPackage ../servers/computing/slurm { gtk = null; };
#
#  slurm-llnl-full = appendToName "full" (callPackage ../servers/computing/slurm { });
#
#  tomcat5 = callPackage ../servers/http/tomcat/5.0.nix { };
#
#  tomcat6 = callPackage ../servers/http/tomcat/6.0.nix { };
#
#  tomcat7 = callPackage ../servers/http/tomcat/7.0.nix { };
#
#  tomcat8 = callPackage ../servers/http/tomcat/8.0.nix { };
#
#  tomcat_mysql_jdbc = callPackage ../servers/http/tomcat/jdbc/mysql { };
#
#  torque = callPackage ../servers/computing/torque { };
#
#  axis2 = callPackage ../servers/http/tomcat/axis2 { };
#
  unifi = callPackage ../servers/unifi { };
#
#  virtuoso6 = callPackage ../servers/sql/virtuoso/6.x.nix { };
#
#  virtuoso7 = callPackage ../servers/sql/virtuoso/7.x.nix { };
#
#  virtuoso = virtuoso6;
#
#  vsftpd = callPackage ../servers/ftp/vsftpd { };
#
#  winstone = callPackage ../servers/http/winstone { };
#
#  xinetd = callPackage ../servers/xinetd { };
#
  zookeeper = callPackage ../servers/zookeeper { };

  zookeeper_mt = callPackage ../development/libraries/zookeeper_mt { };
#
#  xquartz = callPackage ../servers/x11/xquartz { };
#  quartz-wm = callPackage ../servers/x11/quartz-wm {
#    stdenv = clangStdenv;
#  };
#
  xorg = recurseIntoAttrs (lib.callPackagesWith pkgs ../servers/x11/xorg/default.nix {
    inherit (pkgs) fetchurl fetchgit fetchpatch stdenv pkgconfig intltool freetype fontconfig
      libxslt expat libpng zlib perl mesa_drivers spice_protocol libunwind
      dbus util-linux_lib openssl gperf m4 libevdev tradcpp libinput mcpp makeWrapper autoreconfHook
      autoconf automake libtool xmlto asciidoc flex bison python mtdev pixman systemd_lib
      libdrm;
    mesa = pkgs.mesa_noglu;
  } // { inherit (pkgs) xlibsWrapper; } );

  xwayland = callPackage ../servers/x11/xorg/xwayland.nix { };
#
#  yaws = callPackage ../servers/http/yaws { erlang = erlangR17; };
#
#  zabbix = recurseIntoAttrs (callPackages ../servers/monitoring/zabbix {});
#
#  zabbix20 = callPackage ../servers/monitoring/zabbix/2.0.nix { };
#  zabbix22 = callPackage ../servers/monitoring/zabbix/2.2.nix { };
#
#
#  ### OS-SPECIFIC
#
#  afuse = callPackage ../os-specific/linux/afuse { };
#
#  autofs5 = callPackage ../os-specific/linux/autofs { };
#
#  _915resolution = callPackage ../os-specific/linux/915resolution { };
#
#  nfs-utils = callPackage ../os-specific/linux/nfs-utils { };
#
  acpi = callPackage ../os-specific/linux/acpi { };

#  acpitool = callPackage ../os-specific/linux/acpitool { };
#
#  alfred = callPackage ../os-specific/linux/batman-adv/alfred.nix { };
#
#  alienfx = callPackage ../os-specific/linux/alienfx { };
#
  alsa-firmware = callPackage ../os-specific/linux/alsa-firmware { };

  alsa-lib = callPackage ../os-specific/linux/alsa-lib { };

  alsa-plugins = callPackage ../os-specific/linux/alsa-plugins { };

  alsa-plugin-wrapper = callPackage ../os-specific/linux/alsa-plugins/wrapper.nix { };

  alsa-utils = callPackage ../os-specific/linux/alsa-utils { };
  alsa-oss = callPackage ../os-specific/linux/alsa-oss { };
  alsa-tools = callPackage ../os-specific/linux/alsa-tools { };

  microcodeAmd = callPackage ../os-specific/linux/microcode/amd.nix { };

  microcodeIntel = callPackage ../os-specific/linux/microcode/intel.nix { };

#  apparmor = callPackage ../os-specific/linux/apparmor { swig = swig2; };
#  libapparmor = apparmor.libapparmor;
#  apparmor-pam = apparmor.apparmor-pam;
#  apparmor-parser = apparmor.apparmor-parser;
#  apparmor-profiles = apparmor.apparmor-profiles;
#  apparmor-utils = apparmor.apparmor-utils;
#
  atop = callPackage ../os-specific/linux/atop { };

#  b43Firmware_5_1_138 = callPackage ../os-specific/linux/firmware/b43-firmware/5.1.138.nix { };
#
#  b43Firmware_6_30_163_46 = callPackage ../os-specific/linux/firmware/b43-firmware/6.30.163.46.nix { };
#
#  b43FirmwareCutter = callPackage ../os-specific/linux/firmware/b43-firmware-cutter { };
#
#  batctl = callPackage ../os-specific/linux/batman-adv/batctl.nix { };

#  bridge-utils = callPackage ../os-specific/linux/bridge-utils { };
#
  busybox = callPackage ../os-specific/linux/busybox { };

  busyboxBootstrap = callPackageAlias "busybox" {
    enableStatic = true;
    enableMinimal = true;
    extraConfig = ''
      CONFIG_ASH y
      CONFIG_ASH_BUILTIN_ECHO y
      CONFIG_ASH_BUILTIN_TEST y
      CONFIG_ASH_OPTIMIZE_FOR_SIZE y
      CONFIG_MKDIR y
      CONFIG_TAR y
      CONFIG_UNXZ y
    '';
  };
#
#  cgmanager = callPackage ../os-specific/linux/cgmanager { };
#
#  checkpolicy = callPackage ../os-specific/linux/checkpolicy { };
#
#  checksec = callPackage ../os-specific/linux/checksec { };
#
  cifs_utils = callPackage ../os-specific/linux/cifs-utils { };
#
#  conky = callPackage ../os-specific/linux/conky ({ } // config.conky or {});
#
#  conntrack_tools = callPackage ../os-specific/linux/conntrack-tools { };
#
#  cpufrequtils = callPackage ../os-specific/linux/cpufrequtils { };
#
#  cryopid = callPackage ../os-specific/linux/cryopid { };
#
#  criu = callPackage ../os-specific/linux/criu { };
#
#  cramfsswap = callPackage ../os-specific/linux/cramfsswap { };
#
#  crda = callPackage ../os-specific/linux/crda { };
#
#  gnustep-make = callPackage ../development/tools/build-managers/gnustep/make { };
#  gnustep-xcode = callPackage ../development/tools/build-managers/gnustep/xcode { };
#
#  disk_indicator = callPackage ../os-specific/linux/disk-indicator { };
#
  dmidecode = callPackage ../os-specific/linux/dmidecode { };
#
#  dmtcp = callPackage ../os-specific/linux/dmtcp { };
#
#  dietlibc = callPackage ../os-specific/linux/dietlibc { };
#
#  directvnc = callPackage ../os-specific/linux/directvnc { };
#
#  drbd = callPackage ../os-specific/linux/drbd { };
#
#  dstat = callPackage ../os-specific/linux/dstat { };
#
#  light = callPackage ../os-specific/linux/light { };
#
#  lightum = callPackage ../os-specific/linux/lightum { };
#
#  e3cfsprogs = callPackage ../os-specific/linux/e3cfsprogs { };
#
#  ebtables = callPackage ../os-specific/linux/ebtables { };
#
#  facetimehd-firmware = callPackage ../os-specific/linux/firmware/facetimehd-firmware { };
#
#  fanctl = callPackage ../os-specific/linux/fanctl {
#    iproute = iproute.override { enableFan = true; };
#  };
#
#  fatrace = callPackage ../os-specific/linux/fatrace { };
#
  ffado_full = callPackage ../os-specific/linux/ffado { };

  ffado_lib = callPackage ../os-specific/linux/ffado {
    prefix = "lib";
  };
#
#  fbterm = callPackage ../os-specific/linux/fbterm { };
#
#  firejail = callPackage ../os-specific/linux/firejail {};
#
#  freefall = callPackage ../os-specific/linux/freefall { };
#
  fuse = callPackage ../os-specific/linux/fuse { };
#
#  fusionio-util = callPackage ../os-specific/linux/fusionio/util.nix { };
#
#  fxload = callPackage ../os-specific/linux/fxload { };
#
#  gfxtablet = callPackage ../os-specific/linux/gfxtablet {};
#
  gpm-ncurses = gpm.override { inherit ncurses; };

#  gradm = callPackage ../os-specific/linux/gradm {
#    flex = flex_2_5_35;
#  };
#
  hdparm = callPackage ../os-specific/linux/hdparm { };
#
#  hibernate = callPackage ../os-specific/linux/hibernate { };
#
#  hostapd = callPackage ../os-specific/linux/hostapd { };
#
#  i7z = callPackage ../os-specific/linux/i7z { };
#
#  ima-evm-utils = callPackage ../os-specific/linux/ima-evm-utils { };
#
#  iomelt = callPackage ../os-specific/linux/iomelt { };
#
  iotop = callPackage ../os-specific/linux/iotop { };

  iproute = callPackage ../os-specific/linux/iproute { };

  iptables = callPackage ../os-specific/linux/iptables { };

#  irqbalance = callPackage ../os-specific/linux/irqbalance { };
#
  iw = callPackage ../os-specific/linux/iw { };
#
#  jfbview = callPackage ../os-specific/linux/jfbview { };
#
#  jool-cli = callPackage ../os-specific/linux/jool/cli.nix { };
#
#  jujuutils = callPackage ../os-specific/linux/jujuutils { };
#
#  kbdlight = callPackage ../os-specific/linux/kbdlight { };
#
#  kmscon = callPackage ../os-specific/linux/kmscon { };
#
#  latencytop = callPackage ../os-specific/linux/latencytop { };
#
#  ldm = callPackage ../os-specific/linux/ldm { };
#
  libaio = callPackage ../os-specific/linux/libaio { };

  libatasmart = callPackage ../os-specific/linux/libatasmart { };
#
#  libcgroup = callPackage ../os-specific/linux/libcgroup { };
#
#  linuxConsoleTools = callPackage ../os-specific/linux/consoletools { };
#
#  openiscsi = callPackage ../os-specific/linux/open-iscsi { };
#
#  tgt = callPackage ../tools/networking/tgt { };
#
#  # -- Linux kernel expressions ------------------------------------------------
#

  kernelPatches = callPackage ../os-specific/linux/kernel/patches.nix { };

  linux_4_4 = callPackage ../os-specific/linux/kernel/linux-4.4.nix {
    kernelPatches = [ pkgs.kernelPatches.bridge_stp_helper ];
  };

  linux_4_5 = callPackage ../os-specific/linux/kernel/linux-4.5.nix {
    kernelPatches = [ pkgs.kernelPatches.bridge_stp_helper ];
  };

  linux_testing = callPackage ../os-specific/linux/kernel/linux-testing.nix {
    kernelPatches = [ pkgs.kernelPatches.bridge_stp_helper ];
  };
#
#  /* grsec configuration
#
#     We build several flavors of 'default' grsec kernels. These are
#     built by default with Hydra. If the user selects a matching
#     'default' flavor, then the pre-canned package set can be
#     chosen. Typically, users will make very basic choices like
#     'security' + 'server' or 'performance' + 'desktop' with
#     virtualisation support. These will then be picked.
#
#     Note: Xen guest kernels are included for e.g. NixOps deployments
#     to EC2, where Xen is the Hypervisor.
#  */
#
  grFlavors = import ../build-support/grsecurity/flavors.nix;
#
  mkGrsecurity = opts:
    (callPackage ../build-support/grsecurity {
      grsecOptions = opts;
    });
#
  grKernel  = opts: (mkGrsecurity opts).grsecKernel;
  grPackage = opts: recurseIntoAttrs (mkGrsecurity opts).grsecPackage;
#
#  # Stable kernels
#  # This is no longer supported. Please see the official announcement on the
#  # grsecurity page. https://grsecurity.net/announce.php
  linux_grsec_stable_desktop    = throw "No longer supported due to https://grsecurity.net/announce.php. "
    + "Please use linux_grsec_testing_desktop.";
  linux_grsec_stable_server     = throw "No longer supported due to https://grsecurity.net/announce.php. "
    + "Please use linux_grsec_testing_server.";
  linux_grsec_stable_server_xen = throw "No longer supporteddue to https://grsecurity.net/announce.php. "
    + "Please use linux_grsec_testing_server_xen.";
#
#  # Testing kernels: outdated ATM
#  #linux_grsec_testing_desktop = grKernel grFlavors.linux_grsec_testing_desktop;
#  #linux_grsec_testing_server  = grKernel grFlavors.linux_grsec_testing_server;
#  #linux_grsec_testing_server_xen = grKernel grFlavors.linux_grsec_testing_server_xen;
#
#  /* Linux kernel modules are inherently tied to a specific kernel.  So
#     rather than provide specific instances of those packages for a
#     specific kernel, we have a function that builds those packages
#     for a specific kernel.  This function can then be called for
#     whatever kernel you're using. */
#
  linuxPackagesFor = { kernel }: let
    kCallPackage = pkgs.newScope kPkgs;

    kPkgs = {
      inherit kernel;

      accelio = kCallPackage ../development/libraries/accelio { };

      cryptodev = cryptodevHeaders.override {
        onlyHeaders = false;
        inherit kernel;  # We shouldn't need this
      };

      cpupower = kCallPackage ../os-specific/linux/cpupower { };

      e1000e = kCallPackage ../os-specific/linux/e1000e {};

      nvidia-drivers_legacy304 = kCallPackage ../all-pkgs/nvidia-drivers {
        channel = "legacy304";
      };
      nvidia-drivers_legacy340 = kCallPackage ../all-pkgs/nvidia-drivers {
        channel = "legacy340";
      };
      nvidia-drivers_long-lived = kCallPackage ../all-pkgs/nvidia-drivers {
        channel = "long-lived";
      };
      nvidia-drivers_short-lived = kCallPackage ../all-pkgs/nvidia-drivers {
        channel = "short-lived";
      };
      nvidia-drivers_beta = kCallPackage ../all-pkgs/nvidia-drivers {
        channel = "beta";
      };
      nvidia-drivers_vulkan = kCallPackage ../all-pkgs/nvidia-drivers {
        channel = "vulkan";
      };

      spl = kCallPackage ../os-specific/linux/spl {
        configFile = "kernel";
        inherit (kPkgs) kernel;  # We shouldn't need this
      };

      spl_git = kCallPackage ../os-specific/linux/spl/git.nix {
        configFile = "kernel";
        inherit (kPkgs) kernel;  # We shouldn't need this
      };

      zfs = kCallPackage ../os-specific/linux/zfs {
        configFile = "kernel";
        inherit (kPkgs) kernel spl;  # We shouldn't need this
      };

      zfs_git = kCallPackage ../os-specific/linux/zfs/git.nix {
        configFile = "kernel";
        inherit (kPkgs) kernel spl_git;  # We shouldn't need this
      };

    };
  in kPkgs;
#
#
#    acpi_call = callPackage ../os-specific/linux/acpi-call {};
#
#    batman_adv = callPackage ../os-specific/linux/batman-adv {};
#
#    bbswitch = callPackage ../os-specific/linux/bbswitch {};
#
#    blcr = callPackage ../os-specific/linux/blcr { };
#
#    v4l2loopback = callPackage ../os-specific/linux/v4l2loopback { };
#
#    frandom = callPackage ../os-specific/linux/frandom { };
#
#    fusionio-vsl = callPackage ../os-specific/linux/fusionio/vsl.nix { };
#
#    lttng-modules = callPackage ../os-specific/linux/lttng-modules { };
#
#    broadcom_sta = callPackage ../os-specific/linux/broadcom-sta/default.nix { };
#
#    nvidiabl = callPackage ../os-specific/linux/nvidiabl { };
#
#    nvidia_x11_legacy304 = callPackage ../all-pkgs/nvidia-drivers { channel = "legacy304"; };
#
#    rtl8812au = callPackage ../os-specific/linux/rtl8812au { };
#
#    openafsClient = callPackage ../servers/openafs-client { };
#
#    facetimehd = callPackage ../os-specific/linux/facetimehd { };
#
#    klibc = callPackage ../os-specific/linux/klibc { };
#
#    klibcShrunk = lowPrio (callPackage ../os-specific/linux/klibc/shrunk.nix { });
#
#    jool = callPackage ../os-specific/linux/jool { };
#
#    /* compiles but has to be integrated into the kernel somehow
#       Let's have it uncommented and finish it..
#    */
#    ndiswrapper = callPackage ../os-specific/linux/ndiswrapper { };
#
#    netatop = callPackage ../os-specific/linux/netatop { };
#
#    perf = callPackage ../os-specific/linux/kernel/perf.nix { };
#
#    phc-intel = callPackage ../os-specific/linux/phc-intel { };
#
#    prl-tools = callPackage ../os-specific/linux/prl-tools { };
#
#    psmouse_alps = callPackage ../os-specific/linux/psmouse-alps { };
#
#    seturgent = callPackage ../os-specific/linux/seturgent { };
#
#    sysdig = callPackage ../os-specific/linux/sysdig {};
#
#    tp_smapi = callPackage ../os-specific/linux/tp_smapi { };
#
#    v86d = callPackage ../os-specific/linux/v86d { };
#
#    vhba = callPackage ../misc/emulators/cdemu/vhba.nix { };
#
#    virtualbox = callPackage ../applications/virtualization/virtualbox {
#      stdenv = stdenv_32bit;
#      inherit (gnome) libIDL;
#      enableExtensionPack = config.virtualbox.enableExtensionPack or false;
#      pulseSupport = config.pulseaudio or false;
#    };
#
#    virtualboxHardened = lowPrio (virtualbox.override {
#      enableHardening = true;
#    });
#
#    virtualboxGuestAdditions = callPackage ../applications/virtualization/virtualbox/guest-additions { };
#
#    x86_energy_perf_policy = callPackage ../os-specific/linux/x86_energy_perf_policy { };
#
#
#  # The current default kernel / kernel modules.
  linuxPackages = pkgs.linuxPackages_4_4;
  linux = pkgs.linuxPackages.kernel;
#
#  # Update this when adding the newest kernel major version!
  linuxPackages_latest = pkgs.linuxPackages_4_5;
  linux_latest = pkgs.linuxPackages_latest.kernel;
#
#  # Build the kernel modules for the some of the kernels.
  linuxPackages_4_4 = recurseIntoAttrs (pkgs.linuxPackagesFor {
    kernel = pkgs.linux_4_4;
  });
  linuxPackages_4_5 = recurseIntoAttrs (pkgs.linuxPackagesFor {
    kernel = pkgs.linux_4_5;
  });
  linuxPackages_testing = recurseIntoAttrs (pkgs.linuxPackagesFor {
    kernel = pkgs.linux_testing;
  });
  linuxPackages_custom = {version, src, configfile}:
                           let linuxPackages_self = (linuxPackagesFor (pkgs.linuxManualConfig {inherit version src configfile;
                                                                                               allowImportFromDerivation=true;})
                                                     linuxPackages_self);
                           in recurseIntoAttrs linuxPackages_self;
#
#  # Build a kernel for Xen dom0
  linuxPackages_latest_xen_dom0 = recurseIntoAttrs (pkgs.linuxPackagesFor (pkgs.linux_latest.override { features.xen_dom0=true; }) pkgs.linuxPackages_latest);
#
#  # grsecurity flavors
#  # Stable kernels
  linuxPackages_grsec_stable_desktop    = grPackage grFlavors.linux_grsec_stable_desktop;
  linuxPackages_grsec_stable_server     = grPackage grFlavors.linux_grsec_stable_server;
  linuxPackages_grsec_stable_server_xen = grPackage grFlavors.linux_grsec_stable_server_xen;
#
#  # Testing kernels: outdated ATM
  linuxPackages_grsec_testing_desktop = grPackage grFlavors.linux_grsec_testing_desktop;
  linuxPackages_grsec_testing_server  = grPackage grFlavors.linux_grsec_testing_server;
  linuxPackages_grsec_testing_server_xen = grPackage grFlavors.linux_grsec_testing_server_xen;
#
#  # A function to build a manually-configured kernel
  linuxManualConfig = pkgs.buildLinux;
  buildLinux = callPackage ../os-specific/linux/kernel/manual-config.nix {};
#
  keyutils = callPackage ../os-specific/linux/keyutils { };
#
  libselinux = callPackage ../os-specific/linux/libselinux { };
#
  libsemanage = callPackage ../os-specific/linux/libsemanage { };
#
  libraw1394 = callPackage ../development/libraries/libraw1394 { };
#
#  libsass = callPackage ../development/libraries/libsass { };
#
#  libsexy = callPackage ../development/libraries/libsexy { };
#
  libsepol = callPackage ../os-specific/linux/libsepol { };
#
#  libsmbios = callPackage ../os-specific/linux/libsmbios { };
#
#  lockdep = callPackage ../os-specific/linux/lockdep { };
#
#  lsiutil = callPackage ../os-specific/linux/lsiutil { };
#
  kmod-blacklist-ubuntu = callPackage ../os-specific/linux/kmod-blacklist-ubuntu { };

  kmod-debian-aliases = callPackage ../os-specific/linux/kmod-debian-aliases { };

  kvm = qemu_kvm;
#
  libcap = callPackage ../os-specific/linux/libcap { };

  libcap_progs = callPackage ../os-specific/linux/libcap/progs.nix { };

  libcap_pam = callPackage ../os-specific/linux/libcap/pam.nix { };

  libcap_manpages = callPackage ../os-specific/linux/libcap/man.nix { };

#  libnscd = callPackage ../os-specific/linux/libnscd { };
#
  libnotify = callPackage ../development/libraries/libnotify { };
#
#  libvolume_id = callPackage ../os-specific/linux/libvolume_id { };
#
#  lsscsi = callPackage ../os-specific/linux/lsscsi { };
#
#  mbpfan = callPackage ../os-specific/linux/mbpfan { };
#
  mdadm = callPackage ../os-specific/linux/mdadm { };
#
#  mingetty = callPackage ../os-specific/linux/mingetty { };
#
#  miraclecast = callPackage ../os-specific/linux/miraclecast {
#    systemd = systemd.override { enableKDbus = true; };
#  };
#
#  mkinitcpio-nfs-utils = callPackage ../os-specific/linux/mkinitcpio-nfs-utils { };
#
#  mmc-utils = callPackage ../os-specific/linux/mmc-utils { };
#
  module_init_tools = callPackage ../os-specific/linux/module-init-tools { };

  aggregateModules = modules:
    callPackage ../all-pkgs/kmod/aggregator.nix {
      inherit modules;
    };
#
#  multipath-tools = callPackage ../os-specific/linux/multipath-tools { };
#
  nftables = callPackage ../os-specific/linux/nftables { };

#  numad = callPackage ../os-specific/linux/numad { };
#
#  open-vm-tools = callPackage ../applications/virtualization/open-vm-tools {
#    inherit (gnome) gtk gtkmm;
#  };
#
#  gocode = pkgs.goPackages.gocode.bin // { outputs = [ "bin" ]; };
#
#  kgocode = callPackage ../applications/misc/kgocode {
#    inherit (pkgs.kde4) kdelibs;
#  };
#
#  gotags = pkgs.goPackages.gotags.bin // { outputs = [ "bin" ]; };
#
#  golint = pkgs.goPackages.lint.bin // { outputs = [ "bin" ]; };
#
#  godep = callPackage ../development/tools/godep { };
#
#  goimports = pkgs.goPackages.tools.bin // { outputs = [ "bin" ]; };
#
#  gogoclient = callPackage ../os-specific/linux/gogoclient { };
#
#  nss_ldap = callPackage ../os-specific/linux/nss_ldap { };
#
#  pagemon = callPackage ../os-specific/linux/pagemon { };
#
#  # pam_bioapi ( see http://www.thinkwiki.org/wiki/How_to_enable_the_fingerprint_reader )
#
#  pam_ccreds = callPackage ../os-specific/linux/pam_ccreds { };
#
#  pam_devperm = callPackage ../os-specific/linux/pam_devperm { };
#
#  pam_krb5 = callPackage ../os-specific/linux/pam_krb5 { };
#
#  pam_ldap = callPackage ../os-specific/linux/pam_ldap { };
#
#  pam_mount = callPackage ../os-specific/linux/pam_mount { };
#
#  pam_pgsql = callPackage ../os-specific/linux/pam_pgsql { };
#
#  pam_ssh_agent_auth = callPackage ../os-specific/linux/pam_ssh_agent_auth { };
#
#  pam_u2f = callPackage ../os-specific/linux/pam_u2f { };
#
#  pam_usb = callPackage ../os-specific/linux/pam_usb { };
#
#  paxctl = callPackage ../os-specific/linux/paxctl { };
#
#  paxtest = callPackage ../os-specific/linux/paxtest { };
#
#  pax-utils = callPackage ../os-specific/linux/pax-utils { };
#
#  pcmciaUtils = callPackage ../os-specific/linux/pcmciautils {
#    firmware = config.pcmciaUtils.firmware or [];
#    config = config.pcmciaUtils.config or null;
#  };
#
#  perf-tools = callPackage ../os-specific/linux/perf-tools { };
#
#  pipes = callPackage ../misc/screensavers/pipes { };
#
#  pipework = callPackage ../os-specific/linux/pipework { };
#
#  plymouth = callPackage ../os-specific/linux/plymouth { };
#
#  pmount = callPackage ../os-specific/linux/pmount { };
#
#  pmutils = callPackage ../os-specific/linux/pm-utils { };
#
#  pmtools = callPackage ../os-specific/linux/pmtools { };
#
#  policycoreutils = callPackage ../os-specific/linux/policycoreutils { };
#
#  powertop = callPackage ../os-specific/linux/powertop { };
#
#  prayer = callPackage ../servers/prayer { };
#
  procps-old = lowPrio (callPackage ../os-specific/linux/procps { });

  procps = callPackage ../os-specific/linux/procps-ng { };
#
#  watch = callPackage ../os-specific/linux/procps/watch.nix { };
#
#  qemu_kvm = lowPrio (qemu.override { type = "kvm-only"; });
#
  firmware-linux-nonfree = callPackage ../os-specific/linux/firmware/firmware-linux-nonfree { };
#
#  radeontools = callPackage ../os-specific/linux/radeontools { };
#
#  radeontop = callPackage ../os-specific/linux/radeontop { };
#
#  raspberrypifw = callPackage ../os-specific/linux/firmware/raspberrypi {};
#
#  regionset = callPackage ../os-specific/linux/regionset { };
#
  rfkill = callPackage ../os-specific/linux/rfkill { };
#
#  rfkill_udev = callPackage ../os-specific/linux/rfkill/udev.nix { };
#
  rtkit = callPackage ../os-specific/linux/rtkit { };
#
#  rt5677-firmware = callPackage ../os-specific/linux/firmware/rt5677 { };
#
#  s3ql = callPackage ../tools/backup/s3ql { };
#
#  sassc = callPackage ../development/tools/sassc { };
#
#  scanmem = callPackage ../tools/misc/scanmem { };
#
#  schedtool = callPackage ../os-specific/linux/schedtool { };
#
  sdparm = callPackage ../os-specific/linux/sdparm { };
#
#  sepolgen = callPackage ../os-specific/linux/sepolgen { };
#
#  setools = callPackage ../os-specific/linux/setools { };
#
  shadow = callPackage ../os-specific/linux/shadow { };
#
#  sinit = callPackage ../os-specific/linux/sinit {
#    rcinit = "/etc/rc.d/rc.init";
#    rcshutdown = "/etc/rc.d/rc.shutdown";
#  };
#
#  smem = callPackage ../os-specific/linux/smem { };
#
#  statifier = callPackage ../os-specific/linux/statifier { };
#
#  spl = callPackage ../os-specific/linux/spl {
#    configFile = "user";
#  };
#  spl_git = callPackage ../os-specific/linux/spl/git.nix {
#    configFile = "user";
#  };
#
#  sysdig = callPackage ../os-specific/linux/sysdig {
#    kernel = null;
#  }; # pkgs.sysdig is a client, for a driver look at linuxPackagesFor
#
  sysfsutils = callPackage ../os-specific/linux/sysfsutils { };
#
#  sysprof = callPackage ../development/tools/profiling/sysprof {
#    inherit (gnome) libglade;
#  };
#
#  # Provided with sysfsutils.
#  libsysfs = sysfsutils;
#  systool = sysfsutils;
#
#  sysklogd = callPackage ../os-specific/linux/sysklogd { };
#
  syslinux = callPackage ../os-specific/linux/syslinux { };

  sysstat = callPackage ../os-specific/linux/sysstat { };

#  # In nixos, you can set systemd.package = pkgs.systemd_with_lvm2 to get
#  # LVM2 working in systemd.
  systemd_with_lvm2 = pkgs.lib.overrideDerivation pkgs.systemd (p: {
      name = p.name + "-with-lvm2";
      postInstall = p.postInstall + ''
        cp "${pkgs.lvm2}/lib/systemd/system-generators/"* $out/lib/systemd/system-generators
      '';
  });
#
#  sysvinit = callPackage ../os-specific/linux/sysvinit { };
#
#  sysvtools = callPackage ../os-specific/linux/sysvinit {
#    withoutInitTools = true;
#  };
#
#  trinity = callPackage ../os-specific/linux/trinity { };
#
#  tunctl = callPackage ../os-specific/linux/tunctl { };
#
#  # TODO(dezgeg): either refactor & use ubootTools directly, or remove completely
  ubootChooser = name: ubootTools;

  # Upstream U-Boots:
  ubootTools = callPackage ../misc/uboot {
    toolsOnly = true;
    targetPlatforms = lib.platforms.linux;
    filesToInstall = ["tools/dumpimage" "tools/mkenvimage" "tools/mkimage"];
  };
#
#  ubootJetsonTK1 = callPackage ../misc/uboot {
#    defconfig = "jetson-tk1_defconfig";
#    targetPlatforms = ["armv7l-linux"];
#    filesToInstall = ["u-boot" "u-boot.dtb" "u-boot-dtb-tegra.bin" "u-boot-nodtb-tegra.bin"];
#  };
#
#  ubootPcduino3Nano = callPackage ../misc/uboot {
#    defconfig = "Linksprite_pcDuino3_Nano_defconfig";
#    targetPlatforms = ["armv7l-linux"];
#    filesToInstall = ["u-boot-sunxi-with-spl.bin"];
#  };
#
#  ubootRaspberryPi = callPackage ../misc/uboot {
#    defconfig = "rpi_defconfig";
#    targetPlatforms = ["armv6l-linux"];
#    filesToInstall = ["u-boot.bin"];
#  };
#
#  # Intended only for QEMU's vexpress-a9 emulation target!
#  ubootVersatileExpressCA9 = callPackage ../misc/uboot {
#    defconfig = "vexpress_ca9x4_defconfig";
#    targetPlatforms = ["armv7l-linux"];
#    filesToInstall = ["u-boot"];
#  };
#
#  # Non-upstream U-Boots:
#  ubootSheevaplug = callPackage ../misc/uboot/sheevaplug.nix { };
#
#  ubootNanonote = callPackage ../misc/uboot/nanonote.nix { };
#
#  ubootGuruplug = callPackage ../misc/uboot/guruplug.nix { };
#
#  uclibc = callPackage ../os-specific/linux/uclibc { };
#
#  uclibcCross = lowPrio (callPackage ../os-specific/linux/uclibc {
#    linuxHeaders = linuxHeadersCross;
#    gccCross = gccCrossStageStatic;
#    cross = assert crossSystem != null; crossSystem;
#  });
#
#  udisks_glue = callPackage ../os-specific/linux/udisks-glue { };
#
#  uksmtools = callPackage ../os-specific/linux/uksmtools { };
#
#  untie = callPackage ../os-specific/linux/untie { };
#
  upower = callPackage ../os-specific/linux/upower { };

#  upstart = callPackage ../os-specific/linux/upstart { };
#
  usbutils = callPackage ../os-specific/linux/usbutils { };
#
#  usermount = callPackage ../os-specific/linux/usermount { };
#
  v4l_utils = callPackage ../os-specific/linux/v4l-utils {
    qt5 = null;
  };

  wirelesstools = callPackage ../os-specific/linux/wireless-tools { };

  wpa_supplicant = callPackage ../os-specific/linux/wpa_supplicant { };
#
#  wpa_supplicant_gui = callPackage ../os-specific/linux/wpa_supplicant/gui.nix { };
#
#  xf86_input_mtrack = callPackage ../os-specific/linux/xf86-input-mtrack { };
#
#  xf86_input_multitouch =
#    callPackage ../os-specific/linux/xf86-input-multitouch { };
#
xf86_input_wacom = callPackage ../os-specific/linux/xf86-input-wacom { };
#
#  xf86_video_nested = callPackage ../os-specific/linux/xf86-video-nested { };
#
#  xorg_sys_opengl = callPackage ../os-specific/linux/opengl/xorg-sys { };
#
#  zd1211fw = callPackage ../os-specific/linux/firmware/zd1211 { };
#
  zfs = callPackage ../os-specific/linux/zfs {
    configFile = "user";
  };
  zfs_git = callPackage ../os-specific/linux/zfs/git.nix {
    configFile = "user";
  };
#
#  ### DATA
#
#  andagii = callPackage ../data/fonts/andagii { };
#
#  android-udev-rules = callPackage ../os-specific/linux/android-udev-rules { };
#
#  anonymousPro = callPackage ../data/fonts/anonymous-pro { };
#
#  arkpandora_ttf = callPackage ../data/fonts/arkpandora { };
#
#  aurulent-sans = callPackage ../data/fonts/aurulent-sans { };
#
#  baekmuk-ttf = callPackage ../data/fonts/baekmuk-ttf { };
#
  cacert = callPackage ../data/misc/cacert { };
#
#  caladea = callPackage ../data/fonts/caladea {};
#
  cantarell_fonts = callPackage ../data/fonts/cantarell-fonts { };
#
#  carlito = callPackage ../data/fonts/carlito {};
#
#  comfortaa = callPackage ../data/fonts/comfortaa {};
#
#  comic-neue = callPackage ../data/fonts/comic-neue { };
#
#  comic-relief = callPackage ../data/fonts/comic-relief {};
#
#  corefonts = callPackage ../data/fonts/corefonts { };
#
#  culmus = callPackage ../data/fonts/culmus { };
#
#  wrapFonts = paths : (callPackage ../data/fonts/fontWrap { inherit paths; });
#
#  clearlyU = callPackage ../data/fonts/clearlyU { };
#
#  cm_unicode = callPackage ../data/fonts/cm-unicode {};
#
#  crimson = callPackage ../data/fonts/crimson {};
#
  dejavu_fonts = callPackage ../data/fonts/dejavu-fonts { };
#
#  dina-font = callPackage ../data/fonts/dina { };
#
#  dina-font-pcf = callPackage ../data/fonts/dina-pcf { };
#
  docbook5 = callPackage ../data/sgml+xml/schemas/docbook-5.0 { };

  docbook_sgml_dtd_31 = callPackage ../data/sgml+xml/schemas/sgml-dtd/docbook/3.1.nix { };

  docbook_sgml_dtd_41 = callPackage ../data/sgml+xml/schemas/sgml-dtd/docbook/4.1.nix { };

  docbook_xml_dtd_412 = callPackage ../data/sgml+xml/schemas/xml-dtd/docbook/4.1.2.nix { };

  docbook_xml_dtd_42 = callPackage ../data/sgml+xml/schemas/xml-dtd/docbook/4.2.nix { };

  docbook_xml_dtd_43 = callPackage ../data/sgml+xml/schemas/xml-dtd/docbook/4.3.nix { };
#
#  docbook_xml_dtd_44 = callPackage ../data/sgml+xml/schemas/xml-dtd/docbook/4.4.nix { };
#
  docbook_xml_dtd_45 = callPackage ../data/sgml+xml/schemas/xml-dtd/docbook/4.5.nix { };
#
#  docbook_xml_ebnf_dtd = callPackage ../data/sgml+xml/schemas/xml-dtd/docbook-ebnf { };
#
  inherit (callPackages ../data/sgml+xml/stylesheets/xslt/docbook-xsl { })
    docbook_xsl
    docbook_xsl_ns;
#
#  docbook_xml_xslt = docbook_xsl;
#
  docbook5_xsl = callPackageAlias "docbook_xsl_ns" { };
#
#  dosemu_fonts = callPackage ../data/fonts/dosemu-fonts { };
#
#  eb-garamond = callPackage ../data/fonts/eb-garamond { };
#
#  fantasque-sans-mono = callPackage ../data/fonts/fantasque-sans-mono {};
#
#  fira = callPackage ../data/fonts/fira { };
#
#  fira-code = callPackage ../data/fonts/fira-code { };
#
#  fira-mono = callPackage ../data/fonts/fira-mono { };
#
#  font-awesome-ttf = callPackage ../data/fonts/font-awesome-ttf { };
#
  freefont_ttf = callPackage ../data/fonts/freefont-ttf { };
#
#  font-droid = callPackage ../data/fonts/droid { };
#
#  freepats = callPackage ../data/misc/freepats { };
#
#  gentium = callPackage ../data/fonts/gentium {};
#
#  geolite-legacy = callPackage ../data/misc/geolite-legacy { };
#
#  gohufont = callPackage ../data/fonts/gohufont { };
#
#  gnome_user_docs = callPackage ../data/documentation/gnome-user-docs { };
#
#  gyre-fonts = callPackage ../data/fonts/gyre {};
#
#  hack-font = callPackage ../data/fonts/hack { };
#
hicolor_icon_theme = callPackage ../data/icons/hicolor-icon-theme { };
#
#  hanazono = callPackage ../data/fonts/hanazono { };
#
#  inconsolata = callPackage ../data/fonts/inconsolata {};
#  inconsolata-lgc = callPackage ../data/fonts/inconsolata/lgc.nix {};
#
#  iosevka = callPackage ../data/fonts/iosevka { };
#
#  ipafont = callPackage ../data/fonts/ipafont {};
#  ipaexfont = callPackage ../data/fonts/ipaexfont {};
#
#  junicode = callPackage ../data/fonts/junicode { };
#
#  kawkab-mono-font = callPackage ../data/fonts/kawkab-mono {};
#
#  kochi-substitute = callPackage ../data/fonts/kochi-substitute {};
#
#  kochi-substitute-naga10 = callPackage ../data/fonts/kochi-substitute-naga10 {};
#
#  league-of-moveable-type = callPackage ../data/fonts/league-of-moveable-type {};
#
  liberation_ttf_from_source = callPackage ../data/fonts/redhat-liberation-fonts { };
  liberation_ttf_binary = callPackage ../data/fonts/redhat-liberation-fonts/binary.nix { };
  liberation_ttf = pkgs.liberation_ttf_binary;
#
#  libertine = callPackage ../data/fonts/libertine { };
#
#  lmmath = callPackage ../data/fonts/lmodern/lmmath.nix {};
#
#  lmodern = callPackage ../data/fonts/lmodern { };
#
#  lobster-two = callPackage ../data/fonts/lobster-two {};
#
#  # lohit-fonts.assamese lohit-fonts.bengali lohit-fonts.devanagari lohit-fonts.gujarati lohit-fonts.gurmukhi
#  # lohit-fonts.kannada lohit-fonts.malayalam lohit-fonts.marathi lohit-fonts.nepali lohit-fonts.odia
#  # lohit-fonts.tamil-classical lohit-fonts.tamil lohit-fonts.telugu
#  # lohit-fonts.kashmiri lohit-fonts.konkani lohit-fonts.maithili lohit-fonts.sindhi
#  lohit-fonts = recurseIntoAttrs ( callPackages ../data/fonts/lohit-fonts { } );
#
#  marathi-cursive = callPackage ../data/fonts/marathi-cursive { };
#
  meslo-lg = callPackage ../data/fonts/meslo-lg {};
#
#  miscfiles = callPackage ../data/misc/miscfiles { };
#
#  media-player-info = callPackage ../data/misc/media-player-info {};
#
  mobile_broadband_provider_info = callPackage ../data/misc/mobile-broadband-provider-info { };
#
#  mph_2b_damase = callPackage ../data/fonts/mph-2b-damase { };
#
#  mplus-outline-fonts = callPackage ../data/fonts/mplus-outline-fonts { };
#
#  mro-unicode = callPackage ../data/fonts/mro-unicode { };
#
#  nafees = callPackage ../data/fonts/nafees { };
#
#  inherit (callPackages ../data/fonts/noto-fonts {})
#    noto-fonts noto-fonts-cjk noto-fonts-emoji;
#
#  numix-icon-theme = callPackage ../data/icons/numix-icon-theme { };
#
#  numix-icon-theme-circle = callPackage ../data/icons/numix-icon-theme-circle { };
#
#  oldstandard = callPackage ../data/fonts/oldstandard { };
#
#  oldsindhi = callPackage ../data/fonts/oldsindhi { };
#
#  open-dyslexic = callPackage ../data/fonts/open-dyslexic { };
#
#  opensans-ttf = callPackage ../data/fonts/opensans-ttf { };
#
#  pecita = callPackage ../data/fonts/pecita {};
#
#  paratype-pt-mono = callPackage ../data/fonts/paratype-pt/mono.nix {};
#  paratype-pt-sans = callPackage ../data/fonts/paratype-pt/sans.nix {};
#  paratype-pt-serif = callPackage ../data/fonts/paratype-pt/serif.nix {};
#
#  poly = callPackage ../data/fonts/poly { };
#
#  posix_man_pages = callPackage ../data/documentation/man-pages-posix { };
#
#  powerline-fonts = callPackage ../data/fonts/powerline-fonts { };
#
#  proggyfonts = callPackage ../data/fonts/proggyfonts { };
#
#  sampradaya = callPackage ../data/fonts/sampradaya { };
#
  shared_mime_info = callPackage ../data/misc/shared-mime-info { };
#
#  shared_desktop_ontologies = callPackage ../data/misc/shared-desktop-ontologies { };
#
#  signwriting = callPackage ../data/fonts/signwriting { };
#
#  soundfont-fluid = callPackage ../data/soundfonts/fluid { };
#
#  stdmanpages = callPackage ../data/documentation/std-man-pages { };
#
#  stix-otf = callPackage ../data/fonts/stix-otf { };
#
#  inherit (callPackages ../data/fonts/gdouros { })
#    aegean textfonts symbola aegyptus akkadian anatolian maya unidings musica analecta;
#
  iana_etc = callPackage ../data/misc/iana-etc { };
#
#  poppler_data = callPackage ../data/misc/poppler-data { };
#
#  quattrocento = callPackage ../data/fonts/quattrocento {};
#
#  quattrocento-sans = callPackage ../data/fonts/quattrocento-sans {};
#
#  r3rs = callPackage ../data/documentation/rnrs/r3rs.nix { };
#
#  r4rs = callPackage ../data/documentation/rnrs/r4rs.nix { };
#
#  r5rs = callPackage ../data/documentation/rnrs/r5rs.nix { };
#
#  hasklig = callPackage ../data/fonts/hasklig {};
#
  sound-theme-freedesktop = callPackage ../data/misc/sound-theme-freedesktop { };
#
#  source-code-pro = callPackage ../data/fonts/source-code-pro {};
#
#  source-sans-pro = callPackage ../data/fonts/source-sans-pro { };
#
#  source-serif-pro = callPackage ../data/fonts/source-serif-pro { };
#
#  sourceHanSansPackages = callPackage ../data/fonts/source-han-sans { };
#  source-han-sans-japanese = sourceHanSansPackages.japanese;
#  source-han-sans-korean = sourceHanSansPackages.korean;
#  source-han-sans-simplified-chinese = sourceHanSansPackages.simplified-chinese;
#  source-han-sans-traditional-chinese = sourceHanSansPackages.traditional-chinese;
#
#  inherit (callPackages ../data/fonts/tai-languages { }) tai-ahom;
#
#  tango-icon-theme = callPackage ../data/icons/tango-icon-theme { };
#
#  themes = name: callPackage (../data/misc/themes + ("/" + name + ".nix")) {};
#
#  theano = callPackage ../data/fonts/theano { };
#
#  tempora_lgc = callPackage ../data/fonts/tempora-lgc { };
#
#  terminus_font = callPackage ../data/fonts/terminus-font { };
#
#  tipa = callPackage ../data/fonts/tipa { };
#
#  ttf_bitstream_vera = callPackage ../data/fonts/ttf-bitstream-vera { };
#
#  ubuntu_font_family = callPackage ../data/fonts/ubuntu-font-family { };
#
#  ucsFonts = callPackage ../data/fonts/ucs-fonts { };
#
#  uni-vga = callPackage ../data/fonts/uni-vga { };
#
  unifont = callPackage ../data/fonts/unifont { };
#
#  unifont_upper = callPackage ../data/fonts/unifont_upper { };
#
#  vanilla-dmz = callPackage ../data/icons/vanilla-dmz { };
#
#  vistafonts = callPackage ../data/fonts/vista-fonts { };
#
#  wireless-regdb = callPackage ../data/misc/wireless-regdb { };
#
#  wqy_microhei = callPackage ../data/fonts/wqy-microhei { };
#
#  wqy_zenhei = callPackage ../data/fonts/wqy-zenhei { };
#
#  xhtml1 = callPackage ../data/sgml+xml/schemas/xml-dtd/xhtml1 { };
#
#  xlsx2csv = pythonPackages.xlsx2csv;
#
#  zeal = qt5.callPackage ../data/documentation/zeal { };
#
#
#  ### APPLICATIONS
#
#  a2jmidid = callPackage ../applications/audio/a2jmidid { };
#
#  aacgain = callPackage ../applications/audio/aacgain { };
#
#  abcde = callPackage ../applications/audio/abcde {
#    inherit (perlPackages) DigestSHA MusicBrainz MusicBrainzDiscID;
#    inherit (pythonPackages) eyeD3;
#    libcdio = libcdio082;
#  };
#
#  abiword = callPackage ../applications/office/abiword {
#    inherit (gnome) libglade libgnomecanvas;
#  };
#
#  abook = callPackage ../applications/misc/abook { };
#
  adobe-reader = callPackage_i686 ../applications/misc/adobe-reader { };
#
#  aewan = callPackage ../applications/editors/aewan { };
#
#  alchemy = callPackage ../applications/graphics/alchemy { };
#
#  alock = callPackage ../misc/screensavers/alock { };
#
#  alpine = callPackage ../applications/networking/mailreaders/alpine {
#    tcl = tcl-8_5;
#  };
#  realpine = callPackage ../applications/networking/mailreaders/realpine {
#    tcl = tcl-8_5;
#  };
#
#  AMB-plugins = callPackage ../applications/audio/AMB-plugins { };
#
#  ams-lv2 = callPackage ../applications/audio/ams-lv2 { };
#
#  amsn = callPackage ../applications/networking/instant-messengers/amsn { };
#
#  antimony = qt5.callPackage ../applications/graphics/antimony {};
#
#  antiword = callPackage ../applications/office/antiword {};
#
#  ario = callPackage ../applications/audio/ario { };
#
#  artha = callPackage ../applications/misc/artha { };
#
#  aseprite = callPackage ../applications/editors/aseprite {
#    giflib = giflib_4_1;
#  };
#
#  audacious = callPackage ../applications/audio/audacious { };
#
#  audacity = callPackage ../applications/audio/audacity { };
#
#  audio-recorder = callPackage ../applications/audio/audio-recorder { };
#
#  milkytracker = callPackage ../applications/audio/milkytracker { };
#
#  schismtracker = callPackage ../applications/audio/schismtracker { };
#
#  altcoins = recurseIntoAttrs (callPackage ../applications/altcoins { });
#
#  aumix = callPackage ../applications/audio/aumix {
#    gtkGUI = false;
#  };
#
#  autopanosiftc = callPackage ../applications/graphics/autopanosiftc { };
#
#  avidemux = callPackage ../applications/video/avidemux { };
#
#  avrdudess = callPackage ../applications/misc/avrdudess { };
#
#  avxsynth = callPackage ../applications/video/avxsynth {
#    libjpeg = libjpeg_original; # error: 'JCOPYRIGHT_SHORT' was not declared in this scope
#  };
#
#  awesome-3-5 = callPackage ../applications/window-managers/awesome {
#    cairo = cairo.override { xcbSupport = true; };
#    luaPackages = luaPackages.override { inherit lua; };
#  };
#  awesome = awesome-3-5;
#
#  awesomebump = qt5.callPackage ../applications/graphics/awesomebump { };
#
#  backintime-common = callPackage ../applications/networking/sync/backintime/common.nix { };
#
#  backintime-qt4 = callPackage ../applications/networking/sync/backintime/qt4.nix { };
#
#  backintime = backintime-qt4;
#
#  bandwidth = callPackage ../tools/misc/bandwidth { };
#
#  baresip = callPackage ../applications/networking/instant-messengers/baresip {
#    ffmpeg = ffmpeg_1;
#  };
#
#  batti = callPackage ../applications/misc/batti { };
#
#  baudline = callPackage ../applications/audio/baudline {
#    jack = jack1;
#  };
#
#  beast = callPackage ../applications/audio/beast {
#    inherit (gnome) libgnomecanvas libart_lgpl;
#    guile = guile_1_8;
#  };
#
#  bibletime = callPackage ../applications/misc/bibletime { };
#
#  bitlbee = callPackage ../applications/networking/instant-messengers/bitlbee { };
#  bitlbee-plugins = callPackage ../applications/networking/instant-messengers/bitlbee/plugins.nix { };
#
#  bitlbee-facebook = callPackage ../applications/networking/instant-messengers/bitlbee-facebook { };
#
#  bitlbee-steam = callPackage ../applications/networking/instant-messengers/bitlbee-steam { };
#
#  bitmeter = callPackage ../applications/audio/bitmeter { };
#
#  bleachbit = callPackage ../applications/misc/bleachbit { };
#
#  blender = callPackage  ../applications/misc/blender {
#    cudatoolkit = cudatoolkit7;
#    python = python34;
#  };
#
#  bluefish = callPackage ../applications/editors/bluefish {
#    gtk = gtk3;
#  };
#
  bluejeans = callPackage ../applications/networking/browsers/mozilla-plugins/bluejeans { };
#
#  bomi = qt5.callPackage ../applications/video/bomi {
#    youtube-dl = pythonPackages.youtube-dl;
#    pulseSupport = config.pulseaudio or true;
#  };
#
#  brackets = callPackage ../applications/editors/brackets { };
#
#  bristol = callPackage ../applications/audio/bristol { };
#
#  bvi = callPackage ../applications/editors/bvi { };
#
#  bviplus = callPackage ../applications/editors/bviplus { };
#
#  calf = callPackage ../applications/audio/calf {
#      inherit (gnome) libglade;
#  };
#
#  calcurse = callPackage ../applications/misc/calcurse { };
#
#  calibre = qt55.callPackage ../applications/misc/calibre {
#    inherit (pythonPackages) pyqt5 sip_4_16;
#  };
#
#  camlistore = callPackage ../applications/misc/camlistore { };
#
#  canto-curses = callPackage ../applications/networking/feedreaders/canto-curses { };
#
#  canto-daemon = callPackage ../applications/networking/feedreaders/canto-daemon { };
#
#  carddav-util = callPackage ../tools/networking/carddav-util { };
#
#  cava = callPackage ../applications/audio/cava { };
#
#  cbatticon = callPackage ../applications/misc/cbatticon { };
#
#  cddiscid = callPackage ../applications/audio/cd-discid { };
#
#  cdrtools = callPackage ../applications/misc/cdrtools { };
#
#  centerim = callPackage ../applications/networking/instant-messengers/centerim { };
#
#  cgminer = callPackage ../applications/misc/cgminer {
#    amdappsdk = amdappsdk28;
#  };
#
#  CharacterCompressor = callPackage ../applications/audio/CharacterCompressor { };
#
#  chatzilla = callPackage ../applications/networking/irc/chatzilla { };
#
#  chirp = callPackage ../applications/misc/chirp {
#    inherit (pythonPackages) pyserial pygtk;
#  };
#
#  chronos = callPackage ../applications/networking/cluster/chronos { };
#
#  chuck = callPackage ../applications/audio/chuck { };
#
#  cinelerra = callPackage ../applications/video/cinelerra { };
#
#  clawsMail = callPackage ../applications/networking/mailreaders/claws-mail {
#    enableNetworkManager = config.networking.networkmanager.enable or false;
#  };
#
#  clipgrab = callPackage ../applications/video/clipgrab { };
#
#  clipit = callPackage ../applications/misc/clipit { };
#
#  cmatrix = callPackage ../applications/misc/cmatrix { };
#
#  cmus = callPackage ../applications/audio/cmus {
#    libjack = libjack2;
#    libcdio = libcdio082;
#
#    pulseaudioSupport = config.pulseaudio or false;
#  };
#
#  communi = callPackage ../applications/networking/irc/communi { };
#
#  CompBus = callPackage ../applications/audio/CompBus { };
#
#  constant-detune-chorus = callPackage ../applications/audio/constant-detune-chorus { };
#
#  copyq = callPackage ../applications/misc/copyq { };
#
#  coriander = callPackage ../applications/video/coriander {
#    inherit (gnome) libgnomeui GConf;
#  };
#
#  cortex = callPackage ../applications/misc/cortex { };
#
#  csound = callPackage ../applications/audio/csound { };
#
#  cinepaint = callPackage ../applications/graphics/cinepaint {
#    fltk = fltk13;
#    libpng = libpng12;
#    cmake = cmake-2_8;
#  };
#
#  codeblocks = callPackage ../applications/editors/codeblocks { };
#  codeblocksFull = callPackage ../applications/editors/codeblocks { contribPlugins = true; };
#
#  comical = callPackage ../applications/graphics/comical { };
#
#  conkeror-unwrapped = callPackage ../applications/networking/browsers/conkeror { };
#  conkeror = wrapFirefox conkeror-unwrapped { };
#
#  cuneiform = callPackage ../tools/graphics/cuneiform {};
#
#  cutecom = callPackage ../tools/misc/cutecom { };
#
#  cutegram =
#    let cp = qt5.callPackage;
#    in cp ../applications/networking/instant-messengers/telegram/cutegram rec {
#      libqtelegram-aseman-edition = cp ../applications/networking/instant-messengers/telegram/libqtelegram-aseman-edition { };
#      telegram-qml = cp ../applications/networking/instant-messengers/telegram/telegram-qml {
#        inherit libqtelegram-aseman-edition;
#      };
#    };
#
#  cvs = callPackage ../applications/version-management/cvs { };
#
#  cvsps = callPackage ../applications/version-management/cvsps { };
#
#  cvs2svn = callPackage ../applications/version-management/cvs2svn { };
#
#  cyclone = callPackage ../applications/audio/pd-plugins/cyclone  { };
#
#  d4x = callPackage ../applications/misc/d4x { };
#
#  darcs = haskell.lib.overrideCabal haskellPackages.darcs (drv: {
#    configureFlags = (stdenv.lib.remove "-flibrary" drv.configureFlags or []) ++ ["-f-library"];
#    enableSharedExecutables = false;
#    enableSharedLibraries = false;
#    isLibrary = false;
#    doHaddock = false;
#    postFixup = "rm -rf $out/lib $out/nix-support $out/share";
#  });
#
#  darktable = callPackage ../applications/graphics/darktable {
#    inherit (gnome) GConf libglade;
#    pugixml = pugixml.override { shared = true; };
#  };
#
#  das_watchdog = callPackage ../tools/system/das_watchdog { };
#
#  dbvisualizer = callPackage ../applications/misc/dbvisualizer {};
#
#  dd-agent = callPackage ../tools/networking/dd-agent { inherit (pythonPackages) tornado; };
#
#  deadbeef = callPackage ../applications/audio/deadbeef {
#    pulseSupport = config.pulseaudio or true;
#  };
#
#  deadbeef-mpris2-plugin = callPackage ../applications/audio/deadbeef/plugins/mpris2.nix { };
#
#  deadbeef-with-plugins = callPackage ../applications/audio/deadbeef/wrapper.nix {
#    plugins = [];
#  };
#
#  dfasma = qt5.callPackage ../applications/audio/dfasma { };
#
#  dia = callPackage ../applications/graphics/dia {
#    inherit (pkgs.gnome) libart_lgpl libgnomeui;
#  };
#
#  diffuse = callPackage ../applications/version-management/diffuse { };
#
#  direwolf = callPackage ../applications/misc/direwolf { };
#
#  dirt = callPackage ../applications/audio/dirt {};
#
#  distrho = callPackage ../applications/audio/distrho {};
#
  djvulibre = callPackage ../applications/misc/djvulibre { };
#
#  djvu2pdf = callPackage ../tools/typesetting/djvu2pdf { };
#
  djview = callPackage ../applications/graphics/djview { };
  djview4 = pkgs.djview;

  dmenu = callPackage ../applications/misc/dmenu { };

  dmenu-wayland = callPackage ../applications/misc/dmenu/wayland.nix { };

  dmenu2 = callPackage ../applications/misc/dmenu2 { };
#
#  dmtx = dmtx-utils;
#
#  dmtx-utils = callPackage (callPackage ../tools/graphics/dmtx-utils) {
#  };
#
#  docker = callPackage ../applications/virtualization/docker { go = go_1_4; };
#
#  docker-gc = callPackage ../applications/virtualization/docker/gc.nix { };
#
#  doodle = callPackage ../applications/search/doodle { };
#
#  drumgizmo = callPackage ../applications/audio/drumgizmo { };
#
#  dunst = callPackage ../applications/misc/dunst { };
#
#  devede = callPackage ../applications/video/devede { };
#
#  dvb_apps  = callPackage ../applications/video/dvb-apps { };
#
#  dvdauthor = callPackage ../applications/video/dvdauthor { };
#
#  dvd-slideshow = callPackage ../applications/video/dvd-slideshow { };
#
#  dwb-unwrapped = callPackage ../applications/networking/browsers/dwb { };
#  dwb = wrapFirefox dwb-unwrapped { desktopName = "dwb"; };
#
#  dwm = callPackage ../applications/window-managers/dwm {
#    patches = config.dwm.patches or [];
#  };
#
#  eaglemode = callPackage ../applications/misc/eaglemode { };
#
#  eclipses = recurseIntoAttrs (callPackage ../applications/editors/eclipse { });
#
  ed = callPackage ../applications/editors/ed { };
#
#  edbrowse = callPackage ../applications/editors/edbrowse { };
#
#  ekho = callPackage ../applications/audio/ekho { };
#
#  electrum = callPackage ../applications/misc/electrum { };
#
#  electrum-dash = callPackage ../applications/misc/electrum-dash { };
#
#  elinks = callPackage ../applications/networking/browsers/elinks { };
#
#  elvis = callPackage ../applications/editors/elvis { };
#
  emacs = pkgs.emacs24;
#
  emacs24 = callPackage ../applications/editors/emacs-24 {
    # use override to enable additional features
    Xaw3d = null;
    gconf = null;
    alsaLib = null;
    imagemagick = null;
    acl = null;
    gpm = null;
  };
#
#  emacs24-nox = lowPrio (appendToName "nox" (emacs24.override {
#    withX = false;
#    withGTK2 = false;
#    withGTK3 = false;
#  }));
#
#  emacs25pre = lowPrio (callPackage ../applications/editors/emacs-25 {
#    # use override to enable additional features
#    libXaw = xorg.libXaw;
#    Xaw3d = null;
#    gconf = null;
#    alsaLib = null;
#    imagemagick = null;
#    acl = null;
#    gpm = null;
#  });
#
#  enhanced-ctorrent = callPackage ../applications/networking/enhanced-ctorrent { };
#
#  epdfview = callPackage ../applications/misc/epdfview { };
#
#  eq10q = callPackage ../applications/audio/eq10q { };
#
#  espeak = callPackage ../applications/audio/espeak { };
#
#  espeakedit = callPackage ../applications/audio/espeak/edit.nix { };
#
#  esniper = callPackage ../applications/networking/esniper { };
#
#  etherape = callPackage ../applications/networking/sniffers/etherape {
#    inherit (gnome) gnomedocutils libgnome libglade libgnomeui scrollkeeper;
#  };
#
#  evilvte = callPackage ../applications/misc/evilvte {
#    configH = config.evilvte.config or "";
#  };
#
#  evopedia = callPackage ../applications/misc/evopedia { };
#
#  keepassx = callPackage ../applications/misc/keepassx { };
#  keepassx2 = callPackage ../applications/misc/keepassx/2.0.nix { };
#
#  keepass = callPackage ../applications/misc/keepass { };
#
#  keepass-keefox = callPackage ../applications/misc/keepass-plugins/keefox { };
#
#  exrdisplay = callPackage ../applications/graphics/exrdisplay {
#    fltk = fltk20;
#  };
#
#  fbreader = callPackage ../applications/misc/fbreader { };
#
#  fetchmail = callPackage ../applications/misc/fetchmail { };
#
#  fldigi = callPackage ../applications/audio/fldigi { };
#
  fluidsynth = callPackage ../applications/audio/fluidsynth { };
#
#  fmit = qt5.callPackage ../applications/audio/fmit { };
#
#  focuswriter = callPackage ../applications/editors/focuswriter { };
#
#  foo-yc20 = callPackage ../applications/audio/foo-yc20 { };
#
#  fossil = callPackage ../applications/version-management/fossil { };
#
#  freewheeling = callPackage ../applications/audio/freewheeling { };
#
  fribid = callPackage ../applications/networking/browsers/mozilla-plugins/fribid { };
#
#  geany = callPackage ../applications/editors/geany { };
#  geany-with-vte = callPackage ../applications/editors/geany/with-vte.nix { };
#
#  gnuradio = callPackage ../applications/misc/gnuradio {
#    inherit (pythonPackages) lxml numpy scipy matplotlib pyopengl;
#  };
#
#  gnuradio-with-packages = callPackage ../applications/misc/gnuradio/wrapper.nix {
#    extraPackages = [ gnuradio-nacl gnuradio-osmosdr ];
#  };
#
#  gnuradio-nacl = callPackage ../applications/misc/gnuradio-nacl { };
#
#  gnuradio-osmosdr = callPackage ../applications/misc/gnuradio-osmosdr { };
#
#  goldendict = callPackage ../applications/misc/goldendict { };
#
#  google-drive-ocamlfuse = callPackage ../applications/networking/google-drive-ocamlfuse { };
#
#  google-musicmanager = callPackage ../applications/audio/google-musicmanager { };
#
#  gpa = callPackage ../applications/misc/gpa { };
#
#  gpicview = callPackage ../applications/graphics/gpicview { };
#
#  gqrx = callPackage ../applications/misc/gqrx { };
#
#  grip = callPackage ../applications/misc/grip {
#    inherit (gnome) libgnome libgnomeui vte;
#  };
#
#  gtimelog = pythonPackages.gtimelog;
#
#  gjay = callPackage ../applications/audio/gjay { };
#
#  photivo = callPackage ../applications/graphics/photivo { };
#
#  wavesurfer = callPackage ../applications/misc/audio/wavesurfer { };
#
#  wireshark-cli = callPackage ../applications/networking/sniffers/wireshark {
#    withQt = false;
#    withGtk = false;
#  };
#  wireshark-gtk = wireshark-cli.override { withGtk = true; };
#  wireshark-qt = wireshark-cli.override { withQt = true; };
#  wireshark = wireshark-gtk;
#
#  fbida = callPackage ../applications/graphics/fbida { };
#
#  fdupes = callPackage ../tools/misc/fdupes { };
#
  feh = callPackage ../applications/graphics/feh { };
#
#  firestr = qt5.callPackage ../applications/networking/p2p/firestr
#    { boost = boost155;
#    };
#
  flashplayer = callPackage ../applications/networking/browsers/mozilla-plugins/flashplayer-11 {
    debug = config.flashplayer.debug or false;
  };
#
#  flashplayer-standalone = pkgsi686Linux.flashplayer.sa;
#
#  flashplayer-standalone-debugger = pkgsi686Linux.flashplayer.saDbg;
#
#  fluxbox = callPackage ../applications/window-managers/fluxbox { };
#
#  fme = callPackage ../applications/misc/fme {
#    inherit (gnome) libglademm;
#  };
#
#  fomp = callPackage ../applications/audio/fomp { };
#
#  freecad = callPackage ../applications/graphics/freecad {
#    boost = boost155;
#    opencascade = opencascade_oce;
#    inherit (pythonPackages) matplotlib pycollada;
#  };
#
#  freemind = callPackage ../applications/misc/freemind { };
#
#  freenet = callPackage ../applications/networking/p2p/freenet { };
#
#  freepv = callPackage ../applications/graphics/freepv { };
#
#  xfontsel = callPackage ../applications/misc/xfontsel { };
#
#  freerdp = callPackage ../applications/networking/remote/freerdp {
#    ffmpeg = ffmpeg_1;
#  };
#
#  freerdpUnstable = callPackage ../applications/networking/remote/freerdp/unstable.nix {
#    cmake = cmake-2_8;
#  };
#
#  freicoin = callPackage ../applications/misc/freicoin {
#    boost = boost155;
#  };
#
  game-music-emu = callPackage ../applications/audio/game-music-emu { };
#
#  gcolor2 = callPackage ../applications/graphics/gcolor2 { };
#
#  get_iplayer = callPackage ../applications/misc/get_iplayer {};
#
  gimp = callPackage ../applications/graphics/gimp { };

#  giv = callPackage ../applications/graphics/giv { };
#
#  gmrun = callPackage ../applications/misc/gmrun {};
#
#  gnucash = callPackage ../applications/office/gnucash {
#    inherit (gnome2) libgnomeui libgtkhtml gtkhtml libbonoboui libgnomeprint libglade libart_lgpl;
#    guile = guile_1_8;
#    slibGuile = slibGuile.override { scheme = guile_1_8; };
#    goffice = goffice_0_8;
#  };
#
#  gnucash26 = lowPrio (callPackage ../applications/office/gnucash/2.6.nix {
#    inherit (gnome2) libgnomecanvas;
#    goffice = goffice_0_8;
#    webkit = webkitgtk2;
#    guile = guile_1_8;
#    slibGuile = slibGuile.override { scheme = guile_1_8; };
#    glib = glib;
#  });
#
#  goffice = callPackage ../development/libraries/goffice { };
#
#  goffice_0_8 = callPackage ../development/libraries/goffice/0.8.nix {
#    inherit (pkgs.gnome2) libglade libgnomeui;
#    libart = pkgs.gnome2.libart_lgpl;
#  };
#
#  idea = recurseIntoAttrs (callPackages ../applications/editors/idea { androidsdk = androidsdk_4_4; });
#
#  libquvi = callPackage ../applications/video/quvi/library.nix { };
#
#  linssid = qt5.callPackage ../applications/networking/linssid { };
#
#  mi2ly = callPackage ../applications/audio/mi2ly {};
#
#  praat = callPackage ../applications/audio/praat { };
#
#  quvi = callPackage ../applications/video/quvi/tool.nix { };
#
#  quvi_scripts = callPackage ../applications/video/quvi/scripts.nix { };
#
#  gkrellm = callPackage ../applications/misc/gkrellm { };
#
#  gmu = callPackage ../applications/audio/gmu { };
#
#  gnome_mplayer = callPackage ../applications/video/gnome-mplayer {
#    inherit (gnome) GConf;
#  };
#
#  gnumeric = callPackage ../applications/office/gnumeric { };
#
#  gnunet = callPackage ../applications/networking/p2p/gnunet { };
#
#  gnunet_svn = lowPrio (callPackage ../applications/networking/p2p/gnunet/svn.nix { });
#
#  gocr = callPackage ../applications/graphics/gocr { };
#
#  gobby5 = callPackage ../applications/editors/gobby {
#    inherit (gnome) gtksourceview;
#  };
#
#  gphoto2 = callPackage ../applications/misc/gphoto2 { };
#
#  gphoto2fs = callPackage ../applications/misc/gphoto2/gphotofs.nix { };
#
#  gramps = callPackage ../applications/misc/gramps { };
#
#  graphicsmagick = callPackage ../applications/graphics/graphicsmagick { };
#  graphicsmagick_q16 = callPackage ../applications/graphics/graphicsmagick { quantumdepth = 16; };
#
#  graphicsmagick137 = callPackage ../applications/graphics/graphicsmagick/1.3.7.nix {
#    libpng = libpng12;
#  };
#
#  gtkpod = callPackage ../applications/audio/gtkpod {
#    inherit (gnome) libglade;
#  };
#
#  jbidwatcher = callPackage ../applications/misc/jbidwatcher {
#    java = jre;
#  };
#
  gecko_mediaplayer = callPackage ../applications/networking/browsers/mozilla-plugins/gecko-mediaplayer {
    inherit (gnome) GConf;
    browser = firefox-unwrapped;
  };
#
#  geeqie = callPackage ../applications/graphics/geeqie { };
#
#  gigedit = callPackage ../applications/audio/gigedit { };
#
#  gqview = callPackage ../applications/graphics/gqview { };
#
#  gmpc = callPackage ../applications/audio/gmpc {};
#
#  gmtk = callPackage ../applications/networking/browsers/mozilla-plugins/gmtk {
#    inherit (gnome) GConf;
#  };
#
#  gollum = callPackage ../applications/misc/gollum { };
#
  google-chrome = callPackage ../applications/networking/browsers/google-chrome { };
#
#  googleearth = callPackage_i686 ../applications/misc/googleearth { };
#
  google_talk_plugin = callPackage ../applications/networking/browsers/mozilla-plugins/google-talk-plugin { };
#
#  gosmore = callPackage ../applications/misc/gosmore { };
#
#  gpsbabel = qt5.callPackage ../applications/misc/gpsbabel { };
#
#  gpscorrelate = callPackage ../applications/misc/gpscorrelate { };
#
#  gpsd = callPackage ../servers/gpsd { };
#
#  gpsprune = callPackage ../applications/misc/gpsprune { };
#
#  gtk2fontsel = callPackage ../applications/misc/gtk2fontsel {
#    inherit (gnome2) gtk;
#  };
#
#  guake = callPackage ../applications/misc/guake {
#    vte = gnome.vte.override { pythonSupport = true; };
#  };
#
#  guitone = callPackage ../applications/version-management/guitone {
#    graphviz = graphviz_2_32;
#  };
#
#  gv = callPackage ../applications/misc/gv { };
#
#  guvcview = callPackage ../os-specific/linux/guvcview {
#    pulseaudioSupport = config.pulseaudio or true;
#  };
#
#  gxmessage = callPackage ../applications/misc/gxmessage { };
#
#  hackrf = callPackage ../applications/misc/hackrf { };
#
#  hamster-time-tracker = callPackage ../applications/misc/hamster-time-tracker {
#    inherit (pythonPackages) pyxdg pygtk dbus sqlite3;
#    inherit (gnome) gnome_python;
#  };
#
#  hello = callPackage ../applications/misc/hello { };
#
#  helmholtz = callPackage ../applications/audio/pd-plugins/helmholtz { };
#
#  heme = callPackage ../applications/editors/heme { };
#
#  herbstluftwm = callPackage ../applications/window-managers/herbstluftwm { };
#
#  hexchat = callPackage ../applications/networking/irc/hexchat { };
#
#  hexcurse = callPackage ../applications/editors/hexcurse { };
#
#  hexedit = callPackage ../applications/editors/hexedit { };
#
#  hipchat = callPackage ../applications/networking/instant-messengers/hipchat { };
#
#  homebank = callPackage ../applications/office/homebank {
#    gtk = gtk3;
#  };
#
#  ht = callPackage ../applications/editors/ht { };
#
#  htmldoc = callPackage ../applications/misc/htmldoc {
#    fltk = fltk13;
#  };
#
#  hugin = callPackage ../applications/graphics/hugin {
#    boost = boost155;
#  };
#
#  hydrogen = callPackage ../applications/audio/hydrogen { };
#
  spectrwm = callPackage ../applications/window-managers/spectrwm { };
#
#  wlc = callPackage ../development/libraries/wlc { };
#  sway = callPackage ../applications/window-managers/sway { };
#
#  swc = callPackage ../development/libraries/swc { };
#  wld = callPackage ../development/libraries/wld { };
#
#  i3 = callPackage ../applications/window-managers/i3 { };
#
#  i3blocks = callPackage ../applications/window-managers/i3/blocks.nix { };
#
#  i3cat = pkgs.goPackages.i3cat.bin // { outputs = [ "bin" ]; };
#
#  i3lock = callPackage ../applications/window-managers/i3/lock.nix {
#    cairo = cairo.override { xcbSupport = true; };
#  };
#
#  i3minator = callPackage ../tools/misc/i3minator { };
#
#  i3status = callPackage ../applications/window-managers/i3/status.nix { };
#
#  i810switch = callPackage ../os-specific/linux/i810switch { };
#
#  id3v2 = callPackage ../applications/audio/id3v2 { };
#
#  ifenslave = callPackage ../os-specific/linux/ifenslave { };
#
#  ii = callPackage ../applications/networking/irc/ii { };
#
#  ike = callPackage ../applications/networking/ike { };
#
#  ikiwiki = callPackage ../applications/misc/ikiwiki {
#    inherit (perlPackages) TextMarkdown URI HTMLParser HTMLScrubber
#      HTMLTemplate TimeDate CGISession DBFile CGIFormBuilder LocaleGettext
#      RpcXML XMLSimple YAML YAMLLibYAML HTMLTree Filechdir
#      AuthenPassphrase NetOpenIDConsumer LWPxParanoidAgent CryptSSLeay;
#    inherit (perlPackages.override { pkgs = pkgs // { imagemagick = imagemagickBig;}; }) PerlMagick;
#  };
#
#  # Impressive, formerly known as "KeyJNote".
#  impressive = callPackage ../applications/office/impressive {
#    # XXX These are the PyOpenGL dependencies, which we need here.
#    inherit (pythonPackages) pyopengl;
#    inherit (pythonPackages) pillow;
#  };
#
#  inspectrum = callPackage ../applications/misc/inspectrum { };
#
#  ipe = qt5.callPackage ../applications/graphics/ipe {
#    ghostscript = ghostscriptX;
#    texlive = texlive.combine { inherit (texlive) scheme-small; };
#  };
#
#  iptraf = callPackage ../applications/networking/iptraf { };
#
#  iptraf-ng = callPackage ../applications/networking/iptraf-ng { };
#
#  irssi = callPackage ../applications/networking/irc/irssi { };
#
#  irssi_fish = callPackage ../applications/networking/irc/irssi/fish { };
#
#  irssi_otr = callPackage ../applications/networking/irc/irssi/otr { };
#
#  ir.lv2 = callPackage ../applications/audio/ir.lv2 { };
#
#  bip = callPackage ../applications/networking/irc/bip { };
#
#  jabref = callPackage ../applications/office/jabref/default.nix { };
#
#  jack_capture = callPackage ../applications/audio/jack-capture { };
#
#  jack_oscrolloscope = callPackage ../applications/audio/jack-oscrolloscope { };
#
#  jack_rack = callPackage ../applications/audio/jack-rack { };
#
#  jackmeter = callPackage ../applications/audio/jackmeter { };
#
#  jackmix = callPackage ../applications/audio/jackmix { };
#  jackmix_jack1 = jackmix.override { jack = jack1; };
#
#  jalv = callPackage ../applications/audio/jalv { };
#
#  jamin = callPackage ../applications/audio/jamin { };
#
#  jedit = callPackage ../applications/editors/jedit { };
#
#  jigdo = callPackage ../applications/misc/jigdo { };
#
#  jitsi = callPackage ../applications/networking/instant-messengers/jitsi { };
#
#  joe = callPackage ../applications/editors/joe { };
#
#  josm = callPackage ../applications/misc/josm { };
#
#  jbrout = callPackage ../applications/graphics/jbrout { };
#
#  k3d = callPackage ../applications/graphics/k3d {
#    inherit (pkgs.gnome2) gtkglext;
#    boost = boost155;
#  };
#
#  keepnote = callPackage ../applications/office/keepnote {
#    pygtk = pyGtkGlade;
#  };
#
#  kermit = callPackage ../tools/misc/kermit { };
#
#  keyfinder = qt55.callPackage ../applications/audio/keyfinder { };
#
#  keyfinder-cli = qt5.callPackage ../applications/audio/keyfinder-cli { };
#
#  keymon = callPackage ../applications/video/key-mon { };
#
#  khal = callPackage ../applications/misc/khal { };
#
#  khard = callPackage ../applications/misc/khard { };
#
#  kid3 = callPackage ../applications/audio/kid3 {
#    qt = qt4;
#  };
#
#  kino = callPackage ../applications/video/kino {
#    inherit (gnome) libglade;
#  };
#
#  kiwix = callPackage ../applications/misc/kiwix { };
#
#  koji = callPackage ../tools/package-management/koji { };
#
#  ksuperkey = callPackage ../tools/X11/ksuperkey { };
#
  lame = callPackage ../development/libraries/lame { };
#
#  lash = callPackage ../applications/audio/lash { };
#
  ladspaH = callPackage ../applications/audio/ladspa-sdk/ladspah.nix { };
#
#  ladspaPlugins = callPackage ../applications/audio/ladspa-plugins {
#    fftw = fftwSinglePrec;
#  };
#
#  ladspaPlugins-git = callPackage ../applications/audio/ladspa-plugins/git.nix {
#    fftw = fftwSinglePrec;
#  };
#
#  ladspa-sdk = callPackage ../applications/audio/ladspa-sdk { };
#
#  caps = callPackage ../applications/audio/caps { };
#
#  LazyLimiter = callPackage ../applications/audio/LazyLimiter { };
#
#  lastwatch = callPackage ../applications/audio/lastwatch { };
#
#  lastfmsubmitd = callPackage ../applications/audio/lastfmsubmitd { };
#
#  lbdb = callPackage ../tools/misc/lbdb { };
#
#  lbzip2 = callPackage ../tools/compression/lbzip2 { };
#
#  ldcpp = callPackage ../applications/networking/p2p/ldcpp {
#    inherit (gnome) libglade;
#  };
#
#  leo-editor = callPackage ../applications/editors/leo-editor { };
#
#  libowfat = callPackage ../development/libraries/libowfat { };
#
#  librecad = callPackage ../applications/misc/librecad { };
#  librecad2 = librecad;  # backwards compatibility alias, added 2015-10
#
#  libreoffice = callPackage ../applications/office/libreoffice {
#    inherit (perlPackages) ArchiveZip CompressZlib;
#    inherit (gnome) GConf ORBit2 gnome_vfs;
#    zip = zip.override { enableNLS = false; };
#    #glm = glm_0954;
#    bluez5 = bluez5_28;
#    fontsConf = makeFontsConf {
#      fontDirectories = [
#        freefont_ttf xorg.fontmiscmisc xorg.fontbhttf
#      ];
#    };
#    clucene_core = clucene_core_2;
#    lcms = lcms2;
#  };
#
#  liferea = callPackage ../applications/networking/newsreaders/liferea {
#    webkitgtk = webkitgtk24x;
#  };
#
#  lingot = callPackage ../applications/audio/lingot {
#    inherit (gnome) libglade;
#  };
#
#  ledger2 = callPackage ../applications/office/ledger/2.6.3.nix { };
#  ledger3 = callPackage ../applications/office/ledger {
#    boost = boost155;
#  };
#  ledger = ledger3;
#
#  lighttable = callPackage ../applications/editors/lighttable {};
#
#  links2 = callPackage ../applications/networking/browsers/links2 { };
#
#  linphone = callPackage ../applications/networking/instant-messengers/linphone rec { };
#
#  linuxsampler = callPackage ../applications/audio/linuxsampler {
#    bison = bison2;
#  };
#
#  llpp = callPackage ../applications/misc/llpp {
#    inherit (ocamlPackages_4_02) lablgl findlib;
#    ocaml = ocaml_4_02;
#  };
#
#  lmms = callPackage ../applications/audio/lmms { };
#
#  loxodo = callPackage ../applications/misc/loxodo { };
#
#  lrzsz = callPackage ../tools/misc/lrzsz { };
#
#  luakit = callPackage ../applications/networking/browsers/luakit {
#      inherit (lua51Packages) luafilesystem luasqlite3;
#      gtk = gtk3;
#      webkit = webkitgtk2;
#  };
#
#  luminanceHDR = qt5.callPackage ../applications/graphics/luminance-hdr { };
#
#  lxdvdrip = callPackage ../applications/video/lxdvdrip { };
#
#  handbrake = callPackage ../applications/video/handbrake {
#    webkitgtk = webkitgtk24x;
#  };
#
#  lilyterm = callPackage ../applications/misc/lilyterm {
#    inherit (gnome) vte;
#    gtk = gtk2;
#  };
#
#  lynx = callPackage ../applications/networking/browsers/lynx { };
#
#  lyx = callPackage ../applications/misc/lyx { };
#
#  makeself = callPackage ../applications/misc/makeself { };
#
#  marathon = callPackage ../applications/networking/cluster/marathon { };
#
#  MBdistortion = callPackage ../applications/audio/MBdistortion { };
#
  mcpp = callPackage ../development/compilers/mcpp { };
#
#  mda_lv2 = callPackage ../applications/audio/mda-lv2 { };
#
  mediainfo = callPackage ../applications/misc/mediainfo { };
#
#  mediainfo-gui = callPackage ../applications/misc/mediainfo-gui { };
#
#  mediathekview = callPackage ../applications/video/mediathekview { };
#
#  meld = callPackage ../applications/version-management/meld { };
#
#  mcomix = callPackage ../applications/graphics/mcomix { };
#
#  mendeley = callPackage ../applications/office/mendeley { };
#
#  merkaartor = callPackage ../applications/misc/merkaartor { };
#
#  meshlab = callPackage ../applications/graphics/meshlab { };
#
#  metersLv2 = callPackage ../applications/audio/meters_lv2 { };
#
#  mhwaveedit = callPackage ../applications/audio/mhwaveedit {};
#
#  mid2key = callPackage ../applications/audio/mid2key { };
#
#  midori-unwrapped = callPackage ../applications/networking/browsers/midori {
#    webkitgtk = webkitgtk24x;
#  };
#  midori = wrapFirefox midori-unwrapped { };
#
#  mikmod = callPackage ../applications/audio/mikmod { };
#
#  minicom = callPackage ../tools/misc/minicom { };
#
#  minimodem = callPackage ../applications/audio/minimodem { };
#
#  minidjvu = callPackage ../applications/graphics/minidjvu { };
#
#  minitube = callPackage ../applications/video/minitube { };
#
#  mimms = callPackage ../applications/audio/mimms {};
#
#  mirage = callPackage ../applications/graphics/mirage {
#    inherit (pythonPackages) pygtk;
#    inherit (pythonPackages) pillow;
#  };
#
#  mjpg-streamer = callPackage ../applications/video/mjpg-streamer { };
#
#  mldonkey = callPackage ../applications/networking/p2p/mldonkey { };
#
#  mmex = callPackage ../applications/office/mmex { };
#
#  moc = callPackage ../applications/audio/moc { };
#
#  mod-distortion = callPackage ../applications/audio/mod-distortion { };
#
#  monero = callPackage ../applications/misc/monero { };
#
#  monkeysAudio = callPackage ../applications/audio/monkeys-audio { };
#
#  monkeysphere = callPackage ../tools/security/monkeysphere { };
#
#  monodevelop = callPackage ../applications/editors/monodevelop {};
#
#  monotone = callPackage ../applications/version-management/monotone {
#    lua = lua5;
#  };
#
#  monotoneViz = callPackage ../applications/version-management/monotone-viz {
#    inherit (ocamlPackages_4_01_0) lablgtk ocaml camlp4;
#    inherit (gnome) libgnomecanvas glib;
#  };
#
#  mopidy = callPackage ../applications/audio/mopidy { };
#
#  mopidy-gmusic = callPackage ../applications/audio/mopidy-gmusic { };
#
#  mopidy-spotify = callPackage ../applications/audio/mopidy-spotify { };
#
#  mopidy-moped = callPackage ../applications/audio/mopidy-moped { };
#
#  mopidy-mopify = callPackage ../applications/audio/mopidy-mopify { };
#
#  mopidy-spotify-tunigo = callPackage ../applications/audio/mopidy-spotify-tunigo { };
#
#  mopidy-youtube = callPackage ../applications/audio/mopidy-youtube { };
#
#  mopidy-soundcloud = callPackage ../applications/audio/mopidy-soundcloud { };
#
#  mopidy-musicbox-webclient = callPackage ../applications/audio/mopidy-musicbox-webclient { };
#
#  mozplugger = callPackage ../applications/networking/browsers/mozilla-plugins/mozplugger {};
#
#  mozjpeg = callPackage ../applications/graphics/mozjpeg { };
#
#  easytag = callPackage ../applications/audio/easytag { };
#
#  mp3gain = callPackage ../applications/audio/mp3gain { };
#
#  mp3info = callPackage ../applications/audio/mp3info { };
#
#  mp3splt = callPackage ../applications/audio/mp3splt { };
#
  mp3val = callPackage ../applications/audio/mp3val { };
#
#  mpc123 = callPackage ../applications/audio/mpc123 { };
#
  mpg123 = callPackage ../applications/audio/mpg123 { };
#
#  mpg321 = callPackage ../applications/audio/mpg321 { };
#
#  mpc_cli = callPackage ../applications/audio/mpc { };
#
#  nload = callPackage ../applications/networking/nload { };
#
#  normalize = callPackage ../applications/audio/normalize { };

#  mrpeach = callPackage ../applications/audio/pd-plugins/mrpeach { };
#
#  mrxvt = callPackage ../applications/misc/mrxvt { };
#
#  multimarkdown = callPackage ../tools/typesetting/multimarkdown { };
#
#  multimon-ng = callPackage ../applications/misc/multimon-ng { };
#
#  multisync = callPackage ../applications/misc/multisync {
#    inherit (gnome) ORBit2 libbonobo libgnomeui GConf;
#  };
#
#  musescore = qt5.callPackage ../applications/audio/musescore { };
#
#  mutt = callPackage ../applications/networking/mailreaders/mutt { };
#  mutt-with-sidebar = callPackage ../applications/networking/mailreaders/mutt {
#    withSidebar = true;
#  };
#
#  mutt-kz = callPackage ../applications/networking/mailreaders/mutt-kz { };
#
#  openshift = callPackage ../applications/networking/cluster/openshift { };
#
#  ostinato = callPackage ../applications/networking/ostinato { };
#
#  panamax_api = callPackage ../applications/networking/cluster/panamax/api {
#    ruby = ruby_2_1;
#  };
#  panamax_ui = callPackage ../applications/networking/cluster/panamax/ui {
#    ruby = ruby_2_1;
#  };
#
#  pcmanfm = callPackage ../applications/misc/pcmanfm { };
#
#  pig = callPackage ../applications/networking/cluster/pig { };
#
#  pijul = callPackage ../applications/version-management/pijul {
#    inherit (ocamlPackages) findlib cryptokit yojson;
#  };
#
#  playonlinux = callPackage ../applications/misc/playonlinux {
#     stdenv = stdenv_32bit;
#  };
#
#  shotcut = qt5.callPackage ../applications/video/shotcut { };
#
#  smplayer = qt5.callPackage ../applications/video/smplayer { };
#
#  smtube = qt5.callPackage ../applications/video/smtube {};
#
#  sup = callPackage ../applications/networking/mailreaders/sup {
#    ruby = ruby_1_9_3.override { cursesSupport = true; };
#  };
#
#  synapse = callPackage ../applications/misc/synapse { };
#
#  synfigstudio = callPackage ../applications/graphics/synfigstudio {
#    fontsConf = makeFontsConf { fontDirectories = [ freefont_ttf ]; };
#  };
#
#  librep = callPackage ../development/libraries/librep { };
#
#  rep-gtk = callPackage ../development/libraries/rep-gtk { };
#
#  msmtp = callPackage ../applications/networking/msmtp { };
#
#  imapfilter = callPackage ../applications/networking/mailreaders/imapfilter.nix {
#    lua = lua5;
# };
#
#  maxlib = callPackage ../applications/audio/pd-plugins/maxlib { };
#
#  pdfdiff = callPackage ../applications/misc/pdfdiff { };
#
  mupdf = callPackage ../applications/misc/mupdf {
    openjpeg = pkgs.openjpeg_2_0;
  };
#
#  diffpdf = callPackage ../applications/misc/diffpdf { };
#
#  mypaint = callPackage ../applications/graphics/mypaint { };
#
#  mythtv = callPackage ../applications/video/mythtv { };
#
#  nanoblogger = callPackage ../applications/misc/nanoblogger { };
#
#  navipowm = callPackage ../applications/misc/navipowm { };
#
#  navit = callPackage ../applications/misc/navit { };
#
#  netbeans = callPackage ../applications/editors/netbeans { };
#
  ncdu = callPackage ../tools/misc/ncdu { };
#
#  ne = callPackage ../applications/editors/ne { };
#
#  nedit = callPackage ../applications/editors/nedit {
#    motif = lesstif;
#  };
#
#  notmuch = callPackage ../applications/networking/mailreaders/notmuch {
#    # No need to build Emacs - notmuch.el works just fine without
#    # byte-compilation. Use emacs24Packages.notmuch if you want to
#    # byte-compiled files
#    emacs = null;
#    sphinx = pythonPackages.sphinx;
#  };
#
#  # Open Stack
#  nova = callPackage ../applications/virtualization/openstack/nova.nix { };
#  keystone = callPackage ../applications/virtualization/openstack/keystone.nix { };
#  neutron = callPackage ../applications/virtualization/openstack/neutron.nix { };
#  glance = callPackage ../applications/virtualization/openstack/glance.nix { };
#
#  nova-filters =  callPackage ../applications/audio/nova-filters { };
#
#  nspluginwrapper = callPackage ../applications/networking/browsers/mozilla-plugins/nspluginwrapper {};
#
#  nvi = callPackage ../applications/editors/nvi { };
#
#  nvpy = callPackage ../applications/editors/nvpy { };
#
#  obconf = callPackage ../tools/X11/obconf {
#    inherit (gnome) libglade;
#  };
#
#  obs-studio = qt5.callPackage ../applications/video/obs-studio {
#    pulseaudioSupport = config.pulseaudio or true;
#  };
#
#  ocrad = callPackage ../applications/graphics/ocrad { };
#
#  offrss = callPackage ../applications/networking/offrss { };
#
#  ogmtools = callPackage ../applications/video/ogmtools { };
#
#  omxplayer = callPackage ../applications/video/omxplayer { };
#
#  oneteam = callPackage ../applications/networking/instant-messengers/oneteam {};
#
#  openbox = callPackage ../applications/window-managers/openbox { };
#
#  openbox-menu = callPackage ../applications/misc/openbox-menu { };
#
#  openimageio = callPackage ../applications/graphics/openimageio { };
#
#  openjump = callPackage ../applications/misc/openjump { };
#
#  openscad = callPackage ../applications/graphics/openscad {};
#
#  opera = callPackage ../applications/networking/browsers/opera {
#    inherit (pkgs.kde4) kdelibs;
#  };
#
  opusfile = callPackage ../applications/audio/opusfile { };
#
#  opusTools = callPackage ../applications/audio/opus-tools { };
#
#  orpie = callPackage ../applications/misc/orpie { gsl = gsl_1; };
#
#  osmo = callPackage ../applications/office/osmo { };
#
#  pamixer = callPackage ../applications/audio/pamixer { };
#
#  pan = callPackage ../applications/networking/newsreaders/pan {
#    spellChecking = false;
#  };
#
#  panotools = callPackage ../applications/graphics/panotools { };
#
#  paprefs = callPackage ../applications/audio/paprefs {
#    inherit (gnome) libglademm gconfmm;
#  };
#
#  paraview = callPackage ../applications/graphics/paraview { };
#
#  pencil = callPackage ../applications/graphics/pencil { };
#
#  petrifoo = callPackage ../applications/audio/petrifoo {
#    inherit (gnome) libgnomecanvas;
#  };
#
#  pdftk = callPackage ../tools/typesetting/pdftk { };
#  pdfgrep  = callPackage ../tools/typesetting/pdfgrep { };
#
#  pdfpc = callPackage ../applications/misc/pdfpc { };
#
#  pflask = callPackage ../os-specific/linux/pflask {};
#
#  photoqt = qt5.callPackage ../applications/graphics/photoqt { };
#
#  phototonic = qt5.callPackage ../applications/graphics/phototonic { };
#
#  pianobar = callPackage ../applications/audio/pianobar { };
#
#  pianobooster = callPackage ../applications/audio/pianobooster { };
#
#  picard = callPackage ../applications/audio/picard {
#    python-libdiscid = pythonPackages.discid;
#    mutagen = pythonPackages.mutagen;
#  };
#
#  picocom = callPackage ../tools/misc/picocom { };
#
#  pidgin = callPackage ../applications/networking/instant-messengers/pidgin {
#    openssl = if config.pidgin.openssl or true then openssl else null;
#    gnutls = if config.pidgin.gnutls or false then gnutls else null;
#    libgcrypt = if config.pidgin.gnutls or false then libgcrypt else null;
#    startupnotification = libstartup_notification;
#  };
#
#  pidgin-with-plugins = callPackage ../applications/networking/instant-messengers/pidgin/wrapper.nix {
#    plugins = [];
#  };
#
#  pidginlatex = callPackage ../applications/networking/instant-messengers/pidgin-plugins/pidgin-latex {
#    texLive = texlive.combined.scheme-basic;
#  };
#
#  pidginmsnpecan = callPackage ../applications/networking/instant-messengers/pidgin-plugins/msn-pecan { };
#
#  pidgin-mra = callPackage ../applications/networking/instant-messengers/pidgin-plugins/pidgin-mra { };
#
#  pidgin-skypeweb = callPackage ../applications/networking/instant-messengers/pidgin-plugins/pidgin-skypeweb { };
#
#  pidginotr = callPackage ../applications/networking/instant-messengers/pidgin-plugins/otr { };
#
#  pidginsipe = callPackage ../applications/networking/instant-messengers/pidgin-plugins/sipe { };
#
#  pidginwindowmerge = callPackage ../applications/networking/instant-messengers/pidgin-plugins/window-merge { };
#
#  purple-plugin-pack = callPackage ../applications/networking/instant-messengers/pidgin-plugins/purple-plugin-pack { };
#
#  purple-vk-plugin = callPackage ../applications/networking/instant-messengers/pidgin-plugins/purple-vk-plugin { };
#
#  toxprpl = callPackage ../applications/networking/instant-messengers/pidgin-plugins/tox-prpl { };
#
#  pidgin-opensteamworks = callPackage ../applications/networking/instant-messengers/pidgin-plugins/pidgin-opensteamworks { };
#
#  pithos = callPackage ../applications/audio/pithos {
#    pythonPackages = python34Packages;
#  };
#
#  pinfo = callPackage ../applications/misc/pinfo { };
#
#  pinpoint = callPackage ../applications/office/pinpoint {
#    clutter = clutter_1_24;
#    clutter_gtk = clutter_gtk_1_6;
#  };
#
#  pinta = callPackage ../applications/graphics/pinta {
#    gtksharp = gtk-sharp;
#  };
#
#  plugin-torture = callPackage ../applications/audio/plugin-torture { };
#
#  poezio = python3Packages.poezio;
#
#  pommed = callPackage ../os-specific/linux/pommed {};
#
#  pond = pkgs.goPackages.pond.bin // { outputs = [ "bin" ]; };
#
#  ponymix = callPackage ../applications/audio/ponymix { };
#
#  posterazor = callPackage ../applications/misc/posterazor { };
#
#  pqiv = callPackage ../applications/graphics/pqiv { };
#
#  qiv = callPackage ../applications/graphics/qiv { };
#
#  processing = callPackage ../applications/graphics/processing {
#    jdk = jdk7;
#  };
#
#  # perhaps there are better apps for this task? It's how I had configured my preivous system.
#  # And I don't want to rewrite all rules
#  procmail = callPackage ../applications/misc/procmail { };
#
#  profanity = callPackage ../applications/networking/instant-messengers/profanity {
#    notifySupport   = config.profanity.notifySupport   or true;
#    autoAwaySupport = config.profanity.autoAwaySupport or true;
#  };
#
#  pstree = callPackage ../applications/misc/pstree { };
#
#  pulseview = callPackage ../applications/science/electronics/pulseview { };
#
#  puredata = callPackage ../applications/audio/puredata { };
#  puredata-with-plugins = plugins: callPackage ../applications/audio/puredata/wrapper.nix { inherit plugins; };
#
#  puremapping = callPackage ../applications/audio/pd-plugins/puremapping { };
#
#  pybitmessage = callPackage ../applications/networking/instant-messengers/pybitmessage { };
#
#  pythonmagick = callPackage ../applications/graphics/PythonMagick { };
#
#  eiskaltdcpp = callPackage ../applications/networking/p2p/eiskaltdcpp { };
#
#  qemu = callPackage ../applications/virtualization/qemu {
#    gtk = gtk3;
#    bluez = bluez5;
#    mesa = mesa_noglu;
#  };
#
#  qemu-nix = qemu.override { type = "nix"; };
#
#  QmidiNet = callPackage ../applications/audio/QmidiNet { };
#
#  qmidiroute = callPackage ../applications/audio/qmidiroute { };
#
#  qmmp = callPackage ../applications/audio/qmmp { };
#
#  qrcode = callPackage ../tools/graphics/qrcode {};
#
#  qsampler = callPackage ../applications/audio/qsampler { };
#
#  qsynth = callPackage ../applications/audio/qsynth { };
#
#  qtox = qt5.callPackage ../applications/networking/instant-messengers/qtox { };
#
#  qtpass = qt5.callPackage ../applications/misc/qtpass { };
#
#  qtpfsgui = callPackage ../applications/graphics/qtpfsgui { };
#
#  qtractor = callPackage ../applications/audio/qtractor { };
#
#  qtscrobbler = callPackage ../applications/audio/qtscrobbler { };
#
#  quirc = callPackage ../tools/graphics/quirc {};
#
#  quodlibet = callPackage ../applications/audio/quodlibet {
#    inherit (pythonPackages) mutagen;
#  };
#
#  quodlibet-with-gst-plugins = callPackage ../applications/audio/quodlibet {
#    inherit (pythonPackages) mutagen;
#    withGstPlugins = true;
#    gst-plugins-bad_0 = null;
#  };
#
#  qutebrowser = qt55.callPackage ../applications/networking/browsers/qutebrowser {
#    inherit (python34Packages) buildPythonPackage python pyqt5 jinja2 pygments pyyaml pypeg2;
#    inherit (gst_all_1) gst-plugins-base gst-plugins-good gst-plugins-bad gst-libav;
#  };
#
#  rabbitvcs = callPackage ../applications/version-management/rabbitvcs {};
#
#  rakarrack = callPackage ../applications/audio/rakarrack {
#    fltk = fltk13;
#  };
#
#  renoise = callPackage ../applications/audio/renoise {
#    demo = false;
#  };
#
#  rapcad = qt5.callPackage ../applications/graphics/rapcad {};
#
#  rapidsvn = callPackage ../applications/version-management/rapidsvn { };
#
#  ratmen = callPackage ../tools/X11/ratmen {};
#
#  ratox = callPackage ../applications/networking/instant-messengers/ratox { };
#
#  rawtherapee = callPackage ../applications/graphics/rawtherapee {
#    fftw = fftwSinglePrec;
#  };
#
#  rcs = callPackage ../applications/version-management/rcs { };
#
#  rdesktop = callPackage ../applications/networking/remote/rdesktop { };
#
#  recode = callPackage ../tools/text/recode { };
#
#  remotebox = callPackage ../applications/virtualization/remotebox { };
#
#  retroshare = callPackage ../applications/networking/p2p/retroshare {
#    qt = qt4;
#  };
#
#  retroshare06 = lowPrio (callPackage ../applications/networking/p2p/retroshare/0.6.nix {
#    qt = qt4;
#  });
#
#  RhythmDelay = callPackage ../applications/audio/RhythmDelay { };
#
#  ricochet = qt5.callPackage ../applications/networking/instant-messengers/ricochet { };
#
#  rkt = callPackage ../applications/virtualization/rkt { };
#
#  rofi = callPackage ../applications/misc/rofi { };
#
#  rofi-pass = callPackage ../tools/security/pass/rofi-pass.nix { };
#
#  rstudio = callPackage ../applications/editors/rstudio { };
#
  rsync = callPackage ../applications/networking/sync/rsync { };
#
#  rtl-sdr = callPackage ../applications/misc/rtl-sdr { };
#
#  rtv = callPackage ../applications/misc/rtv { };
#
#  rubyripper = callPackage ../applications/audio/rubyripper {};
#
#  rxvt = callPackage ../applications/misc/rxvt { };
#
#  # = urxvt
#  rxvt_unicode = callPackage ../applications/misc/rxvt_unicode {
#    perlSupport = true;
#    gdkPixbufSupport = true;
#    unicode3Support = true;
#  };
#
#  udevil = callPackage ../applications/misc/udevil {};
#
#  # urxvt plugins
#  urxvt_perl = callPackage ../applications/misc/rxvt_unicode-plugins/urxvt-perl { };
#  urxvt_perls = callPackage ../applications/misc/rxvt_unicode-plugins/urxvt-perls { };
#  urxvt_tabbedex = callPackage ../applications/misc/rxvt_unicode-plugins/urxvt-tabbedex { };
#  urxvt_font_size = callPackage ../applications/misc/rxvt_unicode-plugins/urxvt-font-size { };
#
#  rxvt_unicode-with-plugins = callPackage ../applications/misc/rxvt_unicode/wrapper.nix {
#    plugins = [ urxvt_perl urxvt_perls urxvt_tabbedex urxvt_font_size ];
#  };
#
#  sbagen = callPackage ../applications/misc/sbagen { };
#
#  scantailor = callPackage ../applications/graphics/scantailor {
#    boost = boost155;
#  };
#
#  sc-im = callPackage ../applications/misc/sc-im { };
#
#  scite = callPackage ../applications/editors/scite { };
#
#  scribus = callPackage ../applications/office/scribus {
#    inherit (gnome) libart_lgpl;
#  };
#
#  seafile-client = callPackage ../applications/networking/seafile-client { };
#
#  seeks = callPackage ../tools/networking/p2p/seeks {
#    protobuf = protobuf2_5;
#  };
#
#  seg3d = callPackage ../applications/graphics/seg3d {
#    wxGTK = wxGTK28.override { unicode = false; };
#  };
#
#  sent = callPackage ../applications/misc/sent { };
#
#  seq24 = callPackage ../applications/audio/seq24 { };
#
#  setbfree = callPackage ../applications/audio/setbfree { };
#
#  sflphone = callPackage ../applications/networking/instant-messengers/sflphone {
#    gtk = gtk3;
#  };
#
#  simple-scan = callPackage ../applications/graphics/simple-scan { };
#
#  siproxd = callPackage ../applications/networking/siproxd { };
#
#  skype = callPackage_i686 ../applications/networking/instant-messengers/skype { };
#
#  skype4pidgin = callPackage ../applications/networking/instant-messengers/pidgin-plugins/skype4pidgin { };
#
#  skype_call_recorder = callPackage ../applications/networking/instant-messengers/skype-call-recorder { };
#
#  slmenu = callPackage ../applications/misc/slmenu {};
#
#  slop = callPackage ../tools/misc/slop {};
#
#  slrn = callPackage ../applications/networking/newsreaders/slrn { };
#
#  sooperlooper = callPackage ../applications/audio/sooperlooper { };
#
#  sorcer = callPackage ../applications/audio/sorcer { };
#
#  sound-juicer = callPackage ../applications/audio/sound-juicer { };
#
#  spideroak = callPackage ../applications/networking/spideroak { };
#
#  ssvnc = callPackage ../applications/networking/remote/ssvnc { };
#
#  viber = callPackage ../applications/networking/instant-messengers/viber { };
#
#  sonic-pi = callPackage ../applications/audio/sonic-pi { };
#
  st = callPackage ../applications/misc/st {
    conf = config.st.conf or null;
  };
#
  st-wayland = callPackage ../applications/misc/st/wayland.nix {
    conf = config.st.conf or null;
  };
#
#  stag = callPackage ../applications/misc/stag {
#    curses = ncurses;
#  };
#
#  stella = callPackage ../misc/emulators/stella { };
#
#  statsd = callPackage ../tools/networking/statsd {
#    nodejs = nodejs-0_10;
#  };
#
#  linuxstopmotion = callPackage ../applications/video/linuxstopmotion { };
#
#  sweethome3d = recurseIntoAttrs (  (callPackage ../applications/misc/sweethome3d { })
#                                 // (callPackage ../applications/misc/sweethome3d/editors.nix {
#                                      sweethome3dApp = sweethome3d.application;
#                                    })
#                                 );
#
#  swingsane = callPackage ../applications/graphics/swingsane { };
#
#  sxiv = callPackage ../applications/graphics/sxiv { };
#
#  copy-com = callPackage ../applications/networking/copy-com { };
#
#  dropbox-cli = callPackage ../applications/networking/dropbox-cli { };
#
  lightdm = pkgs.qt5.callPackage ../applications/display-managers/lightdm {
    qt4 = null;
    withQt5 = false;
  };
#
#  lightdm_qt = lightdm.override { withQt5 = true; };
#
  lightdm_gtk_greeter = callPackage ../applications/display-managers/lightdm-gtk-greeter { };
#
#  slic3r = callPackage ../applications/misc/slic3r { };
#
#  curaengine = callPackage ../applications/misc/curaengine { };
#
#  cura = callPackage ../applications/misc/cura { };
#
#  curaLulzbot = callPackage ../applications/misc/cura/lulzbot.nix { };
#
#  peru = callPackage ../applications/version-management/peru {};
#
#  printrun = callPackage ../applications/misc/printrun { };
#
#  sddm = kde5.sddm;
#
#  smartgithg = callPackage ../applications/version-management/smartgithg { };
#
#  slimThemes = recurseIntoAttrs (callPackage ../applications/display-managers/slim/themes.nix {});
#
#  smartdeblur = callPackage ../applications/graphics/smartdeblur { };
#
#  snapper = callPackage ../tools/misc/snapper { };
#
#  snd = callPackage ../applications/audio/snd { };
#
#  shntool = callPackage ../applications/audio/shntool { };
#
#  sipp = callPackage ../development/tools/misc/sipp { };
#
#  sonic-visualiser = qt5.callPackage ../applications/audio/sonic-visualiser {
#    inherit (pkgs.vamp) vampSDK;
#  };
#
  sox = callPackage ../applications/misc/audio/sox { };

  soxr = callPackage ../applications/misc/audio/soxr { };
#
#  spek = callPackage ../applications/audio/spek { };
#
  spotify = callPackage ../applications/audio/spotify {
    inherit (gnome) GConf;
    libgcrypt = libgcrypt_1_5;
  };
#
#  libspotify = callPackage ../development/libraries/libspotify {
#    apiKey = config.libspotify.apiKey or null;
#  };
#
#  ltunify = callPackage ../tools/misc/ltunify { };
#
#  src = callPackage ../applications/version-management/src/default.nix { };
#
#  subversionClient = appendToName "client" (pkgs.subversion.override {
#    bdbSupport = false;
#    perlBindings = true;
#    pythonBindings = true;
#  });
#
  subunit = callPackage ../development/libraries/subunit { };
#
#  surf = callPackage ../applications/networking/browsers/surf {
#    webkit = webkitgtk2;
#  };
#
#  swh_lv2 = callPackage ../applications/audio/swh-lv2 { };
#
#  sylpheed = callPackage ../applications/networking/mailreaders/sylpheed { };
#
#  symlinks = callPackage ../tools/system/symlinks { };
#
  syncthing = pkgs.goPackages.syncthing.bin // { outputs = [ "bin" ]; };
#  discosrv = pkgs.goPackages.discosrv.bin // { outputs = [ "bin" ]; };
#  relaysrv = pkgs.goPackages.relaysrv.bin // { outputs = [ "bin" ]; };
#
#  # linux only by now
#  synergy = callPackage ../applications/misc/synergy { };
#
#  tagainijisho = callPackage ../applications/office/tagainijisho {};
#
#  tahoelafs = callPackage ../tools/networking/p2p/tahoe-lafs {
#    inherit (pythonPackages) twisted foolscap simplejson nevow zfec
#      pycryptopp sqlite3 darcsver setuptoolsTrial setuptoolsDarcs
#      numpy pyasn1 mock zope_interface;
#  };
#
#  tailor = callPackage ../applications/version-management/tailor {};
#
#  tangogps = callPackage ../applications/misc/tangogps { };
#
  teamspeak_client = qt55.callPackage ../applications/networking/instant-messengers/teamspeak/client.nix { };
#  teamspeak_server = callPackage ../applications/networking/instant-messengers/teamspeak/server.nix { };
#
#  taskjuggler = callPackage ../applications/misc/taskjuggler { };
#
#  tasknc = callPackage ../applications/misc/tasknc { };
#
#  taskwarrior = callPackage ../applications/misc/taskwarrior { };
#
#  taskserver = callPackage ../servers/misc/taskserver { };
#
#  telegram-cli = callPackage ../applications/networking/instant-messengers/telegram/telegram-cli/default.nix { };
#
#  telepathy_gabble = callPackage ../applications/networking/instant-messengers/telepathy/gabble { };
#
#  telepathy_haze = callPackage ../applications/networking/instant-messengers/telepathy/haze {};
#
  telepathy_logger = callPackage ../applications/networking/instant-messengers/telepathy/logger {};

  telepathy_mission_control = callPackage ../applications/networking/instant-messengers/telepathy/mission-control { };
#
#  telepathy_rakia = callPackage ../applications/networking/instant-messengers/telepathy/rakia { };
#
#  telepathy_salut = callPackage ../applications/networking/instant-messengers/telepathy/salut {};
#
#  telepathy_idle = callPackage ../applications/networking/instant-messengers/telepathy/idle {};
#
#  terminal-notifier = callPackage ../applications/misc/terminal-notifier {};
#
#  terminator = callPackage ../applications/misc/terminator {
#    vte = gnome.vte.override { pythonSupport = true; };
#    inherit (pythonPackages) notify;
#  };
#
#  termite = callPackage ../applications/misc/termite { };
#
  tesseract = callPackage ../applications/graphics/tesseract { };
#
#  tetraproc = callPackage ../applications/audio/tetraproc { };
#
#  thinkingRock = callPackage ../applications/misc/thinking-rock { };
#
#  thunderbird = callPackage ../applications/networking/mailreaders/thunderbird {
#    inherit (gnome) libIDL;
#    inherit (pythonPackages) pysqlite;
#    libpng = libpng_apng;
#  };
#
#  thunderbird-bin = callPackage ../applications/networking/mailreaders/thunderbird-bin {
#    inherit (pkgs.gnome) libgnome libgnomeui;
#  };
#
#  tig = gitAndTools.tig;
#
#  tilda = callPackage ../applications/misc/tilda {
#    gtk = gtk3;
#  };
#
#  timbreid = callPackage ../applications/audio/pd-plugins/timbreid { };
#
#  timidity = callPackage ../tools/misc/timidity { };
#
#  tint2 = callPackage ../applications/misc/tint2 { };
#
#  tkcvs = callPackage ../applications/version-management/tkcvs { };
#
#  tla = callPackage ../applications/version-management/arch { };
#
#  tlp = callPackage ../tools/misc/tlp {
#    inherit (linuxPackages) x86_energy_perf_policy;
#  };
#
#  todo-txt-cli = callPackage ../applications/office/todo.txt-cli { };
#
#  tomahawk = callPackage ../applications/audio/tomahawk {
#    inherit (pkgs.kde4) kdelibs;
#    taglib = taglib_1_9;
#    enableXMPP      = config.tomahawk.enableXMPP      or true;
#    enableKDE       = config.tomahawk.enableKDE       or false;
#    enableTelepathy = config.tomahawk.enableTelepathy or false;
#    quazip = qt5.quazip.override { qt = qt4; };
#  };
#
#  torchat = callPackage ../applications/networking/instant-messengers/torchat {
#    wrapPython = pythonPackages.wrapPython;
#  };
#
#  tortoisehg = callPackage ../applications/version-management/tortoisehg { };
#
#  toxic = callPackage ../applications/networking/instant-messengers/toxic { };
#
#  transcode = callPackage ../applications/audio/transcode { };
#
#  transmission = callPackage ../applications/networking/p2p/transmission { };
#  transmission_gtk = transmission.override { enableGTK3 = true; };
#
#  transmission_remote_gtk = callPackage ../applications/networking/p2p/transmission-remote-gtk {};
#
#  tree = callPackage ../tools/system/tree {};
#
  trezor-bridge = callPackage ../applications/networking/browsers/mozilla-plugins/trezor { };
#
#  tribler = callPackage ../applications/networking/p2p/tribler { };
#
#  github-release = callPackage ../development/tools/github/github-release { };
#
#  tudu = callPackage ../applications/office/tudu { };
#
#  tuxguitar = callPackage ../applications/editors/music/tuxguitar { };
#
#  twister = callPackage ../applications/networking/p2p/twister { };
#
#  twmn = qt5.callPackage ../applications/misc/twmn { };
#
#  twinkle = callPackage ../applications/networking/instant-messengers/twinkle { };
#
#  umurmur = callPackage ../applications/networking/umurmur { };
#
#  unison = callPackage ../applications/networking/sync/unison {
#    inherit (ocamlPackages) lablgtk;
#    enableX11 = config.unison.enableX11 or true;
#  };
#
#  unpaper = callPackage ../tools/graphics/unpaper { };
#
#  uucp = callPackage ../tools/misc/uucp { };
#
#  uvccapture = callPackage ../applications/video/uvccapture { };
#
#  uwimap = callPackage ../tools/networking/uwimap { };
#
#  uzbl = callPackage ../applications/networking/browsers/uzbl {
#    webkit = webkitgtk2;
#  };
#
#  utox = callPackage ../applications/networking/instant-messengers/utox { };
#
#  vanitygen = callPackage ../applications/misc/vanitygen { };
#
#  vanubi = callPackage ../applications/editors/vanubi { };
#
#  vbindiff = callPackage ../applications/editors/vbindiff { };
#
#  vcprompt = callPackage ../applications/version-management/vcprompt { };
#
#  vdirsyncer = callPackage ../tools/misc/vdirsyncer { };
#
#  vdpauinfo = callPackage ../tools/X11/vdpauinfo { };
#
#  macvim = callPackage ../applications/editors/vim/macvim.nix { stdenv = clangStdenv; };
#
#  vimHugeX = vim_configurable;
#
#  vim_configurable = vimUtils.makeCustomizable (callPackage ../applications/editors/vim/configurable.nix {
#
#    features = "huge"; # one of  tiny, small, normal, big or huge
#    gui = config.vim.gui or "auto";
#
#    # optional features by flags
#    flags = [ "python" "X11" ]; # only flag "X11" by now
#  });
#
#  vimNox = lowPrio (vim_configurable.override { source = "vim-nox"; });
#
#  qpdfview = callPackage ../applications/misc/qpdfview {};
#
#
#  qvim = lowPrio (callPackage ../applications/editors/vim/qvim.nix {
#    features = "huge"; # one of  tiny, small, normal, big or huge
#    lua = pkgs.lua5;
#    flags = [ "python" "X11" ]; # only flag "X11" by now
#  });
#
#  vimpc = callPackage ../applications/audio/vimpc { };
#
#  neovim = callPackage ../applications/editors/neovim {
#    inherit (lua52Packages) lpeg luaMessagePack luabitop;
#  };
#
#  neovim-qt = callPackage ../applications/editors/neovim/qt.nix {
#    qt5 = qt55;
#  };
#
#  neovim-pygui = pythonPackages.neovim_gui;
#
#  virt-viewer = callPackage ../applications/virtualization/virt-viewer {
#    gtkvnc = gtkvnc.override { enableGTK3 = true; };
#    spice_gtk = spice_gtk.override { enableGTK3 = true; };
#  };
#  virtmanager = callPackage ../applications/virtualization/virt-manager {
#    inherit (gnome) gnome_python;
#    gtkvnc = gtkvnc.override { enableGTK3 = true; };
#    spice_gtk = spice_gtk.override { enableGTK3 = true; };
#    system-libvirt = libvirt;
#  };
#
#  virtinst = callPackage ../applications/virtualization/virtinst {};
#
#  virtualglLib = callPackage ../tools/X11/virtualgl/lib.nix {
#    fltk = fltk13;
#  };
#
#  virtualgl = callPackage ../tools/X11/virtualgl {
#    virtualglLib_i686 = if system == "x86_64-linux"
#      then pkgsi686Linux.virtualglLib
#      else null;
#  };
#
#  primusLib = callPackage ../tools/X11/primus/lib.nix {
#    nvidia_x11 = linuxPackages.nvidia_x11.override { libsOnly = true; };
#  };
#
#  primus = callPackage ../tools/X11/primus {
#    primusLib_i686 = if system == "x86_64-linux"
#      then pkgsi686Linux.primusLib
#      else null;
#  };
#
#  bumblebee = callPackage ../tools/X11/bumblebee {
#    nvidia_x11 = linuxPackages.nvidia_x11;
#    nvidia_x11_i686 = if system == "x86_64-linux"
#      then pkgsi686Linux.linuxPackages.nvidia_x11.override { libsOnly = true; }
#      else null;
#    primusLib_i686 = if system == "x86_64-linux"
#      then pkgsi686Linux.primusLib
#      else null;
#  };
#
#  vkeybd = callPackage ../applications/audio/vkeybd {};
#
#  vmpk = callPackage ../applications/audio/vmpk { };
#
#  vnstat = callPackage ../applications/networking/vnstat { };
#
#  VoiceOfFaust = callPackage ../applications/audio/VoiceOfFaust { };
#
  vorbis-tools = callPackage ../applications/audio/vorbis-tools { };
#
#  vue = callPackage ../applications/misc/vue { };
#
#  vym = callPackage ../applications/misc/vym { };
#
#  weechat = callPackage ../applications/networking/irc/weechat { };
#
#  westonLite = callPackage ../applications/window-managers/weston {
#    pango = null;
#    freerdp = null;
#    libunwind = null;
#    vaapi = null;
#    libva = null;
#    libwebp = null;
#    xwayland = null;
#  };
#
#  weston = callPackage ../applications/window-managers/weston {
#    freerdp = freerdpUnstable;
#  };
#
#  winswitch = callPackage ../tools/X11/winswitch { };
#
#  wings = callPackage ../applications/graphics/wings {
#    erlang = erlangR14;
#    esdl = esdl.override { erlang = erlangR14; };
#  };
#
#  wmname = callPackage ../applications/misc/wmname { };
#
#  wmctrl = callPackage ../tools/X11/wmctrl { };
#
#  wordnet = callPackage ../applications/misc/wordnet { };
#
#  workrave = callPackage ../applications/misc/workrave {
#    inherit (gnome) GConf gconfmm;
#    inherit (python27Packages) cheetah;
#  };
#
#  retroArchCores =
#    let
#      cfg = config.retroarch or {};
#      inherit (lib) optional;
#    in with libretro;
#      ([ ]
#      ++ optional (cfg.enable4do or false) _4do
#      ++ optional (cfg.enableBsnesMercury or false) bsnes-mercury
#      ++ optional (cfg.enableDesmume or false) desmume
#      ++ optional (cfg.enableFBA or false) fba
#      ++ optional (cfg.enableFceumm or false) fceumm
#      ++ optional (cfg.enableGambatte or false) gambatte
#      ++ optional (cfg.enableGenesisPlusGX or false) genesis-plus-gx
#      ++ optional (cfg.enableMednafenPCEFast or false) mednafen-pce-fast
#      ++ optional (cfg.enableMupen64Plus or false) mupen64plus
#      ++ optional (cfg.enableNestopia or false) nestopia
#      ++ optional (cfg.enablePicodrive or false) picodrive
#      ++ optional (cfg.enablePrboom or false) prboom
#      ++ optional (cfg.enablePPSSPP or false) ppsspp
#      ++ optional (cfg.enableQuickNES or false) quicknes
#      ++ optional (cfg.enableScummVM or false) scummvm
#      ++ optional (cfg.enableSnes9x or false) snes9x
#      ++ optional (cfg.enableSnes9xNext or false) snes9x-next
#      ++ optional (cfg.enableStella or false) stella
#      ++ optional (cfg.enableVbaNext or false) vba-next
#      ++ optional (cfg.enableVbaM or false) vba-m
#      );
#
#  wrapRetroArch = { retroarch }: callPackage ../misc/emulators/retroarch/wrapper.nix {
#    inherit retroarch;
#    cores = retroArchCores;
#  };
#
#  wrapKodi = { kodi }: callPackage ../applications/video/kodi/wrapper.nix {
#    inherit kodi;
#    plugins = let inherit (lib) optional optionals; in with kodiPlugins;
#      ([]
#      ++ optional (config.kodi.enableAdvancedLauncher or false) advanced-launcher
#      ++ optional (config.kodi.enableGenesis or false) genesis
#      ++ optional (config.kodi.enableSVTPlay or false) svtplay
#      ++ optional (config.kodi.enableSteamLauncher or false) steam-launcher
#      ++ optional (config.kodi.enablePVRHTS or false) pvr-hts
#      ++ optionals (config.kodi.enableSALTS or false) [salts urlresolver t0mm0-common]
#      );
#  };
#
#  wxhexeditor = callPackage ../applications/editors/wxhexeditor { };
#
#  wxcam = callPackage ../applications/video/wxcam {
#    inherit (gnome) libglade;
#    wxGTK = wxGTK28;
#    gtk = gtk2;
#  };
#
#  x11vnc = callPackage ../tools/X11/x11vnc { };
#
#  x2goclient = callPackage ../applications/networking/remote/x2goclient { };
#
#  x2vnc = callPackage ../tools/X11/x2vnc { };
#
#  x42-plugins = callPackage ../applications/audio/x42-plugins { };
#
#  xaos = callPackage ../applications/graphics/xaos {
#    libpng = libpng12;
#  };
#
#  xara = callPackage ../applications/graphics/xara { };
#
#  xawtv = callPackage ../applications/video/xawtv { };
#
#  xbindkeys = callPackage ../tools/X11/xbindkeys { };
#
#  xbindkeys-config = callPackage ../tools/X11/xbindkeys-config/default.nix {
#    gtk = gtk2;
#  };
#
#  kodiPlain = callPackage ../applications/video/kodi { };
#  xbmcPlain = kodiPlain;
#
#  kodiPlugins = recurseIntoAttrs (callPackage ../applications/video/kodi/plugins.nix {
#    kodi = kodiPlain;
#  });
#  xbmcPlugins = kodiPlugins;
#
#  kodi = wrapKodi {
#    kodi = kodiPlain;
#  };
#  xbmc = kodi;
#
#  kodi-retroarch-advanced-launchers =
#    callPackage ../misc/emulators/retroarch/kodi-advanced-launchers.nix {
#      cores = retroArchCores;
#  };
#  xbmc-retroarch-advanced-launchers = kodi-retroarch-advanced-launchers;
#
#  xca = callPackage ../applications/misc/xca { };
#
#  xcalib = callPackage ../tools/X11/xcalib { };
#
#  xcape = callPackage ../tools/X11/xcape { };
#
#  xchainkeys = callPackage ../tools/X11/xchainkeys { };
#
#  xchm = callPackage ../applications/misc/xchm { };
#
#  xdaliclock = callPackage ../tools/misc/xdaliclock {};
#
  xdg-user-dirs = callPackage ../tools/X11/xdg-user-dirs { };
#
#  xdotool = callPackage ../tools/X11/xdotool { };
#
#  xen_4_5_0 = callPackage ../applications/virtualization/xen/4.5.0.nix { };
#  xen_4_5_2 = callPackage ../applications/virtualization/xen/4.5.2.nix { };
#  xen_xenServer = callPackage ../applications/virtualization/xen/4.5.0.nix { xenserverPatched = true; };
#  xen = xen_4_5_2;
#
#  win-spice = callPackage ../applications/virtualization/driver/win-spice { };
#  win-virtio = callPackage ../applications/virtualization/driver/win-virtio { };
#  win-qemu = callPackage ../applications/virtualization/driver/win-qemu { };
#  win-pvdrivers = callPackage ../applications/virtualization/driver/win-pvdrivers { };
#  win-signed-gplpv-drivers = callPackage ../applications/virtualization/driver/win-signed-gplpv-drivers { };
#
#  xfe = callPackage ../applications/misc/xfe {
#    fox = fox_1_6;
#  };
#
#  xfig = callPackage ../applications/graphics/xfig { };
#
#  xneur_0_13 = callPackage ../applications/misc/xneur { };
#
#  xneur_0_8 = callPackage ../applications/misc/xneur/0.8.nix { };
#
#  xneur = xneur_0_13;
#
#  gxneur = callPackage ../applications/misc/gxneur  {
#    inherit (gnome) libglade GConf;
#  };
#
#  xiphos = callPackage ../applications/misc/xiphos {
#    inherit (gnome2) gtkhtml libgtkhtml libglade scrollkeeper;
#    python = python27;
#    webkitgtk = webkitgtk2;
#  };
#
#  xournal = callPackage ../applications/graphics/xournal {
#    inherit (gnome) libgnomeprint libgnomeprintui libgnomecanvas;
#  };
#
#  apvlv = callPackage ../applications/misc/apvlv { };
#
  xpdf = callPackage ../applications/misc/xpdf {
    motif = lesstif;
    base14Fonts = "${ghostscript}/share/ghostscript/fonts";
  };
#
#  xkb_switch = callPackage ../tools/X11/xkb-switch { };
#
#  xkblayout-state = callPackage ../applications/misc/xkblayout-state { };
#
#  xmonad-with-packages = callPackage ../applications/window-managers/xmonad/wrapper.nix {
#    inherit (haskellPackages) ghcWithPackages;
#    packages = self: [];
#  };
#
#  xmpp-client = pkgs.goPackages.xmpp-client.bin // { outputs = [ "bin" ]; };
#
#  libxpdf = callPackage ../applications/misc/xpdf/libxpdf.nix { };
#
#  xpra = callPackage ../tools/X11/xpra { inherit (texFunctions) fontsConf; };
#  libfakeXinerama = callPackage ../tools/X11/xpra/libfakeXinerama.nix { };
#  #TODO: 'pil' is not available for python3, yet
#  xpraGtk3 = callPackage ../tools/X11/xpra/gtk3.nix { inherit (texFunctions) fontsConf; inherit (python3Packages) buildPythonPackage python cython pygobject3 pycairo; };
#
#  xrestop = callPackage ../tools/X11/xrestop { };
#
#  xscreensaver = callPackage ../misc/screensavers/xscreensaver {
#    inherit (gnome) libglade;
#  };
#
#  xss-lock = callPackage ../misc/screensavers/xss-lock { };
#
#  xsynth_dssi = callPackage ../applications/audio/xsynth-dssi { };
#
#  xterm = callPackage ../applications/misc/xterm { };
#
#  finalterm = callPackage ../applications/misc/finalterm { };
#
#  roxterm = callPackage ../applications/misc/roxterm {
#    inherit (pythonPackages) lockfile;
#  };
#
#  xtrace = callPackage ../tools/X11/xtrace { };
#
#  xlaunch = callPackage ../tools/X11/xlaunch { };
#
#  xmacro = callPackage ../tools/X11/xmacro { };
#
#  xmove = callPackage ../applications/misc/xmove { };
#
#  xmp = callPackage ../applications/audio/xmp { };
#
#  xnee = callPackage ../tools/X11/xnee { };
#
#  xvidcap = callPackage ../applications/video/xvidcap {
#    inherit (gnome) scrollkeeper libglade;
#  };
#
#  xzgv = callPackage ../applications/graphics/xzgv { };
#
#  yate = callPackage ../applications/misc/yate { };
#
#  qtbitcointrader = callPackage ../applications/misc/qtbitcointrader {
#    qt = qt4;
#  };
#
#  pahole = callPackage ../development/tools/misc/pahole {};
#
#  yed = callPackage ../applications/graphics/yed {};
#
#  ykpers = callPackage ../applications/misc/ykpers {};
#
#  yoshimi = callPackage ../applications/audio/yoshimi {
#    fltk = fltk13.override { cfg.xftSupport = true; };
#  };
#
#  zam-plugins = callPackage ../applications/audio/zam-plugins { };
#
#  zathuraCollection = recurseIntoAttrs
#    (callPackage ../applications/misc/zathura {
#        callPackage = newScope pkgs.zathuraCollection;
#        useMupdf = config.zathura.useMupdf or true;
#      });
#
#  zathura = zathuraCollection.zathuraWrapper;
#
#  zed = callPackage ../applications/editors/zed { };
#
  zeroc_ice = callPackage ../development/libraries/zeroc-ice { };
#
#  zexy = callPackage ../applications/audio/pd-plugins/zexy  { };
#
#  girara = callPackage ../applications/misc/girara {
#    gtk = gtk3;
#  };
#
#  girara-light = callPackage ../applications/misc/girara {
#    gtk = gtk3;
#    withBuildColors = false;
#    ncurses = null;
#  };
#
#  zgrviewer = callPackage ../applications/graphics/zgrviewer {};
#
#  zim = callPackage ../applications/office/zim {
#    pygtk = pyGtkGlade;
#  };
#
#  zotero = callPackage ../applications/office/zotero {
#    firefox = firefox-unwrapped;
#  };
#
#  zscroll = callPackage ../applications/misc/zscroll {};
#
#  zynaddsubfx = callPackage ../applications/audio/zynaddsubfx { };
#
#  drumkv1 = callPackage ../applications/audio/drumkv1 { };
#
#  samplv1 = callPackage ../applications/audio/samplv1 { };
#
#  synthv1 = callPackage ../applications/audio/synthv1 { };
#
#  ### DESKTOP ENVIRONMENTS
#
#  clearlooks-phenix = callPackage ../misc/themes/gtk3/clearlooks-phenix { };
#
  gnome2 = callPackage ../desktops/gnome-2 {
    callPackage = pkgs.newScope pkgs.gnome2;
    self = pkgs.gnome2;
  }  // pkgs.gtkLibs // {
    # Backwards compatibility;
    inherit (pkgs) libwnck gtk_doc gnome_doc_utils;
  };

  gnome = recurseIntoAttrs pkgs.gnome2;
#
#  hsetroot = callPackage ../tools/X11/hsetroot { };
#
#  kakasi = callPackage ../tools/text/kakasi { };
#
  kde4 = recurseIntoAttrs pkgs.kde414;

  kde414 =
    pkgs.kdePackagesFor
      {
        libcanberra = pkgs.libcanberra_kde;
        boost = pkgs.boost155;
        kdelibs = pkgs.kde5.kdelibs;
        subversionClient = pkgs.subversion18 { };
      }
      ../desktops/kde-4.14;


  kdePackagesFor = extra: dir:
    let
      # list of extra packages not included in KDE
      # the real work in this function is done below this list
      extraPackages = callPackage:
        rec {
#          amarok = callPackage ../applications/audio/amarok { };
#
#          bangarang = callPackage ../applications/video/bangarang { };
#
#          basket = callPackage ../applications/office/basket { };
#
#          bluedevil = callPackage ../tools/bluetooth/bluedevil { };
#
#          calligra = callPackage ../applications/office/calligra {
#            vc = vc_0_7;
#          };
#
#          choqok = callPackage ../applications/networking/instant-messengers/choqok { };
#
#          colord-kde = callPackage ../tools/misc/colord-kde { };
#
#          digikam = callPackage ../applications/graphics/digikam { };
#
#          eventlist = callPackage ../applications/office/eventlist {};
#
#          k3b = callPackage ../applications/misc/k3b {
#            cdrtools = cdrkit;
#          };
#
#          kadu = callPackage ../applications/networking/instant-messengers/kadu { };
#
#          kbibtex = callPackage ../applications/office/kbibtex { };
#
#          kde_gtk_config = callPackage ../tools/misc/kde-gtk-config { };
#
#          kde_wacomtablet = callPackage ../applications/misc/kde-wacomtablet { };
#
#          kdeconnect = callPackage ../applications/misc/kdeconnect { };
#
#          kdenlive = callPackage ../applications/video/kdenlive { mlt = mlt-qt4; };
#
#          kdesvn = callPackage ../applications/version-management/kdesvn { };
#
#          kdevelop = callPackage ../applications/editors/kdevelop { };
#
#          kdevplatform = callPackage ../development/libraries/kdevplatform {
#            boost = boost155;
#          };
#
#          kdiff3 = callPackage ../tools/text/kdiff3 { };
#
#          kgraphviewer = callPackage ../applications/graphics/kgraphviewer { };
#
#          kile = callPackage ../applications/editors/kile { };
#
#          kmplayer = callPackage ../applications/video/kmplayer { };
#
#          kmymoney = callPackage ../applications/office/kmymoney { };
#
#          kipi_plugins = callPackage ../applications/graphics/kipi-plugins { };
#
#          konversation = callPackage ../applications/networking/irc/konversation { };
#
#          kvirc = callPackage ../applications/networking/irc/kvirc { };
#
#          krename = callPackage ../applications/misc/krename {
#            taglib = taglib_1_9;
#          };
#
#          krusader = callPackage ../applications/misc/krusader { };
#
#          ksshaskpass = callPackage ../tools/security/ksshaskpass {};
#
#          ktorrent = callPackage ../applications/networking/p2p/ktorrent { };
#
#          kuickshow = callPackage ../applications/graphics/kuickshow { };
#
#          libalkimia = callPackage ../development/libraries/libalkimia { };
#
#          libktorrent = callPackage ../development/libraries/libktorrent {
#            boost = boost155;
#          };
#
#          libkvkontakte = callPackage ../development/libraries/libkvkontakte { };
#
#          liblikeback = callPackage ../development/libraries/liblikeback { };
#
#          libmm-qt = callPackage ../development/libraries/libmm-qt { };
#
#          libnm-qt = callPackage ../development/libraries/libnm-qt { };
#
#          massif-visualizer = callPackage ../development/tools/analysis/massif-visualizer { };
#
#          partitionManager = callPackage ../tools/misc/partition-manager { };
#
#          plasma-nm = callPackage ../tools/networking/plasma-nm { };
#
#          polkit_kde_agent = callPackage ../tools/security/polkit-kde-agent { };
#
#          psi = callPackage ../applications/networking/instant-messengers/psi { };
#
#          qtcurve = callPackage ../misc/themes/qtcurve { };
#
#          rekonq-unwrapped = callPackage ../applications/networking/browsers/rekonq { };
#          rekonq = wrapFirefox rekonq-unwrapped { };
#
#          kwebkitpart = callPackage ../applications/networking/browsers/kwebkitpart { };
#
#          rsibreak = callPackage ../applications/misc/rsibreak { };
#
#          semnotes = callPackage ../applications/misc/semnotes { };
#
#          skrooge = callPackage ../applications/office/skrooge { };
#
#          telepathy = callPackage ../applications/networking/instant-messengers/telepathy/kde {};
#
#          yakuake = callPackage ../applications/misc/yakuake { };
#
#          zanshin = callPackage ../applications/office/zanshin { };
#
#          kwooty = callPackage ../applications/networking/newsreaders/kwooty { };
        };

      callPackageOrig = pkgs.newScope extra;

      makePackages = extra:
        let
          callPackage = newScope (extra // self);
          kde4 = callPackageOrig dir { inherit callPackage callPackageOrig; };
          self =
            kde4
            // extraPackages callPackage
            // {
              inherit kde4;
              wrapper = callPackage ../build-support/kdewrapper {};
              recurseForRelease = true;
            };
        in self;

    in lib.makeOverridable makePackages extra;

#  redshift = callPackage ../applications/misc/redshift {
#    inherit (python3Packages) python pygobject3 pyxdg;
#  };
#
#  orion = callPackage ../misc/themes/orion {};
#
#  albatross = callPackage ../misc/themes/albatross { };
#
#  oxygen-gtk2 = callPackage ../misc/themes/gtk2/oxygen-gtk { };
#
#  oxygen-gtk3 = callPackage ../misc/themes/gtk3/oxygen-gtk3 { };
#
#  oxygen_gtk = oxygen-gtk2; # backwards compatibility
#
#  gtk_engines = callPackage ../misc/themes/gtk2/gtk-engines { };
#
#  gtk-engine-murrine = callPackage ../misc/themes/gtk2/gtk-engine-murrine { };
#
#  mate-icon-theme = callPackage ../misc/themes/mate-icon-theme { };
#
#  mate-themes = callPackage ../misc/themes/mate-themes { };
#
#  numix-gtk-theme = callPackage ../misc/themes/gtk3/numix-gtk-theme { };
#
  kde5PackagesFun = self: with self; {
#
#    calamares = callPackage ../tools/misc/calamares rec {
#      python = python3;
#      boost = pkgs.boost.override { python=python3; };
#      libyamlcpp = callPackage ../development/libraries/libyaml-cpp { makePIC=true; boost=boost; };
#    };
#
#    dfilemanager = callPackage ../applications/misc/dfilemanager { };
#
#    fcitx-qt5 = callPackage ../tools/inputmethods/fcitx/fcitx-qt5.nix { };
#
#    k9copy = callPackage ../applications/video/k9copy {};
#
#    konversation = callPackage ../applications/networking/irc/konversation/1.6.nix {
#    };
#
    quassel = callPackage ../all-pkgs/quassel {
      monolithic = true;
      daemon = false;
      client = false;
      tag = "-kf5";
    };

    quasselClient = quassel.override {
      monolithic = false;
      client = true;
      tag = "-client-kf5";
    };

    quassel_qt5 = quassel.override {
      tag = "-qt5";
    };

    quasselClient_qt5 = quasselClient.override {
      tag = "-client-qt5";
    };

    quasselDaemon = quassel.override {
      monolithic = false;
      daemon = true;
      tag = "-daemon-qt5";
    };

    sddm = callPackage ../applications/display-managers/sddm {
      themes = [];  # extra themes, etc.
    };

  };

  kde5 =
    let
      frameworks = import ../development/libraries/kde-frameworks-5.18 { inherit pkgs; };
      plasma = import ../desktops/plasma-5.5 { inherit pkgs; };
      apps = import ../applications/kde-apps-15.12 { inherit pkgs; };
      named = self: { plasma = plasma self; frameworks = frameworks self; apps = apps self; };
      merged = self:
        named self // frameworks self // plasma self // apps self // kde5PackagesFun self;
    in
      recurseIntoAttrs (lib.makeScope qt55.newScope merged);
#
#  kde5_latest =
#    let
#      frameworks = import ../development/libraries/kde-frameworks-5.19 { inherit pkgs; };
#      plasma = import ../desktops/plasma-5.5 { inherit pkgs; };
#      apps = import ../applications/kde-apps-15.12 { inherit pkgs; };
#      named = self: { plasma = plasma self; frameworks = frameworks self; apps = apps self; };
#      merged = self:
#        named self // frameworks self // plasma self // apps self // kde5PackagesFun self;
#    in
#      recurseIntoAttrs (lib.makeScope qt55.newScope merged);
#
#  theme-vertex = callPackage ../misc/themes/vertex { };
#
#  xfce = xfce4-12;
#  xfce4-12 = recurseIntoAttrs (callPackage ../desktops/xfce { });
#
#  xrandr-invert-colors = callPackage ../applications/misc/xrandr-invert-colors { };
#
#  ### SCIENCE
#
#  ### SCIENCE / ELECTRONICS
#
#  alliance = callPackage ../applications/science/electronics/alliance {
#    motif = lesstif;
#  };
#
#  archimedes = callPackage ../applications/science/electronics/archimedes { };
#
#  eagle = callPackage ../applications/science/electronics/eagle { };
#
#  caneda = callPackage ../applications/science/electronics/caneda { };
#
#  geda = callPackage ../applications/science/electronics/geda { };
#
#  gerbv = callPackage ../applications/science/electronics/gerbv { };
#
#  gtkwave = callPackage ../applications/science/electronics/gtkwave { };
#
#  kicad = callPackage ../applications/science/electronics/kicad {
#    wxGTK = wxGTK29;
#  };
#
#  ngspice = callPackage ../applications/science/electronics/ngspice { };
#
#  pcb = callPackage ../applications/science/electronics/pcb { };
#
#  qucs = callPackage ../applications/science/electronics/qucs { };
#
#  xoscope = callPackage ../applications/science/electronics/xoscope { };
#
#  ### MISC
#
#  antimicro = qt5.callPackage ../tools/misc/antimicro { };
#
#  atari800 = callPackage ../misc/emulators/atari800 { };
#
#  ataripp = callPackage ../misc/emulators/atari++ { };
#
#  auctex = callPackage ../tools/typesetting/tex/auctex { };
#
#  beep = callPackage ../misc/beep { };
#
  cups = callPackage ../misc/cups { };

  cups_filters = callPackage ../misc/cups/filters.nix { };
#
#  cups-pk-helper = callPackage ../misc/cups/cups-pk-helper.nix { };
#
#  gutenprint = callPackage ../misc/drivers/gutenprint { };
#
#  gutenprintBin = callPackage ../misc/drivers/gutenprint/bin.nix { };
#
#  cups-bjnp = callPackage ../misc/cups/drivers/cups-bjnp { };
#
#  darcnes = callPackage ../misc/emulators/darcnes { };
#
#  darling-dmg = callPackage ../tools/filesystems/darling-dmg { };
#
#  desmume = callPackage ../misc/emulators/desmume { inherit (pkgs.gnome) gtkglext libglade; };
#
#  dbacl = callPackage ../tools/misc/dbacl { };
#
  dblatex = callPackage ../tools/typesetting/tex/dblatex {
    enableAllFeatures = false;
  };
#
#  dblatexFull = appendToName "full" (dblatex.override {
#    enableAllFeatures = true;
#  });
#
#  dosbox = callPackage ../misc/emulators/dosbox { };
#
#  dpkg = callPackage ../tools/package-management/dpkg { };
#
#  ekiga = newScope pkgs.gnome ../applications/networking/instant-messengers/ekiga { };
#
#  emulationstation = callPackage ../misc/emulators/emulationstation { };
#
#  electricsheep = callPackage ../misc/screensavers/electricsheep { };
#
#  fakenes = callPackage ../misc/emulators/fakenes { };
#
#  faust = faust2;
#
#  faust1 = callPackage ../applications/audio/faust/faust1.nix { };
#
#  faust2 = callPackage ../applications/audio/faust/faust2.nix { };
#
#  faust2alqt = callPackage ../applications/audio/faust/faust2alqt.nix { };
#
#  faust2alsa = callPackage ../applications/audio/faust/faust2alsa.nix { };
#
#  faust2csound = callPackage ../applications/audio/faust/faust2csound.nix { };
#
#  faust2firefox = callPackage ../applications/audio/faust/faust2firefox.nix { };
#
#  faust2jack = callPackage ../applications/audio/faust/faust2jack.nix { };
#
#  faust2jaqt = callPackage ../applications/audio/faust/faust2jaqt.nix { };
#
#  faust2lv2 = callPackage ../applications/audio/faust/faust2lv2.nix { };
#
#  fceux = callPackage ../misc/emulators/fceux { };
#
#  foldingathome = callPackage ../misc/foldingathome { };
#
#  foo2zjs = callPackage ../misc/drivers/foo2zjs {};
#
#  foomatic_filters = callPackage ../misc/drivers/foomatic-filters {};
#
#  freestyle = callPackage ../misc/freestyle { };
#
#  gajim = callPackage ../applications/networking/instant-messengers/gajim { };
#
#  gale = callPackage ../applications/networking/instant-messengers/gale { };
#
#  gammu = callPackage ../applications/misc/gammu { };
#
#  gensgs = callPackage_i686 ../misc/emulators/gens-gs { };
#
  ghostscript = callPackage ../misc/ghostscript {
    x11Support = false;
    cupsSupport = config.ghostscript.cups or true;
  };
#
  ghostscriptX = appendToName "with-X" (ghostscript.override {
    x11Support = true;
  });
#
#  gnuk = callPackage ../misc/gnuk { };
#  gnuk-unstable = callPackage ../misc/gnuk/unstable.nix { };
#  gnuk-git = callPackage ../misc/gnuk/git.nix { };
#
#  guix = callPackage ../tools/package-management/guix {
#    libgcrypt = libgcrypt_1_5;
#  };
#
#  gxemul = callPackage ../misc/emulators/gxemul { };
#
#  hatari = callPackage ../misc/emulators/hatari { };
#
#  helm = callPackage ../applications/audio/helm { };
#
#  hplip = callPackage ../misc/drivers/hplip { };
#
#  hplipWithPlugin = hplip.override { withPlugin = true; };
#
#  hplip_3_15_9 = callPackage ../misc/drivers/hplip/3.15.9.nix { };
#
#  hplipWithPlugin_3_15_9 = hplip_3_15_9.override { withPlugin = true; };
#
#  # using the new configuration style proposal which is unstable
#  jack1 = callPackage ../misc/jackaudio/jack1.nix { };
#
  jack2_full = callPackage ../misc/jackaudio { };

  jack2_lib = callPackageAlias "jack2_full" {
    prefix = "lib";
  };
#  libjack2-git = callPackage ../misc/jackaudio/git.nix { };
#
#  keynav = callPackage ../tools/X11/keynav { };
#
#  lilypond = callPackage ../misc/lilypond { guile = guile_1_8; };
#
#  mailcore2 = callPackage ../development/libraries/mailcore2 { };
#
#  martyr = callPackage ../development/libraries/martyr { };
#
#  mess = callPackage ../misc/emulators/mess {
#    inherit (pkgs.gnome) GConf;
#  };
#
#  mongoc = callPackage ../development/libraries/mongoc { };
#
#  mupen64plus = callPackage ../misc/emulators/mupen64plus { };
#
  inherit (callPackages ../tools/package-management/nix {
      storeDir = config.nix.storeDir or "/nix/store";
      stateDir = config.nix.stateDir or "/nix/var";
      })
    nix
    nixStable
    nixUnstable;
#
#  nixops = callPackage ../tools/package-management/nixops { };
#
#  nixopsUnstable = nixops;# callPackage ../tools/package-management/nixops/unstable.nix { };
#
#  nixui = callPackage ../tools/package-management/nixui { node_webkit = nwjs_0_12; };
#
#  inherit (callPackages ../tools/package-management/nix-prefetch-scripts { })
#    nix-prefetch-bzr
#    nix-prefetch-cvs
#    nix-prefetch-git
#    nix-prefetch-hg
#    nix-prefetch-svn
#    nix-prefetch-zip
#    nix-prefetch-scripts;
#
#  nix-template-rpm = callPackage ../build-support/templaterpm { inherit (pythonPackages) python toposort; };
#
#  nix-repl = callPackage ../tools/package-management/nix-repl { };
#
#  nix-serve = callPackage ../tools/package-management/nix-serve { };
#
  nixos-artwork = callPackage ../data/misc/nixos-artwork { };
#
#  nut = callPackage ../applications/misc/nut { };
#
#  solfege = callPackage ../misc/solfege {
#      pysqlite = pkgs.pythonPackages.sqlite3;
#  };
#
#  disnix = callPackage ../tools/package-management/disnix { };
#
#  dysnomia = callPackage ../tools/package-management/disnix/dysnomia {
#    enableApacheWebApplication = config.disnix.enableApacheWebApplication or false;
#    enableAxis2WebService = config.disnix.enableAxis2WebService or false;
#    enableEjabberdDump = config.disnix.enableEjabberdDump or false;
#    enableMySQLDatabase = config.disnix.enableMySQLDatabase or false;
#    enablePostgreSQLDatabase = config.disnix.enablePostgreSQLDatabase or false;
#    enableSubversionRepository = config.disnix.enableSubversionRepository or false;
#    enableTomcatWebApplication = config.disnix.enableTomcatWebApplication or false;
#  };
#
#  disnixos = callPackage ../tools/package-management/disnix/disnixos { };
#
#  DisnixWebService = callPackage ../tools/package-management/disnix/DisnixWebService { };
#
#  lkproof = callPackage ../tools/typesetting/tex/lkproof { };
#
#  mysqlWorkbench = newScope gnome ../applications/misc/mysql-workbench {
#    libctemplate = libctemplate_2_2;
#    inherit (pythonPackages) pexpect paramiko;
#  };
#
#  robomongo = qt5.callPackage ../applications/misc/robomongo { };
#
#  rucksack = callPackage ../development/tools/rucksack { };
#
#  opkg = callPackage ../tools/package-management/opkg { };
#
#  opkg-utils = callPackage ../tools/package-management/opkg-utils { };
#
#  pgadmin = callPackage ../applications/misc/pgadmin { };
#
#  pgf = pgf2;
#
#  # Keep the old PGF since some documents don't render properly with
#  # the new one.
#  pgf1 = callPackage ../tools/typesetting/tex/pgf/1.x.nix { };
#
#  pgf2 = callPackage ../tools/typesetting/tex/pgf/2.x.nix { };
#
#  pgf3 = callPackage ../tools/typesetting/tex/pgf/3.x.nix { };
#
#  pgfplots = callPackage ../tools/typesetting/tex/pgfplots { };
#
#  phabricator = callPackage ../misc/phabricator { };
#
#  physlock = callPackage ../misc/screensavers/physlock { };
#
#  pjsip = callPackage ../applications/networking/pjsip { };
#
#  PPSSPP = callPackage ../misc/emulators/ppsspp { SDL = SDL2; };
#
#  pt = callPackage ../applications/misc/pt { };
#
#  uae = callPackage ../misc/emulators/uae { };
#
#  fsuae = callPackage ../misc/emulators/fs-uae { };
#
#  putty = callPackage ../applications/networking/remote/putty { };
#
#  retroarchBare = callPackage ../misc/emulators/retroarch { };
#
#  retroarch = wrapRetroArch { retroarch = retroarchBare; };
#
#  libretro = recurseIntoAttrs (callPackage ../misc/emulators/retroarch/cores.nix {
#    retroarch = retroarchBare;
#  });
#
#  rss-glx = callPackage ../misc/screensavers/rss-glx { };
#
#  runit = callPackage ../tools/system/runit { };
#
#  refind = callPackage ../tools/bootloaders/refind { };
#
#  spectrojack = callPackage ../applications/audio/spectrojack { };
#
#  xlockmore = callPackage ../misc/screensavers/xlockmore { };
#
#  xtrlock-pam = callPackage ../misc/screensavers/xtrlock-pam { };
#
#  sails = callPackage ../misc/sails { };
#
#  canon-cups-ufr2 = callPackage ../misc/cups/drivers/canon { };
#
#  mfcj470dw = callPackage_i686 ../misc/cups/drivers/mfcj470dw { };
#
#  samsung-unified-linux-driver_1_00_37 = callPackage ../misc/cups/drivers/samsung { };
#  samsung-unified-linux-driver = callPackage ../misc/cups/drivers/samsung/4.00.39 { };
#
#  sane-backends = callPackage ../applications/graphics/sane/backends {
#    gt68xxFirmware = config.sane.gt68xxFirmware or null;
#    snapscanFirmware = config.sane.snapscanFirmware or null;
#  };
#
#  sane-backends-git = callPackage ../applications/graphics/sane/backends/git.nix {
#    gt68xxFirmware = config.sane.gt68xxFirmware or null;
#    snapscanFirmware = config.sane.snapscanFirmware or null;
#  };
#
#  mkSaneConfig = callPackage ../applications/graphics/sane/config.nix { };
#
#  sane-frontends = callPackage ../applications/graphics/sane/frontends.nix { };
#
#  sct = callPackage ../tools/X11/sct {};
#
#  seafile-shared = callPackage ../misc/seafile-shared { };
#
  slock = callPackage ../misc/screensavers/slock { };
#
#  snapraid = callPackage ../tools/filesystems/snapraid { };
#
#  soundOfSorting = callPackage ../misc/sound-of-sorting { };
#
#  sourceAndTags = callPackage ../misc/source-and-tags {
#    hasktags = haskellPackages.hasktags;
#  };
#
#  splix = callPackage ../misc/cups/drivers/splix { };
#
#  streamripper = callPackage ../applications/audio/streamripper { };
#
#  sqsh = callPackage ../development/tools/sqsh { };
#
#  tetex = callPackage ../tools/typesetting/tex/tetex { libpng = libpng12; };
#
#  tewi-font = callPackage ../data/fonts/tewi  {};
#
#  tex4ht = callPackage ../tools/typesetting/tex/tex4ht { };
#
#  texFunctions = callPackage ../tools/typesetting/tex/nix pkgs;
#
#  # All the new TeX Live is inside. See description in default.nix.
  texlive = recurseIntoAttrs
    (callPackage ../tools/typesetting/tex/texlive-new { });

  texLive = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive) {
    ghostscript = ghostscriptX;
  };

  texLiveFull = lib.setName "texlive-full" (texLiveAggregationFun {
    paths = [ texLive texLiveExtra lmodern texLiveCMSuper texLiveLatexXColor
              texLivePGF texLiveBeamer texLiveModerncv tipa tex4ht texinfo
              texLiveModerntimeline texLiveContext ];
  });

  /* Look in configurations/misc/raskin.nix for usage example (around revisions
  where TeXLive was added)

  (texLiveAggregationFun {
    paths = [texLive texLiveExtra texLiveCMSuper
      texLiveBeamer
    ];
  })

#  You need to use texLiveAggregationFun to regenerate, say, ls-R (TeX-related file list)
#  Just installing a few packages doesn't work.
#  */
  texLiveAggregationFun = params:
    builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/aggregate.nix) params;

  texLiveContext = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/context.nix) {};

  texLiveExtra = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/extra.nix) {};

  texLiveCMSuper = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/cm-super.nix) {};

  texLiveLatexXColor = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/xcolor.nix) {};

  texLivePGF = pgf3;

  texLiveBeamer = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/beamer.nix) {};

  texLiveModerncv = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/moderncv.nix) {};

  texLiveModerntimeline = builderDefsPackage (callPackage ../tools/typesetting/tex/texlive/moderntimeline.nix) {};
#
#  ib-tws = callPackage ../applications/office/ib/tws { jdk=oraclejdk8; };
#
#  ib-controller = callPackage ../applications/office/ib/controller { jdk=oraclejdk8; };
#
#  thermald = callPackage ../tools/system/thermald { };
#
#  thinkfan = callPackage ../tools/system/thinkfan { };
#
#  tup = callPackage ../development/tools/build-managers/tup { };
#
#  tvheadend = callPackage ../servers/tvheadend { };
#
#  ums = callPackage ../servers/ums { };
#
#  urbit = callPackage ../misc/urbit { };
#
#  utf8proc = callPackage ../development/libraries/utf8proc { };
#
  vault = pkgs.goPackages.vault.bin // { outputs = [ "bin" ]; };
#
#  vbam = callPackage ../misc/emulators/vbam {};
#
#  vice = callPackage ../misc/emulators/vice {
#    libX11 = xorg.libX11;
#    giflib = giflib_4_1;
#  };
#
#  viewnior = callPackage ../applications/graphics/viewnior { };
#
#  vimUtils = callPackage ../misc/vim-plugins/vim-utils.nix { };
#
#  vimPlugins = recurseIntoAttrs (callPackage ../misc/vim-plugins { });
#
#  vimprobable2-unwrapped = callPackage ../applications/networking/browsers/vimprobable2 {
#    webkit = webkitgtk2;
#  };
#  vimprobable2 = wrapFirefox vimprobable2-unwrapped { };
#
#  inherit (kde4) rekonq;
#
#  vimb-unwrapped = callPackage ../applications/networking/browsers/vimb {
#    webkit = webkitgtk2;
#  };
#  vimb = wrapFirefox vimb-unwrapped { };
#
#  vips = callPackage ../tools/graphics/vips { };
#  nip2 = callPackage ../tools/graphics/nip2 { };
#
#  wavegain = callPackage ../applications/audio/wavegain { };
#
#  wcalc = callPackage ../applications/misc/wcalc { };
#
#  webfs = callPackage ../servers/http/webfs { };
#
  wine = callPackage ../misc/emulators/wine {
    wineRelease = config.wine.release or "stable";
    wineBuild = config.wine.build or "wine32";
    pulseaudioSupport = config.pulseaudio or true;
  };
  wineStable = wine.override { wineRelease = "stable"; };
  wineUnstable = lowPrio (wine.override { wineRelease = "unstable"; });
  wineStaging = lowPrio (wine.override { wineRelease = "staging"; });

  winetricks = callPackage ../misc/emulators/wine/winetricks.nix {
    inherit (gnome2) zenity;
  };
#
#  wmutils-core = callPackage ../tools/X11/wmutils-core { };
#
#  wxmupen64plus = callPackage ../misc/emulators/wxmupen64plus { };
#
#  x2x = callPackage ../tools/X11/x2x { };
#
#  xboxdrv = callPackage ../misc/drivers/xboxdrv { };
#
#  xcftools = callPackage ../tools/graphics/xcftools { };
#
#  xhyve = callPackage ../applications/virtualization/xhyve { };
#
#  xinput_calibrator = callPackage ../tools/X11/xinput_calibrator {};
#
#  xosd = callPackage ../misc/xosd { };
#
#  xsane = callPackage ../applications/graphics/sane/xsane.nix {
#    libpng = libpng12;
#  };
#
#  xwiimote = callPackage ../misc/drivers/xwiimote {
#    bluez = pkgs.bluez5.override {
#      enableWiimote = true;
#    };
#  };
#
#  yabause = callPackage ../misc/emulators/yabause {
#    qt = qt4;
#  };
#
#  yafc = callPackage ../applications/networking/yafc { };
#
#  yandex-disk = callPackage ../tools/filesystems/yandex-disk { };
#
#  yara = callPackage ../tools/security/yara { };
#
#  zap = callPackage ../tools/networking/zap { };
#
#  zdfmediathk = callPackage ../applications/video/zdfmediathk { };
#
#  zopfli = callPackage ../tools/compression/zopfli { };
#
  myEnvFun = callPackage ../misc/my-env { };
#
#  # patoline requires a rather large ocaml compilation environment.
#  # this is why it is build as an environment and not just a normal package.
#  # remark : the emacs mode is also installed, but you have to adjust your load-path.
#  PatolineEnv = pack: myEnvFun {
#      name = "patoline";
#      buildInputs = [ stdenv ncurses mesa freeglut libzip gcc
#                                   pack.ocaml pack.findlib pack.camomile
#                                   pack.dypgen pack.ocaml_sqlite3 pack.camlzip
#                                   pack.lablgtk pack.camlimages pack.ocaml_cairo
#                                   pack.lablgl pack.ocamlnet pack.cryptokit
#                                   pack.ocaml_pcre pack.patoline
#                                   ];
#    # this is to circumvent the bug with libgcc_s.so.1 which is
#    # not found when using thread
#    extraCmds = ''
#       LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:${gcc.cc}/lib
#       export LD_LIBRARY_PATH
#    '';
#  };
#
#  patoline = PatolineEnv ocamlPackages_4_00_1;
#
#  znc = callPackage ../applications/networking/znc { };
#
#  znc_14 = callPackage ../applications/networking/znc/1.4.nix { };
#
#  zncModules = recurseIntoAttrs (
#    callPackage ../applications/networking/znc/modules.nix { }
#  );
#
#  zsnes = callPackage_i686 ../misc/emulators/zsnes { };
#
#  snes9x-gtk = callPackage ../misc/emulators/snes9x-gtk { };
#
#  higan = callPackage ../misc/emulators/higan {
#    inherit (gnome) gtksourceview;
#    profile = config.higan.profile or "balanced";
#  };
#
#  misc = callPackage ../misc/misc.nix { };
#
#  bullet = callPackage ../development/libraries/bullet {};
#
#  httrack = callPackage ../tools/backup/httrack { };
#
}; # self_ =

in self; in pkgs
