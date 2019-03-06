{ stdenv
, docbook_xml_dtd_42
, docbook-xsl
, fetchurl
, gettext
, lib
, libxslt
, meson
, ninja
, python3
, vala

, bash-completion
, dbus-dummy
, glib
}:

let
  channel = "0.30";
  version = "${channel}.1";
in
stdenv.mkDerivation rec {
  name = "dconf-${version}";

  src = fetchurl {
    url = "mirror://gnome/sources/dconf/${channel}/${name}.tar.xz";
    hashOutput = false;
    sha256 = "549a3a7cc3881318107dc48a7b02ee8f88c9127acaf2d47f7724f78a8f6d02b7";
  };

  nativeBuildInputs = [
    docbook_xml_dtd_42
    docbook-xsl
    meson
    ninja
    libxslt
    python3
    vala
  ];

  buildInputs = [
    bash-completion
    dbus-dummy
    glib
  ];

  postPatch = ''
    chmod +x meson_post_install.py
    patchShebangs meson_post_install.py
  '';

  setVapidirInstallFlag = false;

  passthru = {
    srcVerification = fetchurl {
      inherit (src)
        outputHash
        outputHashAlgo
        urls;
      failEarly = true;
      fullOpts = {
        sha256Url = "https://download.gnome.org/sources/dconf/${channel}/"
          + "${name}.sha256sum";
      };
    };
  };

  meta = with lib; {
    description = "Simple low-level configuration system";
    homepage = https://wiki.gnome.org/dconf;
    license = licenses.lgpl21Plus;
    maintainers = with maintainers; [
      codyopel
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
