{ stdenv, fetchurl, xorg, perl, libxkbcommon }:

stdenv.mkDerivation rec {
  name = "xdotool-${version}";
  version = "3.20150503.1";
  src = fetchurl {
    url = "https://github.com/jordansissel/xdotool/releases/download/v${version}/xdotool-${version}.tar.gz";
    sha256 = "1lcngsw33fy9my21rdiz1gs474bfdqcfxjrnfggbx4aypn1nhcp8";
  };

  nativeBuildInputs = [ perl ];
  buildInputs = [ xorg.libX11 xorg.libXtst xorg.xextproto xorg.libXi xorg.libXinerama libxkbcommon ];

  makeFlags = "PREFIX=$(out)";

  meta = {
    homepage = http://www.semicomplete.com/projects/xdotool/;
    description = "Fake keyboard/mouse input, window management, and more";
    license = stdenv.lib.licenses.bsd3;
    maintainers = with stdenv.lib.maintainers; [viric];
    platforms = with stdenv.lib.platforms; linux;
  };
}
