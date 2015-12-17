{ stdenv, fetchurl, pkgconfig, glib, intltool, gnutls, libproxy
, gsettings_desktop_schemas }:

let
  ver_maj = "2.46";
  ver_min = "1";
in
stdenv.mkDerivation rec {
  name = "glib-networking-${ver_maj}.${ver_min}";

  src = fetchurl {
    url = "mirror://gnome/sources/glib-networking/${ver_maj}/${name}.tar.xz";
    sha256 = "d5034214217f705891b6c9e719cc2c583c870bfcfdc454ebbb5e5e8940ac90b1";
  };

  configureFlags = [
    "--with-libproxy"
    "--with-ca-certificates=/etc/ssl/certs/ca-certificates.crt"
  ];

  /*preBuild = ''
    sed -e "s@${glib}/lib/gio/modules@$out/lib/gio/modules@g" -i $(find . -name Makefile)
  '';*/

  nativeBuildInputs = [ pkgconfig intltool ];
  buildInputs = [ glib ];
  #propagatedBuildInputs = [ glib gnutls libproxy gsettings_desktop_schemas ];

  doCheck = false; # tests need to access the certificates (among other things)

  meta = with stdenv.lib; {
    description = "Network-related giomodules for glib";
    license = licenses.lgpl2Plus;
    platforms = platforms.unix;
  };
}

