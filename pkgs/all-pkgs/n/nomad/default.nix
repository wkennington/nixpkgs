{ lib
, buildGo
, fetchFromGitHub
}:

let
  version = "0.9.3";
in
buildGo {
  name = "nomad-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "hashicorp";
    repo = "nomad";
    rev = "v${version}";
    sha256 = "c19c9673dee8c5f4bbb30360072f0d57f56031807b12cf6e1979585762071893";
  };

  srcRoot = null;

  postUnpack = ''
    srcNew="$NIX_BUILD_TOP"/go/src/github.com/hashicorp/nomad
    mkdir -p "$(dirname "$srcNew")"
    mv "$srcRoot" "$srcNew"
    srcRoot="$srcNew"
  '';

  goFlags = [
    "-tags" "nonvidia"
  ];

  installedSubmodules = [
    "."
  ];

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
