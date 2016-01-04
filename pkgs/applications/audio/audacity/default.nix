{ stdenv, fetchurl, wxGTK, gettext, gtk2, glib, zlib, perl, intltool,
  libogg, libvorbis, libmad, alsaLib, libsndfile, soxr, flac, lame,
  expat, libid3tag, ffmpeg, soundtouch /*, portaudio - given up fighting their portaudio.patch */
  }:

stdenv.mkDerivation rec {
  version = "2.1.1";
  name = "audacity-${version}";

  src = fetchurl {
    url = "https://github.com/audacity/audacity/archive/Audacity-${version}.tar.gz";
    sha256 = "15c5ff7ac1c0b19b08f4bdcb0f4988743da2f9ed3fab41d6f07600e67cb9ddb6";
  };

  preConfigure = /* we prefer system-wide libs */ ''
    mv lib-src lib-src-rm
    mkdir lib-src
    mv lib-src-rm/{Makefile*,lib-widget-extra,portaudio-v19,portmixer,portsmf,FileDialog,sbsms,libnyquist} lib-src/
    rm -r lib-src-rm/
  '';

  configureFlags = "--with-libsamplerate";

  buildInputs = [
    gettext wxGTK gtk2 expat alsaLib
    libsndfile soxr libid3tag
    ffmpeg libmad lame libvorbis flac soundtouch
  ]; #ToDo: detach sbsms

  dontDisableStatic = true;
  doCheck = false; # Test fails

  meta = {
    description = "Sound editor with graphical UI";
    homepage = http://audacityteam.org/;
    license = stdenv.lib.licenses.gpl2Plus;
    platforms = with stdenv.lib.platforms; linux;
    maintainers = with stdenv.lib.maintainers; [ the-kenny ];
  };
}
