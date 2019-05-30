{ stdenv
, fetchTritonPatch
, fetchurl
, gettext
, intltool
, itstool
, lib
, libxml2
, perl
, vala

, audit_lib
, glib
, gobject-introspection
, libgcrypt
, libx11
, libxcb
, libxdmcp
, libxklavier
, pam
}:

let
  version = "1.30.0";
in
stdenv.mkDerivation rec {
  name = "lightdm-${version}";

  src = fetchurl {
    url = "https://github.com/CanonicalLtd/lightdm/releases/download/"
      + "${version}/${name}.tar.xz";
    sha256 = "f20f599d8d7cf90b77a2df33c6e9e615abc443123b1b228de1c20a636aecfa07";
  };

  postPatch = ''
    grep -q '/usr/sbin/nologin' common/user-list.c
    sed -i common/user-list.c \
      -e 's,/usr/sbin/nologin,/usr/sbin/nologin /run/current-system/sw/bin/nologin,'

    grep -q '/usr/local/bin' src/session-child.c
    sed -i src/session-child.c \
      -e 's,/usr/local/bin:/usr/bin:/bin,/run/current-system/sw/bin,'

    grep -q '/bin/rm' src/shared-data-manager.c
    sed -i src/shared-data-manager.c \
      -e 's,/bin/rm,/run/current-system/sw/bin/rm,'
  '';

  nativeBuildInputs = [
    gettext
    intltool
    itstool
    libxml2
    perl
    vala
  ];

  buildInputs = [
    audit_lib
    glib
    gobject-introspection
    libgcrypt
    libx11
    libxcb
    libxdmcp
    libxklavier
    pam
  ];

  configureFlags = [
    "--localstatedir=/var"
    "--sysconfdir=/etc"
    "--enable-introspection"
    "--enable-vala"
    "--enable-libaudit"
    "--disable-tests"
  ];

  preInstall = ''
    installFlagsArray+=(
      "sysconfdir=$out/etc"
      "localstatedir=$TMPDIr"
    )
  '';

  meta = with lib; {
    description = "Cross-desktop display manager";
    homepage = https://github.com/CanonicalLtd/lightdm;
    license = licenses.gpl3;
    maintainers = with maintainers; [
      codyopel
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
