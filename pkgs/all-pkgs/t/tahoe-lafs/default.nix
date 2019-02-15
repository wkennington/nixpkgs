{ stdenv
, buildPythonPackage
, fetchPyPi

, characteristic
, foolscap
, magic-wormhole
, nevow
, pyasn1
, pycrypto
, pycryptopp
, pyopenssl
, pyyaml
, service-identity
, simplejson
, twisted
, zfec
}:

let
  version = "1.13.0";
in
buildPythonPackage {
  name = "tahoe-lafs-${version}";

  src = fetchPyPi {
    package = "tahoe-lafs";
    type = ".tar.bz2";
    inherit version;
    sha256 = "82d4d20f2672e67927d91e73e54dbfd7e526eca27dea09a29f131bef7dfaee86";
  };

  propagatedBuildInputs = [
    characteristic
    foolscap
    magic-wormhole
    nevow
    #pyasn1
    pycryptopp
    pyopenssl
    pyyaml
    #service-identity
    #simplejson
    twisted
    zfec
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
