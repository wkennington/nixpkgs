{ stdenv
, fetchFromGitHub
, cmake
, lib
, ninja
}:

let
  rev = "25bdc35acc1a89b15851b649709d7903cd2f71dc";
  date = "2018-11-26";
in
stdenv.mkDerivation {
  name = "simplecpp-${date}";

  src = fetchFromGitHub {
    version = 6;
    owner = "danmar";
    repo = "simplecpp";
    inherit rev;
    sha256 = "7da334d7c37564714d79e9c2c920db15bd4ef279c3f4c93b299aef9f078f096d";
  };

  installPhase = ''
    mkdir -p "$out"/bin
    cp simplecpp "$out"/bin
  '';

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
