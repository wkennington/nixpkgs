{ stdenv
, fetchurl
, gnum4
, lib
, makeWrapper

, coreutils
, pacman
, util-linux_full
}:

let
  inherit (lib)
    concatStringsSep;

  path = [
    coreutils
    pacman
    util-linux_full
  ];
in
stdenv.mkDerivation rec {
  name = "arch-install-scripts-18";

  src = fetchurl {
    url = "https://sources.archlinux.org/other/arch-install-scripts/${name}.tar.gz";
    multihash = "QmWt9SWxWwGem34eVs8ryHUe8A1KiR54JWxBxzsYoppbEY";
    hashOutput = false;
    sha256 = "1221e1ec07ab0365d77726d6becb08c1a37419541705d27fa8a93464828fd406";
  };

  nativeBuildInputs = [
    gnum4
    makeWrapper
  ];

  preBuild = ''
    makeFlagsArray+=("PREFIX=$out")
  '';

  postInstall = ''
    wrapProgram "$out"/bin/pacstrap \
      --set PATH "${concatStringsSep ":" (map (n: "${n}/bin") path)}"
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      pgpsigUrls = map (n: "${n}.sig") src.urls;
      pgpKeyFingerprint = "487E ACC0 8557 AD08 2088  DABA 1EB2 638F F56C 0C53";
      inherit (src) urls outputHash outputHashAlgo;
    };
  };

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
