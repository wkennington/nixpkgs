{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.boot.loader.grub;

  efi = config.boot.loader.efi;

  grubMbr =
    if cfg.version == 1 then
      pkgs.grub
    else if cfg.version == 2 then
      pkgs.grub2
    else
      throw "Unsupported Grub Configuration for MBR";

  grubEfi =
    if cfg.version == 2 then
      pkgs.grub2_efi
    else
      throw "Unsupported Grub Configuration for EFI";

  grubConfig = args: let
    efiBootloaderId = if args.efiSys != null then "NixOS${replaceChars [ "/" ] [ "-" ] args.efiSysMountPoint}" else null;
    grubMbr' = if args.mbrDevices == [ ] then "" else grubMbr;
    grubEfi' = if args.efiSys == null then "" else grubEfi;
  in pkgs.writeText "grub-config.xml" (builtins.toXML {
    splashImage = if cfg.splashImage == null then "" else cfg.splashImage;
    grubMbr = grubMbr';
    grubEfi = grubEfi';
    grubTarget = grubMbr'.grubTarget or null;
    grubTargetEfi = grubEfi'.grubTarget or null;
    shell = "${pkgs.stdenv.shell}";
    fullName =
      if grubMbr' != null then
        grubMbr'
      else if grubEfi' != null then
        grubEfi'
      else
        "";
    bootPath = args.path;
    efiBootloaderId = if args.efiBootloaderId == null then efiBootloaderId else args.efiBootloaderId;
    inherit (args)
      efiSys
      mbrDevices;
    inherit (efi)
      canTouchEfiVariables;
    inherit (config.boot.loader)
      timeout;
    inherit (cfg)
      version
      extraConfig
      extraPerEntryConfig
      extraEntries
      extraEntriesBeforeNixOS
      extraPrepareConfig
      configurationLimit
      copyKernels
      default
      fsIdentifier
      gfxmodeEfi
      gfxmodeBios;
    path = makeSearchPath "bin" ([
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.diffutils
      pkgs.btrfs-progs
      pkgs.util-linux_full
      pkgs.mdadm
    ] ++ optionals (grubEfi' != null) [
      pkgs.efibootmgr
    ]);
  });

  bootDeviceCounters = fold (device: attr: attr // { "${device}" = (attr."${device}" or 0) + 1; }) {}
    (concatMap (args: args.mbrDevices) cfg.mirroredBoots);

in

{

  ###### interface

  options = {

    boot.loader.grub = {

      enable = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether to enable the GNU GRUB boot loader.
        '';
      };

      version = mkOption {
        default = 2;
        example = 1;
        type = types.int;
        description = ''
          The version of GRUB to use: <literal>1</literal> for GRUB
          Legacy (versions 0.9x), or <literal>2</literal> (the
          default) for GRUB 2.
        '';
      };

      installPoints = mkOption {
        example = [
          { path = "/boot1"; devices = [ "/dev/sda" ]; }
          { path = "/boot2"; devices = [ "/dev/sdb" ]; }
        ];
        description = ''
          Mirror the boot configuration to multiple partitions and install grub
          to the respective devices corresponding to those partitions.
        '';

        type = types.listOf types.optionSet;

        options = {

          path = mkOption {
            example = "/boot1";
            type = types.str;
            description = ''
              The path to the boot directory where GRUB will be written. Generally
              this boot path should double as an EFI path.
            '';
          };

          efiSys = mkOption {
            example = "/boot1/efi";
            type = types.nullOr types.str;
            description = ''
              The path to the efi system mount point. Usually this is the same
              partition as the above path and can be left as null. If you are
              not using efi set this to null;
            '';
          };

          efiBootloaderId = mkOption {
            default = null;
            example = "NixOS-fsid";
            type = types.nullOr types.str;
            description = ''
              The id of the bootloader to store in efi nvram.
              The default is to name it NixOS and append the path or efiSys.
              This is only used if <literal>boot.loader.efi.canTouchEfiVariables</literal> is true.
            '';
          };

          mbrDevices = mkOption {
            example = [ "/dev/sda" "/dev/sdb" ];
            type = types.listOf types.str;
            description = ''
              The path to the devices which will have the GRUB MBR written.
              Note these are typically device paths and not paths to partitions.
              If you don't want to write to mbr devices, set this to the empty list instead.
              This is usually empty on efi enabled machines.
            '';
          };

        };
      };

      configurationName = mkOption {
        default = "";
        example = "Stable 2.6.21";
        type = types.str;
        description = ''
          GRUB entry name instead of default.
        '';
      };

      extraPrepareConfig = mkOption {
        default = "";
        type = types.lines;
        description = ''
          Additional bash commands to be run at the script that
          prepares the GRUB menu entries.
        '';
      };

      extraConfig = mkOption {
        default = "";
        example = "serial; terminal_output.serial";
        type = types.lines;
        description = ''
          Additional GRUB commands inserted in the configuration file
          just before the menu entries.
        '';
      };

      extraPerEntryConfig = mkOption {
        default = "";
        example = "root (hd0)";
        type = types.lines;
        description = ''
          Additional GRUB commands inserted in the configuration file
          at the start of each NixOS menu entry.
        '';
      };

      extraEntries = mkOption {
        default = "";
        type = types.lines;
        example = ''
          # GRUB 1 example (not GRUB 2 compatible)
          title Windows
            chainloader (hd0,1)+1

          # GRUB 2 example
          menuentry "Windows 7" {
            chainloader (hd0,4)+1
          }
        '';
        description = ''
          Any additional entries you want added to the GRUB boot menu.
        '';
      };

      extraEntriesBeforeNixOS = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether extraEntries are included before the default option.
        '';
      };

      extraFiles = mkOption {
        type = types.attrsOf types.path;
        default = {};
        example = literalExample ''
          { "memtest.bin" = "''${pkgs.memtest86plus}/memtest.bin"; }
        '';
        description = ''
          A set of files to be copied to <filename>/boot</filename>.
          Each attribute name denotes the destination file name in
          <filename>/boot</filename>, while the corresponding
          attribute value specifies the source file.
        '';
      };

      splashImage = mkOption {
        type = types.nullOr types.path;
        example = literalExample "./my-background.png";
        description = ''
          Background image used for GRUB.  It must be a 640x480,
          14-colour image in XPM format, optionally compressed with
          <command>gzip</command> or <command>bzip2</command>.  Set to
          <literal>null</literal> to run GRUB in text mode.
        '';
      };

      gfxmodeEfi = mkOption {
        default = "auto";
        example = "1024x768";
        type = types.str;
        description = ''
          The gfxmode to pass to GRUB when loading a graphical boot interface under EFI.
        '';
      };

      gfxmodeBios = mkOption {
        default = "1024x768";
        example = "auto";
        type = types.str;
        description = ''
          The gfxmode to pass to GRUB when loading a graphical boot interface under BIOS.
        '';
      };

      configurationLimit = mkOption {
        default = 100;
        example = 120;
        type = types.int;
        description = ''
          Maximum of configurations in boot menu. GRUB has problems when
          there are too many entries.
        '';
      };

      copyKernels = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether the GRUB menu builder should copy kernels and initial
          ramdisks to /boot.  This is done automatically if /boot is
          on a different partition than /.
        '';
      };

      default = mkOption {
        default = 0;
        type = types.int;
        description = ''
          Index of the default menu item to be booted.
        '';
      };

      fsIdentifier = mkOption {
        default = "uuid";
        type = types.addCheck types.str
          (type: type == "uuid" || type == "label" || type == "provided");
        description = ''
          Determines how GRUB will identify devices when generating the
          configuration file. A value of uuid / label signifies that grub
          will always resolve the uuid or label of the device before using
          it in the configuration. A value of provided means that GRUB will
          use the device name as show in <command>df</command> or
          <command>mount</command>. Note, zfs zpools / datasets are ignored
          and will always be mounted using their labels.
        '';
      };

    };

  };


  ###### implementation

  config = mkMerge [

    { boot.loader.grub.splashImage = mkDefault (
        if cfg.version == 1 then pkgs.fetchurl {
          url = http://www.gnome-look.org/CONTENT/content-files/36909-soft-tux.xpm.gz;
          sha256 = "14kqdx2lfqvh40h6fjjzqgff1mwk74dmbjvmqphi6azzra7z8d59";
        }
        # GRUB 1.97 doesn't support gzipped XPMs.
        else "${pkgs.nixos-artwork}/share/artwork/gnome/Gnome_Dark.png");
    }

    (mkIf cfg.enable {

      system.build.installBootLoader = pkgs.writeScript "install-grub.sh" (''
        #!${pkgs.stdenv.shell}
        set -e
        export PERL5LIB=${makePerlPath (with pkgs.perlPackages; [ FileSlurp XMLLibXML XMLSAX XMLSAXBase ListCompare ])}
        export GRUB_ENABLE_CRYPTODISK=y
      '' + flip concatMapStrings cfg.installPoints (args: ''
        ${pkgs.perl}/bin/perl ${./install-grub.pl} ${grubConfig args} $@
      ''));

      system.build.grub = grub;

      # Common attribute for boot loaders so only one of them can be
      # set at once.
      system.boot.loader.id = "grub";

      environment.systemPackages = optional (grub != null) grub;

      boot.loader.grub.extraPrepareConfig =
        concatStrings (mapAttrsToList (n: v: ''
          ${pkgs.coreutils}/bin/cp -pf "${v}" "/boot/${n}"
        '') config.boot.loader.grub.extraFiles);

      assertions = [
        {
          assertion = cfg.installPoints != [ ];
          message = "'boot.loader.grub.installPoints' to make the system bootable.";
        }
        {
          assertion = all (c: c < 2) (mapAttrsToList (_: c: c) bootDeviceCounters);
          message = "You cannot have duplicated devices in installPoints";
        }
      ] ++ flip concatMap cfg.installPoints (args: [
        {
          assertion = hasPrefix "/" args.path;
          message = "Boot paths must be absolute, not ${args.path}";
        }
        {
          assertion = if args.efiSysMountPoint == null then true else hasPrefix "/" args.efiSysMountPoint;
          message = "Efi paths must be absolute, not ${args.efiSysMountPoint}";
        }
      ] ++ flip map args.mbrDevices (device: {
        assertion = hasPrefix "/" device;
        message = "GRUB devices must be absolute paths, not ${dev} in ${args.path}";
      }));
    })

  ];


  imports =
    [ (mkRemovedOptionModule [ "boot" "loader" "grub" "bootDevice" ])
      (mkRenamedOptionModule [ "boot" "copyKernels" ] [ "boot" "loader" "grub" "copyKernels" ])
      (mkRenamedOptionModule [ "boot" "extraGrubEntries" ] [ "boot" "loader" "grub" "extraEntries" ])
      (mkRenamedOptionModule [ "boot" "extraGrubEntriesBeforeNixos" ] [ "boot" "loader" "grub" "extraEntriesBeforeNixOS" ])
      (mkRenamedOptionModule [ "boot" "grubDevice" ] [ "boot" "loader" "grub" "device" ])
      (mkRenamedOptionModule [ "boot" "bootMount" ] [ "boot" "loader" "grub" "bootDevice" ])
      (mkRenamedOptionModule [ "boot" "grubSplashImage" ] [ "boot" "loader" "grub" "splashImage" ])
    ];

}
