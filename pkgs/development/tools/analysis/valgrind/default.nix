{ stdenv
, fetchurl
, perl

, gdb
}:

stdenv.mkDerivation rec {
  name = "valgrind-3.11.0";

  src = fetchurl {
    url = "http://valgrind.org/downloads/${name}.tar.bz2";
    sha256 = "0hiv871b9bk689mv42mkhp76za78l5773glszfkdbpf1m1qn4fbc";
  };

  # Perl is needed for `cg_annotate'.
  nativeBuildInputs = [
    perl
  ];

  # GDB is needed to provide a sane default for `--db-command'.
  buildInputs = [
    gdb
  ];

  meta = with stdenv.lib; {
    homepage = http://www.valgrind.org/;
    description = "Debugging and profiling tool suite";
    license = licenses.gpl2Plus;
    maintainers = with stdenv.lib; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
