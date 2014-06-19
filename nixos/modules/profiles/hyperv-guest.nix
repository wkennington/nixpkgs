# Common configuration for virtual machines running under Hyper-V
{ ... }:
{
  boot.initrd.availableKernelModules = [ "hv_storvsc" "hyperv_fb" "hyperv_keyboard" ];
}
