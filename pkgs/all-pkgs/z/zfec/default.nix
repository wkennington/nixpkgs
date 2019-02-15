{ stdenv
, buildPythonPackage
, fetchPyPi

, pyutil
}:

let
  version = "1.5.3";
in
buildPythonPackage {
  name = "zfec-${version}";

  src = fetchPyPi {
    package = "zfec";
    inherit version;
    sha256 = "b41bd4b0af9c6b3a78bd6734e1e4511475944164375e6241b53df518a366922b";
  };

  propagatedBuildInputs = [
    #pyutil
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
