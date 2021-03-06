{ stdenv
, docbook-xsl
, docbook-xsl-ns
, fetchurl
, gettext
, intltool
, libtool
, libxslt
, makeWrapper

, accountsservice
, adwaita-icon-theme
, at-spi2-atk
, at-spi2-core
, atk
, caribou
, clutter
, cogl
, dbus
, dbus-glib
, dconf
, evolution-data-server
, gcr
, gdk-pixbuf
, gdm
, gjs
, glib
, gnome-bluetooth
, gnome-clocks
, gnome-control-center
, gnome-desktop
, gnome-keyring
, gnome-menus
, gnome-session
, gnome-settings-daemon
, gobject-introspection
, gsettings-desktop-schemas
, gst-plugins-base
, gstreamer
, gtk3
, ibus
, json-glib
, libcanberra
, libcroco
, libical
, libgweather
, librsvg
, libsecret
, libsoup
, libstartup_notification
, libxkbcommon
, libxml2
, mesa
, mutter
, networkmanager
, networkmanager-applet
, nss
, p11-kit
, pango
, polkit
, pulseaudio_lib
, spidermonkey
, sqlite
, systemd_lib
, telepathy_glib
, telepathy_logger
, unzip
, upower
, wayland
#, webkitgtk
, xorg

, python3
, libffi
}:

let
  inherit (stdenv.lib)
    enFlag;
in
stdenv.mkDerivation rec {
  name = "gnome-shell-${version}";
  versionMajor = "3.22";
  versionMinor = "3";
  version = "${versionMajor}.${versionMinor}";

  src = fetchurl {
    url = "mirror://gnome/sources/gnome-shell/${versionMajor}/${name}.tar.xz";
    sha256Url = "mirror://gnome/sources/gnome-shell/${versionMajor}/"
      + "${name}.sha256sum";
    sha256 = "d1e6bd80ddd1fef92d80b518d4dbeffa296e8f003402551b8c37c42744b7d42f";
  };

  nativeBuildInputs = [
    docbook-xsl
    docbook-xsl-ns
    gettext
    intltool
    libtool
    libxslt
    makeWrapper
  ];

  buildInputs = [
    accountsservice
    adwaita-icon-theme
    at-spi2-atk
    at-spi2-core
    atk
    caribou
    clutter
    cogl
    dbus
    dbus-glib
    dconf
    evolution-data-server
    gcr
    gdk-pixbuf
    gdm
    glib
    gjs
    gnome-control-center#
    gnome-desktop
    gnome-keyring#
    gnome-menus
    gnome-session
    gnome-bluetooth
    libgweather
    gnome-clocks
    gnome-settings-daemon
    gobject-introspection
    gsettings-desktop-schemas
    gst-plugins-base
    gstreamer
    gtk3
    ibus
    json-glib
    libcanberra
    libcroco
    #libgnome-keyring
    #libical
    libsecret
    libsoup
    libstartup_notification
    #libxkbcommon
    libxml2
    mesa
    mutter
    networkmanager
    networkmanager-applet
    #nss
    #p11-kit
    pango
    polkit
    pulseaudio_lib
    python3
    #spidermonkey
    systemd_lib
    telepathy_glib
    telepathy_logger
    #tzdata
    upower
    #wayland
    #webkitgtk
    xorg.libSM
    xorg.libICE
    xorg.libX11
    xorg.libxcb
    xorg.libXext
    xorg.libXfixes
    xorg.libXinerama
    xorg.libXtst
  ];

  postPatch = ''
    patchShebangs ./src/data-to-c.pl
  '' + ''
    sed -i data/Makefile.in \
      -e 's/ install-keysDATA//'
  '';

  configureFlags = [
    # Needed to find /etc/NetworkManager/VPN
    "--sysconfdir=/etc"
    "--disable-maintainer-mode"
    "--enable-nls"
    "--enable-schemas-compile"
    (enFlag "systemd" (systemd_lib != null) null)
    "--enable-browser-plugin"
    (enFlag "introspection" (gobject-introspection != null) null)
    (enFlag "networkmanager" (networkmanager != null) null)
    "--enable-glibtest"
    "--disable-gtk-doc"
    "--disable-gtk-doc-html"
    "--disable-gtk-doc-pdf"
    "--disable-man"
    "--enable-compile-warnings"
    "--enable-Werror"
  ];

  installFlags = [
    "keysdir=$(out)/share/gnome-control-center/keybindings"
  ];

  preFixup = ''
    wrapProgram $out/bin/gnome-shell \
      --set 'GDK_PIXBUF_MODULE_FILE' "${gdk-pixbuf.loaders.cache}" \
      --set 'GSETTINGS_BACKEND' 'dconf' \
      --path 'PATH' : "${unzip}/bin" \
      --prefix 'GIO_EXTRA_MODULES' : "$GIO_EXTRA_MODULES" \
      --prefix 'GI_TYPELIB_PATH' : "$GI_TYPELIB_PATH" \
      --prefix 'XDG_DATA_DIRS' : "$GSETTINGS_SCHEMAS_PATH" \
      --prefix 'XDG_DATA_DIRS' : "$out/share" \
      --prefix 'XDG_DATA_DIRS' : "$XDG_ICON_DIRS" \
      --prefix 'XDG_DATA_DIRS' : "${evolution-data-server}/share"
  '' + ''
    echo "${unzip}/bin" > $out/${passthru.mozillaPlugin}/extra-bin-path
  '';

  passthru = {
    mozillaPlugin = "/lib/mozilla/plugins";
  };

  meta = with stdenv.lib; {
    description = "Provides core UI functions for the GNOME 3 desktop";
    homepage = https://wiki.gnome.org/Projects/GnomeShell;
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
