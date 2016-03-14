{ stdenv
, fetchurl
, gnum4
}:

stdenv.mkDerivation rec {
  name = "bison-3.0.4";

  src = fetchurl {
    url = "mirror://gnu/bison/${name}.tar.xz";
    sha256 = "a72428c7917bdf9fa93cb8181c971b6e22834125848cf1d03ce10b1bb0716fe1";
  };

  nativeBuildInputs = [
    gnum4
  ];

  # We need this for bison to work correctly when being
  # used during the build process
  propagatedBuildInputs = [
    gnum4
  ];

  # We don't want a dependency on perl since it is horrible to build
  # during the early bootstrap when we need bison
  preConfigure = ''
    mkdir -p pbin
    echo "#! ${stdenv.shell}" >> pbin/perl
    echo "echo 0 > $(pwd)/examples/extracted.stamp" >> pbin/perl
    echo "echo 0 > $(pwd)/examples/extracted.stamp.tmp" >> pbin/perl
    chmod +x pbin/perl
    export PATH="$(pwd)/pbin:$PATH"
    cat pbin/perl

    touch examples/calc++/calc++-driver.cc
    touch examples/calc++/calc++-driver.hh
    touch examples/calc++/calc++-scanner.ll
    touch examples/calc++/calc++.cc
    touch examples/calc++/calc++-parser.yy
    touch examples/mfcalc/calc.h
    touch examples/mfcalc/mfcalc.y
    touch examples/rpcalc/rpcalc.y
  '';

  postInstall = ''
    rm -rf $out/share/doc
  '';

  meta = with stdenv.lib; {
    description = "Yacc-compatible parser generator";
    homepage = "http://www.gnu.org/software/bison/";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux
      ++ x86_64-linux;
  };
}
