{ lib
, buildGo
, fetchGo
}:

let
  inherit (builtins.fromJSON (builtins.readFile ./source.json))
    version;

  name = "ipfs-${version}";
in
buildGo {
  inherit name;

  src = fetchGo {
    inherit name;
    gomod = ./go.mod;
    gosum = ./go.sum;
    sourceJSON = ./source.json;
  };

  installedSubmodules = [
    "cmd/ipfs"
  ];

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
