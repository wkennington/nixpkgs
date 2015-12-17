{ qtSubmodule, stdenv, qtdeclarative, qtlocation, qtmultimedia, qtsensors
, fontconfig, libwebp, libxml2, libxslt
, sqlite, udev
, bison, flex, gdb, gperf, perl, pkgconfig, python, ruby
}:

with stdenv.lib;

qtSubmodule {
  name = "qtwebkit";
  qtInputs = [ qtdeclarative qtlocation qtmultimedia qtsensors ];
  buildInputs = [ fontconfig libwebp libxml2 libxslt sqlite ];
  nativeBuildInputs = [
    bison flex gdb gperf perl pkgconfig python ruby
  ];
}
