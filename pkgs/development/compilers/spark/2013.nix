{ stdenv, fetchurl, gnat, ... } @ args:

import ./generic.nix (args // rec {
  version = "2013";

  src = fetchurl {
    name = "spark-ada-${version}.tar.gz";
    url = "http://mirrors.cdn.adacore.com/art/0a1f8ffbd4873bb9e3c01f9d6297cd08ef6f11cd";
    sha256 = "14v75vfnqiknmrz4m0gz4xyxiizy2zzinb51r3jbabmjjzwhxifd";
  };
} // (args.argsOverride or {}))
