{ stdenv, fetchurl, gnat, ... } @ args:

import ./generic.nix (args // rec {
  version = "2012";

  src = fetchurl {
    name = "spark-ada-${version}.tar.gz";
    url = "http://mirrors.cdn.adacore.com/art/999ad5b5cdb68cf50c92c3117ac6c8160a7a4136";
    sha256 = "0pi79i57yl6b7r8cp42mhqh8m9l8lcxa3sfwb5dvswwc9nwq1sc0";
  };

  patches = [ ./2012-disable-warnings-as-errors.patch ];
} // (args.argsOverride or {}))
