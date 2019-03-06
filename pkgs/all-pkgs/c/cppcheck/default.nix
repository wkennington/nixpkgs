{ stdenv
, fetchFromGitHub
, lib

, simplecpp
, tinyxml
}:

let
  version = "1.86";
in
stdenv.mkDerivation {
  name = "cppcheck-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "danmar";
    repo = "cppcheck";
    rev = version;
    sha256 = "f9391dfb9d0468d17ca1e32f70e60c7b1f00a86f2ada78821aca9edde9b7a44e";
  };

  postPatch = ''
    rm -r externals
    mkdir -p externals
    pushd externals >/dev/null
    unpackFile '${simplecpp.src}'
    mv simplecpp* simplecpp
    unpackFile '${tinyxml.src}'
    mv tinyxml* tinyxml
    popd >/dev/null
  '';

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
