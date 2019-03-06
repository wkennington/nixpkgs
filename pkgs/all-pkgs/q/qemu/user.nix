{ stdenv
, bison
, fetchurl
, flex
, perl
, python3

, glib
, zlib
}:

let
  common = import ./common.nix {
    inherit
      bison
      fetchurl
      flex
      perl
      python3
      stdenv;
  };
in
stdenv.mkDerivation (common // {
  buildInputs = [
    glib
    zlib
  ];

  configureFlags = common.configureFlags ++ [
    #"--static"  # TODO: Required for binfmt
    "--disable-system"
    "--disable-tools"
    "--enable-user"
  ];
})
