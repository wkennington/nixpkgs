{ stdenv, lib, fetchurl, pam ? null, autoreconfHook
, xorg }:

stdenv.mkDerivation rec {

  name = "xlockmore-5.46";
  src = fetchurl {
    url = "http://www.tux.org/~bagleyd/xlock/${name}.tar.xz";
    sha256 = "1ps0dmnh912x8mwns94y2607xk90rjxrjn5s1pkmmpjg5h9bxcrj";
  };

  # Optionally, it can use GTK+.
  buildInputs = [ pam xorg.libX11 xorg.libXext xorg.libXinerama xorg.libXdmcp xorg.libXt ];

  nativeBuildInputs = [ autoreconfHook ];

  # Don't try to install `xlock' setuid. Password authentication works
  # fine via PAM without super user privileges.
  configureFlags =
    [ "--disable-setuid"
    ] ++ (lib.optional (pam != null) "--enable-pam");

  postPatch =
    let makePath = p: lib.concatMapStringsSep " " (x: x + "/" + p) buildInputs;
        inputs = "${makePath "lib"} ${makePath "include"}";
    in ''
      sed -i 's,\(for ac_dir in\),\1 ${inputs},' configure.ac
      sed -i 's,/usr/,/no-such-dir/,g' configure.ac
      configureFlags+=" --enable-appdefaultdir=$out/share/X11/app-defaults"
    '';

  meta = with lib; {
    description = "Screen locker for the X Window System";
    homepage = http://www.tux.org/~bagleyd/xlockmore.html;
    license = licenses.gpl2;
    maintainers = with maintainers; [ pSub ];
    platforms = platforms.linux;
  };
}
