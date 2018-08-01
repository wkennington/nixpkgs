{ stdenv
, fetchurl
, lib

, cairo
, gconf
, glu
, gstreamer
, gst-plugins-base
, gtk3
, expat
, libice
, libjpeg
, libnotify
, libpng
, libsm
, libtiff
, libx11
, libxinerama
, msgpack-c
, opengl-dummy
, xorg
, xorgproto
, xz
, zlib
}:

let
  version = "3.1.1";
in
stdenv.mkDerivation rec {
  name = "wxWidgets-${version}";

  src = fetchurl {
    url = "https://github.com/wxWidgets/wxWidgets/releases/download/v${version}/${name}.tar.bz2";
    sha1Confirm = "f999c3cf1887c0a60e519214c14b15cb9bb5ea6e";
    sha256 = "c925dfe17e8f8b09eb7ea9bfdcfcc13696a3e14e92750effd839f5e10726159e";
  };

  buildInputs = [
    #cairo
    #gconf
    #glu
    #gstreamer
    #gst-plugins-base
    #expat
    #libice
    libjpeg
    #libnotify
    #libpng
    #libsm
    #libtiff
    #libx11
    #libxinerama
    #msgpack-c
    #opengl-dummy
    #xorg.libXxf86vm
    #xorgproto
    xz
    zlib
  ];

  # WXWidget applications will depend directly on gtk
  propagatedBuildInputs = [
    gtk3
  ];

  SEARCH_LIB = "${opengl-dummy}/lib";

  preConfigure = ''
    sed -i configure \
      -e 's/SEARCH_INCLUDE=/DUMMY_SEARCH_INCLUDE=/' \
      -e 's/SEARCH_LIB=/DUMMY_SEARCH_LIB=/' \
      -e 's,/usr,/no-such-path,'
  '';

  configureFlags = [
    "--enable-monolithic"
    "--disable-precomp-headers"
    "--with-gtk=any"
  ];

  postInstall = ''
    pushd $out/include
    ln -sv wx-*/* .
    popd
  '';

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
