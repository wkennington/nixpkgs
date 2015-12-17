{ stdenv, fetchurl, pkgconfig, intltool, vala, gobjectIntrospection
, glib, libxml2, sqlite
}:

let
  majorVersion = "2.52";
  version = "${majorVersion}.2";
in
stdenv.mkDerivation {
  name = "libsoup-${version}";

  src = fetchurl {
    url = "mirror://gnome/sources/libsoup/${majorVersion}/libsoup-${version}.tar.xz";
    sha256 = "db55628b5c7d952945bb71b236469057c8dfb8dea0c271513579c6273c2093dc";
  };

  nativeBuildInputs = [ pkgconfig intltool vala gobjectIntrospection ];
  buildInputs = [ glib libxml2 sqlite ];

  configureFlags = [
    "--disable-debug"
    "--enable-gnome"
    "--enable-tls-check"
    "--without-apache-httpd"
    "--without-ntlm-auth"
    "--disable-more-warnings"
  ];

  meta = {
    inherit (glib.meta) maintainers platforms;
  };
}
