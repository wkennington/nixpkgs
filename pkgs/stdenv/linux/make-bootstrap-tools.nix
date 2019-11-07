{ targetSystem ? builtins.currentSystem
, hostSystem ? builtins.currentSystem
}:

let
  pkgs = import ../../.. { inherit targetSystem hostSystem; };

  a = import ./make-bootstrap-tools-common.nix {
    inherit (pkgs)
      bash_small
      busybox_bootstrap
      glibc_lib_gcc
      gcc
      gcc_lib_glibc
      gcc_runtime_glibc
      linux-headers
      nukeReferences
      stdenv;
  };
in a
