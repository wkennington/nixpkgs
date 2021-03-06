{ stdenv, runCommand, git, bison, flex, bc, elfutils, gmp, mpfr, libmpc, perl, kmod, openssl, writeTextFile, ubootChooser }:

let
  readConfig = configfile: import (runCommand "config.nix" {} ''
    echo "{" > "$out"
    while IFS='=' read key val; do
      [ "x''${key#CONFIG_}" != "x$key" ] || continue
      no_firstquote="''${val#\"}";
      echo '  "'"$key"'" = "'"''${no_firstquote%\"}"'";' >> "$out"
    done < "${configfile}"
    echo "}" >> $out
  '').outPath;
in {
  # The kernel version
  version,
  # The version of the kernel module directory
  modDirVersion ? version,
  # The kernel source (tarball, git checkout, etc.)
  src,
  needsGitPatch,
  patch,
  # Any patches
  kernelPatches ? [],
  # Patches for native compiling only
  nativeKernelPatches ? [],
  # Patches for cross compiling only
  crossKernelPatches ? [],
  # The native kernel .config file
  configfile,
  # The cross kernel .config file
  crossConfigfile ? configfile,
  # Manually specified nixexpr representing the config
  # If unspecified, this will be autodetected from the .config
  config ? stdenv.lib.optionalAttrs allowImportFromDerivation (readConfig configfile),
  # Cross-compiling config
  crossConfig ? if allowImportFromDerivation then (readConfig crossConfigfile) else config,
  # Whether to utilize the controversial import-from-derivation feature to parse the config
  allowImportFromDerivation ? false
}:

let
  inherit (stdenv.lib)
    hasAttr getAttr optional optionalString optionalAttrs maintainers platforms;

  common = import ./common.nix { inherit stdenv; };

  installkernel = writeTextFile { name = "installkernel"; executable=true; text = ''
    #!${stdenv.shell} -e
    mkdir -p $4
    cp -av $2 $4
    cp -av $3 $4
  ''; };

  commonMakeFlags = [
    "O=$(buildRoot)"
  ];

  drvAttrs = config_: kernelPatches: configfile:
    let
      config = let attrName = attr: "CONFIG_" + attr; in {
        isSet = attr: hasAttr (attrName attr) config;

        getValue = attr: if config.isSet attr then getAttr (attrName attr) config else null;

        isYes = attr: (config.getValue attr) == "y";

        isNo = attr: (config.getValue attr) == "n";

        isModule = attr: (config.getValue attr) == "m";

        isEnabled = attr: (config.isModule attr) || (config.isYes attr);

        isDisabled = attr: (!(config.isSet attr)) || (config.isNo attr);
      } // config_;

      isModular = config.isYes "MODULES";

      installsFirmware = (config.isEnabled "FW_LOADER") &&
        (isModular || (config.isDisabled "FIRMWARE_IN_KERNEL"));
    in (optionalAttrs isModular { outputs = [ "out" "dev" ]; }) // {
      passthru = {
        inherit version modDirVersion config kernelPatches configfile;
      };

      inherit src;

      # We don't want these compiler security features / optimizations
      optFlags = false;
      pie = false;
      fpic = false;
      noStrictOverflow = false;
      fortifySource = false;
      stackProtector = false;
      optimize = false;

      preUnpack = ''
        mkdir build
        export buildRoot="$(pwd)/build"
      '';

      prePatch = optionalString (needsGitPatch && patch != null) ''
        echo "Applying delta ${patch}"
        case "${patch}" in
          *.xz)
            cmd='xz -d -'
            ;;
          *)
            cmd='cat -'
        esac
        cat '${patch}' | eval "$cmd" | git apply --unsafe-paths
      '';

      patches = stdenv.lib.optionals (!needsGitPatch && patch != null) [ patch ]
        ++ map (p: p.patch) kernelPatches;

      postPatch = ''
        for mf in $(find -name Makefile -o -name Makefile.include -o -name install.sh); do
            echo "stripping FHS paths in \`$mf'..."
            sed -i "$mf" -e 's|/usr/bin/||g ; s|/bin/||g ; s|/sbin/||g'
        done
        sed -i Makefile -e 's|= depmod|= ${kmod}/sbin/depmod|'

        # We want to make sure the hostname is deterministic
        mkdir -p $TMPDIR/bin
        echo '#! ${stdenv.shell}' > $TMPDIR/bin/hostname
        echo 'echo "localhost"' >> $TMPDIR/bin/hostname
        chmod +x $TMPDIR/bin/hostname
        export PATH="$TMPDIR/bin:$PATH"
      '' + stdenv.lib.optionalString (stdenv.lib.versionOlder version "4.18") ''
        # All current kernels ship with a broken classmap.h
        cp ${./classmap.h} security/selinux/include/classmap.h
      '';

      configurePhase = ''
        runHook preConfigure
        ln -sv ${configfile} $buildRoot/.config
        make $makeFlags "''${makeFlagsArray[@]}" oldconfig
        runHook postConfigure

        # Note: we can get rid of this once http://permalink.gmane.org/gmane.linux.kbuild.devel/13800 is merged.
        buildFlagsArray+=("KBUILD_BUILD_TIMESTAMP=$(date -u -d @$SOURCE_DATE_EPOCH)")
      '';

      buildFlags = [
        "KBUILD_BUILD_VERSION=1-Triton"
        "bzImage"
      ] ++ optional isModular "modules";

      installFlags = [
        "INSTALLKERNEL=${installkernel}"
        "INSTALL_PATH=$(out)"
      ] ++ (optional isModular "INSTALL_MOD_PATH=$(out)")
      ++ optional installsFirmware "INSTALL_FW_PATH=$(out)/lib/firmware";

      # Some image types need special install targets (e.g. uImage is installed with make uinstall)
      installTargets = [
        "install"
      ];

      postInstall = (optionalString installsFirmware ''
        mkdir -p $out/lib/firmware
      '') + (if isModular then ''
        if [ -z "$dontStrip" ]; then
          installFlagsArray+=("INSTALL_MOD_STRIP=1")
        fi
        make modules_install $makeFlags "''${makeFlagsArray[@]}" \
          $installFlags "''${installFlagsArray[@]}"
        unlink $out/lib/modules/${modDirVersion}/build
        unlink $out/lib/modules/${modDirVersion}/source

        mkdir -p $dev/lib/modules/${modDirVersion}
        cd ..
        mv $srcRoot $dev/lib/modules/${modDirVersion}/source
        cd $dev/lib/modules/${modDirVersion}/source

        mv $buildRoot/.config $buildRoot/Module.symvers $TMPDIR
        rm -fR $buildRoot
        mkdir $buildRoot
        mv $TMPDIR/.config $TMPDIR/Module.symvers $buildRoot
        make modules_prepare $makeFlags "''${makeFlagsArray[@]}"
        mv $buildRoot $dev/lib/modules/${modDirVersion}/build

        # !!! No documentation on how much of the source tree must be kept
        # If/when kernel builds fail due to missing files, you can add
        # them here. Note that we may see packages requiring headers
        # from drivers/ in the future; it adds 50M to keep all of its
        # headers on 3.10 though.

        chmod +w -R ../source
        arch=`cd $dev/lib/modules/${modDirVersion}/build/arch; ls`

        # Remove unusued arches
        mv arch/$arch .
        rm -fR arch
        mkdir arch
        mv $arch arch

        # Remove all driver-specific code (50M of which is headers)
        rm -fR drivers

        # Keep all headers
        find .  -type f -name '*.h' -print0 | xargs -0 chmod -w

        # Keep root and arch-specific Makefiles
        chmod -w Makefile
        chmod -w arch/$arch/Makefile*

        # Keep whole scripts dir
        chmod -w -R scripts

        # Delete everything not kept
        find . -type f -perm -u=w -print0 | xargs -0 rm

        # Delete empty directories
        find -empty -type d -delete

        # Remove reference to kmod
        sed -i Makefile -e 's|= ${kmod}/sbin/depmod|= depmod|'
      '' else optionalString installsFirmware ''
        make firmware_install $makeFlags "''${makeFlagsArray[@]}" \
          $installFlags "''${installFlagsArray[@]}"
      '');

      # Remove build directory impurities
      preFixup = ''
        find "$dev" -name '*.s' -exec sed -i '/-f[^ ]\+-prefix-map/d' {} \;
        find "$dev" -name '*.cmd' -delete
        find "$dev" -name '*.d' -exec sed -i "s,$TMPDIR,/no-such-path,g" {} \;
      '';

      # !!! This leaves references to gcc in $dev
      # that we might be able to avoid
      postFixup = if isModular then ''
        # !!! Should this be part of stdenv? Also patchELF should take an argument...
        prefix=$dev
        patchELF
        prefix=$out
      '' else null;

      meta = {
        description =
          "The Linux kernel" +
          (if kernelPatches == [] then "" else
            " (with patches: "
            + stdenv.lib.concatStrings (stdenv.lib.intersperse ", " (map (x: x.name) kernelPatches))
            + ")");
        license = stdenv.lib.licenses.gpl2;
        homepage = http://www.kernel.org/;
        repositories.git = https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git;
        maintainers = [
          maintainers.thoughtpolice
        ];
        platforms = platforms.linux;
      };
    };
in

stdenv.mkDerivation ((drvAttrs config (kernelPatches ++ nativeKernelPatches) configfile) // {
  name = "linux-${version}";

  # GMP / MPFR / libmpc is a hack that should be fixed in gcc
  nativeBuildInputs = [ bc elfutils openssl perl ]
    ++ stdenv.lib.optionals (stdenv.lib.versionAtLeast version "4.9") [ gmp mpfr libmpc ]
    ++ stdenv.lib.optionals (stdenv.lib.versionAtLeast version "4.16") [ bison flex ]
    ++ stdenv.lib.optionals needsGitPatch [ git ];

  preBuild = ''
    chmod +x ./tools/objtool/sync-check.sh || true
  '';

  makeFlags = commonMakeFlags ++ [
    "ARCH=${common.kernelArch}"
  ];

  karch = common.kernelArch;
})
