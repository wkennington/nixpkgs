{ stdenv
, docbook-xsl
, fetchurl
, intltool
, libxslt

, dbus-glib
, glib
, libgudev
, libusb
, systemd_lib
, gobject-introspection
}:

stdenv.mkDerivation rec {
  name = "upower-${version}";
  version = "0.99.4";

  src = fetchurl {
    urls = [
      "http://upower.freedesktop.org/releases/${name}.tar.xz"
      "http://http.debian.net/debian/pool/main/u/upower/upower_${version}.orig.tar.xz"
    ];
    sha256 = "1c1ph1j1fnrf3vipxb7ncmdfc36dpvcvpsv8n8lmal7grjk2b8ww";
  };

  nativeBuildInputs = [
    docbook-xsl
    intltool
    libxslt
  ];

  buildInputs = [
    dbus-glib
    glib
    libgudev
    libusb
    systemd_lib
    gobject-introspection
  ];

  configureFlags = [
    "--with-backend=linux"
    "--localstatedir=/var"
    "--sysconfdir=/etc"
    "--with-systemdsystemunitdir=$(out)/etc/systemd/system"
    "--with-systemdutildir=$(out)/lib/systemd"
    "--with-udevrulesdir=$(out)/lib/udev/rules.d"
  ];

  NIX_CFLAGS_LINK = "-lgcc_s";

  installFlags = [
    "historydir=$(TMPDIR)/foo"
    "sysconfdir=$(out)/etc"
  ];

  meta = {
    homepage = http://upower.freedesktop.org/;
    description = "A D-Bus service for power management";
    platforms = stdenv.lib.platforms.linux;
  };
}
