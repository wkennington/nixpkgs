{ stdenv
, bison
, fetchurl
, flex
, perl
, python3

, glib
, xorg
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
    xorg.pixman
    zlib
  ];

  configureFlags = common.configureFlags ++ [
    "--disable-system"
    "--enable-tools"
    "--disable-user"
  ];
})
