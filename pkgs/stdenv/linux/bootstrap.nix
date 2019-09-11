{ lib
, fetchurl
, hostSystem
}:

let
  makeUrls = { multihash, nix-hash, file, sha256, executable ? false }:
    fetchurl {
      name = file;
      inherit multihash sha256 executable;
    };
in
if [ hostSystem ] == lib.platforms.x86_64-linux || [ hostSystem ] == lib.platforms.i686-linux || [ hostSystem ] == lib.platforms.powerpc64le-linux then {
  busybox = makeUrls {
    file = "bootstrap-busybox";
    nix-hash = "794m4bqyvkniwy14axhbvvlwn0nfkvgg";
    multihash = "Qma8NRuL2omkHsjqYv7wYFqYJ5gVFsxe3C73iVpzQEKREV";
    sha256 = "0m2jamdl5q86p7540g5bsb9g9dgxr3nq4a75rzchlm8ich6cljca";
    executable = true;
  };

  bootstrapTools = makeUrls {
    file = "bootstrap-tools.tar.xz";
    nix-hash = "794m4bqyvkniwy14axhbvvlwn0nfkvgg";
    multihash = "QmWq525ugaE6MWjVMCz8xUjxxGa9nLdw9ibwxH8b1qJdr6";
    sha256 = "86774a1d77dec741652a162a3003a3cddfa40cef8b168f3a954c877fe8a81164";
  };
} else
  throw "Unsupported System ${hostSystem}"
