{ stdenv
, fetchurl
, intltool
, lib
, libxslt

, atk
, dbus-glib
, gdk-pixbuf
, glib
, gobject-introspection
, gnupg
, gtk3
, libgcrypt
, libtasn1
, p11-kit
, pango
, vala
}:

let
  inherit (lib)
    boolEn;

  channel = "3.28";
  version = "${channel}.1";
in
stdenv.mkDerivation rec {
  name = "gcr-${version}";

  src = fetchurl {
    url = "mirror://gnome/sources/gcr/${channel}/${name}.tar.xz";
    sha256 = "95204aa2111c301778ebfbe60975ce3ed698c958430ffcc2a785ac5e593d168b";
  };

  nativeBuildInputs = [
    intltool
    libxslt
    vala
  ];

  buildInputs = [
    atk
    dbus-glib
    gdk-pixbuf
    glib
    gnupg
    gobject-introspection
    gtk3
    libgcrypt
    libtasn1
    p11-kit
    pango
  ];

  configureFlags = [
    "--disable-schemas-compile"
    "--enable-introspection"
    "--${boolEn (vala != null)}-vala"
    "--disable-update-mime"
    "--disable-update-icon-cache"
    "--disable-debug"
    "--disable-valgrind"
  ];

  doCheck = false;

  passthru = {
    srcVerification = fetchurl {
      inherit (src)
        outputHash
        outputHashAlgo
        urls;
      fullOpts = {
        sha256Url = "https://download.gnome.org/sources/gcr/${channel}/"
          + "${name}.sha256sum";
      };
      failEarly = true;
    };
  };

  meta = with lib; {
    description = "Libraries for cryptographic UIs and accessing PKCS#11 modules";
    homepage = https://git.gnome.org/browse/gcr;
    license = with licenses; [
      gpl2Plus
      lgpl2Plus
    ];
    maintainers = with maintainers; [
      codyopel
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
