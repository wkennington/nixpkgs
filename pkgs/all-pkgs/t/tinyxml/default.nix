{ stdenv
, fetchFromGitHub
, cmake
, lib
, ninja
}:

let
  version = "7.0.1";
in
stdenv.mkDerivation {
  name = "tinyxml-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "leethomason";
    repo = "tinyxml2";
    rev = version;
    sha256 = "033b128c64e8bf17cebfb0c18e54707060ca2a4cb501f922baebe673545d4494";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
