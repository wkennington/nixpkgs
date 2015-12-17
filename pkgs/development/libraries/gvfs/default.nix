{ stdenv, fetchurl, pkgconfig, intltool, libtool, makeWrapper, libxslt
, glib, dbus, gnome3, avahi, libxml2, samba, libarchive, libgcrypt, libbluray
, 
/*, glib, dbus, udev, libgudev, udisks2, libgcrypt
, libgphoto2, avahi, libarchive, fuse, libcdio
, libxml2, libxslt, docbook_xsl, samba, libmtp
, gnomeSupport ? false, gnome, libgnome_keyring, gconf
*/}:

let
  ver_maj = "1.26";
  version = "${ver_maj}.2";
in
stdenv.mkDerivation rec {
  name = "gvfs-${version}";

  src = fetchurl {
    url = "mirror://gnome/sources/gvfs/${ver_maj}/${name}.tar.xz";
    sha256 = "695b6e0f3de5ac2cb4d188917edef3f13299328150a2413f1a7131d9b2d48d18";
  };

  nativeBuildInputs = [ pkgconfig intltool libtool makeWrapper libxslt ];
  buildInputs = [ glib dbus gnome3.gcr avahi libxml2 samba libarchive libgcrypt libbluray libsoup ];
  /*buildInputs =
    [ makeWrapper glib dbus.libs udev libgudev udisks2 libgcrypt
      libgphoto2 avahi libarchive fuse libcdio
      libxml2 libxslt docbook_xsl samba libmtp
      # ToDo: a ligther version of libsoup to have FTP/HTTP support?
    ] ++ stdenv.lib.optionals gnomeSupport (with gnome; [
      gtk libsoup libgnome_keyring gconf
    ]);*/

  configureFlags = [
    "--enable-documentation"
    # "--with-dbus_service_dir"
    "--enable-gcr"
    "--enable-http"
    "--enable-avahi"
    "--enable-udev"
    "--enable-fuse"
    "--enable-gdu"
    "--enable-udisks2"
    "--enable-libsystemd_login"
    "--disable-hal"
    "--enable-gudev"
    "--enable-cdda"
    "--enable-afc"
    "--enable-goa"
    "--enable-google"
    "--enable-gphoto2"
    "--enable-keyring"
    "--enable-bluray"
    "--enable-libmtp"
    "--enable-samba"
    "--enable-gtk"
    "--enable-archive"
    "--enable-afp"
    "--enable-nfs"
    "--enable-bash-completion"
    # "--with-bash-completion-dir"
    "--disable-more-warnings"
    "--disable-installed-tests"
    "--disable-always-build-tests"
  ];

  enableParallelBuilding = true;

  # ToDo: one probably should specify schemas for samba and others here
  preFixup = ''
    wrapProgram $out/libexec/gvfsd --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH"
  '';

  meta = with stdenv.lib; {
    description = "Virtual Filesystem support library";
    platforms = platforms.linux;
    maintainers = [ maintainers.lethalman ];
  };
}
