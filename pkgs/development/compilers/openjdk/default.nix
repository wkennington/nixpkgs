{ stdenv
, fetchurl
, lib
}:

let
  version = "10.0.2+13";
in
stdenv.mkDerivation {
  name = "openjdk-${version}";

  src = fetchurl {
    url = "http://hg.openjdk.java.net/jdk-updates/jdk10u/archive/jdk-${version}.tar.bz2";
    insecureHashOutput = true;
    sha256 = "374f7ae35f0a7439a40bd2c765d1f410607c75c6c1e788f1a344a42e59431f51";
  };

  postPatch = ''
    chmod +x configure
    patchShebangs configure
  
    cat doc/building.md
  '';

  configureFlags = [
    "--help"
  ];

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
