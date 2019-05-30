{ stdenv
, fetchurl
, gettext
, intltool
, lib
, libxml2
, makeWrapper
, python2Packages

, aalib
, alsa-lib
, atk
, babl
, bzip2
, cairo
, freetype
, fontconfig
, gdk-pixbuf
, gegl
, gexiv2
, ghostscript
, glib
, glib-networking
, gnome-themes-standard
, gtk_2
, harfbuzz_lib
, iso-codes
, jasper
, lcms2
, libexif
, libgudev
, libice
, libjpeg
, libmng
, libmypaint
, libpng
, librsvg
, libsm
, libtiff
, libwebp
, libwmf
, libx11
, libxcursor
, libxext
, libxfixes
, libxmu
, libxt
, libzip
, mypaint-brushes
, openexr
, pango
, poppler
, poppler-data
, shared-mime-info
, xorg
, xorgproto
, xz
, zlib
}:

let
  major = "2.10";
  patch = "8";

  version = "${major}.${patch}";
in
stdenv.mkDerivation rec {
  name = "gimp-${version}";

  src = fetchurl rec {
    url = "https://download.gimp.org/pub/gimp/v${major}/${name}.tar.bz2";
    multihash = "QmUp2FZpWg6KoAYF5mk3KYQAbM2TsaQZGjR4H6niw3vYv6";
    hashOutput = false;
    sha256 = "4eca071f828e918384cf7bc7d1219210467c84655123f802bc55a8bf2415101f";
  };

  nativeBuildInputs = [
    gettext
    intltool
    libxml2
    makeWrapper
    python2Packages.wrapPython
  ];

  buildInputs = [
    aalib
    alsa-lib
    atk
    babl
    bzip2
    cairo
    freetype
    fontconfig
    gdk-pixbuf
    gegl
    gexiv2
    ghostscript
    glib
    glib-networking
    gnome-themes-standard
    gtk_2
    harfbuzz_lib
    iso-codes
    jasper
    lcms2
    libexif
    libgudev
    libice
    libjpeg
    libmng
    libmypaint
    libpng
    librsvg
    libsm
    libtiff
    libwebp
    libwmf
    libx11
    libxcursor
    libxext
    libxfixes
    libxmu
    libxt
    libzip
    mypaint-brushes
    openexr
    pango
    poppler
    poppler-data
    python2Packages.pycairo
    python2Packages.pygtk
    python2Packages.python
    shared-mime-info
    xorg.libXpm
    xorgproto
    xz
    zlib
  ];

  pythonPath = [
    python2Packages.pycairo
    python2Packages.pygtk
  ];

  postPatch = /* Use system theme by default */ ''
    sed -i app/config/gimpguiconfig.h \
      -e '/GIMP_CONFIG_DEFAULT_THEME/ s/03-Dark/System/'
  '';

  configureFlags = [
    "--enable-vector-icons"
  ];

  NIX_LDFLAGS = [
    # "screenshot" needs this.
    "-rpath ${libx11}/lib"
  ];

  preBuild = ''
    # Build depends on shared-mime-info
    export XDG_DATA_DIRS="$XDG_DATA_DIRS''${XDG_DATA_DIRS:+:}${shared-mime-info}/share"

    # Build depends gdk pixbuf loaders
    export GDK_PIXBUF_MODULE_FILE='${gdk-pixbuf.loaders.cache}'
  '';

  postInstall = ''
    wrapPythonPrograms
  '';

  preFixup = ''
    wrapProgram $out/bin/gimp-${major} \
      --set 'GDK_PIXBUF_MODULE_FILE' '${gdk-pixbuf.loaders.cache}' \
      --prefix 'XDG_DATA_DIRS' : "${shared-mime-info}/share" \
      --prefix 'XDG_DATA_DIRS' : "$XDG_ICON_DIRS" \
      --run "$DEFAULT_GTK2_RC_FILES"
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts.sha256Urls = map (n: "${n}/../SHA256SUMS") src.urls;
    };
  };

  meta = with lib; {
    description = "The GNU Image Manipulation Program";
    homepage = http://www.gimp.org/;
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
