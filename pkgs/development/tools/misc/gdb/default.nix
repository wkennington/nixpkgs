{ stdenv
, bison
, fetchurl
, flex
, gnum4
, texinfo
}:

stdenv.mkDerivation rec {
  name = "gdb-7.11";

  src = fetchurl {
    url = "mirror://gnu/gdb/${name}.tar.xz";
    sha256 = "7a434116cb630d77bb40776e8f5d3937bed11dea56bafebb4d2bc5dd389fe5c1";
  };

  nativeBuildInputs = [
    bison
    flex
    gnum4
    texinfo
  ];
  
  postPatch = ''
    rm -r bfd intl libdecnumber libiberty opcodes readline texinfo zlib

    sed \
      -e 's,.*/development.sh,true,g' \
      -e 's,.*/config.bfd,true,g' \
      -i gdb/configure
  '';

  configureFlags = [
    "--with-system-zlib"
  ];

  # Remove Info files already provided by Binutils and other packages.
  postInstall = ''
    rm -v $out/share/info
  '';

  meta = with stdenv.lib; {
    description = "The GNU Project debugger";
    homepage = http://www.gnu.org/software/gdb/;
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
