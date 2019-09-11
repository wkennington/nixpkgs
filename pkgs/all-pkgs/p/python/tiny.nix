{ stdenv
, fetchurl
, lib
, python
}:

let
  version = "3.7.3";
in
stdenv.mkDerivation {
  name = "python-tiny-${version}";

  src = fetchurl {
    url = "https://www.python.org/ftp/python/${version}/Python-${version}.tar.xz";
    hashOutput = false;
    sha256 = "da60b54064d4cfcd9c26576f6df2690e62085123826cff2e667e72a91952d318";
  };

  nativeBuildInputs = [
    python
  ];

  configureFlags = [
    "--with-assertions"
    "--without-ensurepip"

    # Needed for cross compiling
    "--enable-ipv6"
    "ac_cv_file__dev_ptmx=yes"
    "ac_cv_file__dev_ptc=yes"
  ];

  postInstall = ''
    rm -r "$out"/lib/python*/test
    rm -r "$out"/lib/python*/config-*
    rm -r "$out"/share
    find "$out"/lib -name __pycache__ -prune -exec rm -r {} \;
    find "$out"/lib -name '*'.exe -delete
    rm -r "$out"/lib/python*/{idlelib,ensurepip}
    ln -sv python3 "$out"/bin/python
  '';

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux ++
      x86_64-linux ++
      powerpc64le-linux;
  };
}
