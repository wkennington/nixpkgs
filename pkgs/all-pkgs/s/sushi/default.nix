{ stdenv
, fetchurl
, gettext
, intltool
, makeWrapper

, atk
, clutter
, clutter-gst
, clutter-gtk
, cogl
, dconf
, evince
, freetype
, gdk-pixbuf
, gjs
, glib
, gobject-introspection
, gst-plugins-base
, gstreamer
, gtk
, gtksourceview
, json-glib
, libmusicbrainz
, libx11
, pango
, webkitgtk

, channel
}:

let
  sources = {
    "3.24" = {
      version = "3.24.0";
      sha256 = "f90bb95172664486f8d529995007fd12f0df9d0c998e20658b6203f46ce70d48";
    };
  };
  source = sources."${channel}";
in
stdenv.mkDerivation rec {
  name = "sushi-${source.version}";

  src = fetchurl {
    url = "mirror://gnome/sources/sushi/${channel}/${name}.tar.xz";
    hashOutput = false;
    inherit (source) sha256;
  };

  nativeBuildInputs = [
    gettext
    intltool
    makeWrapper
  ];

  buildInputs = [
    atk
    clutter
    clutter-gst
    clutter-gtk
    cogl
    dconf
    evince
    freetype
    gdk-pixbuf
    gjs
    glib
    gobject-introspection
    gst-plugins-base
    gstreamer
    gtk
    gtksourceview
    json-glib
    libmusicbrainz
    libx11
    pango
    webkitgtk
  ];

  configureFlags = [
    "--disable-maintainer-mode"
    "--enable-nls"
  ];

  preFixup = ''
    wrapProgram $out/bin/sushi \
      --set 'GDK_PIXBUF_MODULE_FILE' "${gdk-pixbuf.loaders.cache}" \
      --set 'GSETTINGS_BACKEND' 'dconf' \
      --prefix 'GI_TYPELIB_PATH' : "$GI_TYPELIB_PATH" \
      --prefix 'GIO_EXTRA_MODULES' : "$GIO_EXTRA_MODULES" \
      --prefix 'GST_PLUGIN_SYSTEM_PATH_1_0' : "$GST_PLUGIN_SYSTEM_PATH_1_0" \
      --prefix 'XDG_DATA_DIRS' : "$GSETTINGS_SCHEMAS_PATH" \
      --prefix 'XDG_DATA_DIRS' : "$out/share" \
      --prefix 'XDG_DATA_DIRS' : "$XDG_ICON_DIRS"
  '';

  passthru = {
    srcVerification = fetchurl {
      inherit (src)
        outputHash
        outputHashAlgo
        urls;
      sha256Url = "https://download.gnome.org/sources/sushi/${channel}/"
        + "${name}.sha256sum";
      failEarly = true;
    };
  };

  meta = with stdenv.lib; {
    description = "A quick previewer for Nautilus";
    homepage = "http://en.wikipedia.org/wiki/Sushi_(software)";
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [
      codyopel
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
