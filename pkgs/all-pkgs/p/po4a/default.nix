{ stdenv
, docbook_xml_dtd_412
, docbook-xsl
, fetchurl
, gettext
, libxslt
, makeWrapper
, perlPackages
}:

let
  version = "0.55";
in
stdenv.mkDerivation rec {
  name = "po4a-${version}";

  src = fetchurl {
    url = "https://github.com/mquinson/po4a/releases/download/v${version}/${name}.tar.gz";
    sha256 = "596f7621697f9dd12709958c229e256b56683d25997ac73c9625a2cc0c603d51";
  };

  nativeBuildInputs = [
    docbook_xml_dtd_412
    docbook-xsl
    gettext
    libxslt
    makeWrapper
    perlPackages.LocaleGettext
    perlPackages.ModuleBuild
    perlPackages.perl
    perlPackages.SGMLSpm
    perlPackages.TermReadKey
    perlPackages.TextWrapI18N
    perlPackages.UnicodeLineBreak
  ];

  configurePhase = ''
    perl Build.PL installdirs=vendor create_packlist=0
  '';

  buildPhase = ''
    perl Build
  '';

  installPhase = ''
    find . -name \*.pm
    perl Build destdir=$out install
    dir="$out/${perlPackages.perl}"
    mv "$dir"/* "$out"
    while [ "$dir" != "$out" ]; do
      rmdir "$dir"
      dir="$(dirname "$dir")"
    done

    mkdir -p "$out/${perlPackages.perl.libPrefix}"
    cp -r blib/lib/* "$out/${perlPackages.perl.libPrefix}"
  '';

  preFixup = ''
    progs=($(find $out/bin -type f))
    for prog in "''${progs[@]}"; do
      wrapProgram "$prog" \
        --prefix PATH : "$out/bin:${gettext}/bin" \
        --prefix PERL5LIB : "$out/${perlPackages.perl.libPrefix}"
    done
  '';

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
