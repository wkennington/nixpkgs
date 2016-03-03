{ lib, ... }:

with lib;

{
  options.boot.loader.efi = {
    canTouchEfiVariables = mkOption {
      type = types.bool;
      description = ''
        Whether or not the installation process should modify efi boot variables.
        You probably want to enable this.
      '';
    };

    efiSysMountPoint = mkOption {
      type = types.str;
      description = ''
        Where the EFI System Partition is mounted.
      '';
    };
  };
}
