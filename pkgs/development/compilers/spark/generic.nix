{ stdenv, gnat
, version, src, patches ? [],  extraInputs ? [ ]
, ...
}:

stdenv.mkDerivation rec {
  inherit src patches;

  name = "spark-ada-${version}";

  buildInputs = [ gnat ] ++ extraInputs;

  meta = with stdenv.lib; {
    homepage = http://libre.adacore.com/tools/spark-gpl-edition/;
    license = licenses.gpl3;
    platforms = platforms.unix;
  };
}
