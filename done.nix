let
  inherit (import ./default.nix { })
    pkgs;

  inherit (pkgs.lib)
    concatMap
    concatMapStrings
    flip;

  set = with pkgs; [
    bison
    flex
    curl_minimal
    expat
    libxml2_lib
    stdenv
    strace
  ];
in
pkgs.stdenv.mkDerivation {
  name = "done";

  preferLocalBuild = true;
  allowSubstitutes = false;

  buildCommand = ''
    mkdir -p "$out"
  '' + flip concatMapStrings (concatMap (p: p.all) set) (n: ''
    ln -sv "${n}" "$out"
  '');
}
