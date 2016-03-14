{ stdenv
, bison
, fetchurl
, gnum4
}:

stdenv.mkDerivation rec {
  name = "flex-2.6.0";

  src = fetchurl {
    url = "mirror://sourceforge/flex/${name}.tar.xz";
    multihash = "Qmbh4C3bjyQ8oKNPHkc2euP7SGHrcKBL9dZHu8UH9iHMHY";
    sha256 = "d39b15a856906997ced252d76e9bfe2425d7503c6ed811669665627b248e4c73";
  };

  nativeBuildInputs = [
    bison
    gnum4
  ];

  # Using static libraries fixes issues with references to
  # yylex in flex 2.6.0
  # This can be tested by building glusterfs
  configureFlags = [
    "--disable-shared"
  ];

  dontDisableStatic = true;

  meta = with stdenv.lib; {
    homepage = http://flex.sourceforge.net/;
    description = "A fast lexical analyser generator";
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux
      ++ i686-linux;
  };
}
