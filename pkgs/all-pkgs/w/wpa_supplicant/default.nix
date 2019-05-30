{ stdenv
, fetchurl
, writeText

, dbus
, libnl
, ncurses
, openssl
, pcsc-lite_lib
, readline
}:

let
  version = "2.7";

  inherit (stdenv.lib)
    optionals
    optionalString
    versionAtLeast;

  # TODO: Patch epoll so that the dbus actually responds
  # TODO: Figure out how to get privsep working, currently getting SIGBUS
  extraConfigFile = writeText "wpa_supplicant-config" (''
    CONFIG_DRIVER_NL80211_QCA=y
    CONFIG_DRIVER_MACSEC_QCA=y
    CONFIG_DRIVER_MACSEC_LINUX=y
    CONFIG_DRIVER_ROBOSWITCH=y
    CONFIG_LIBNL32=y
    CONFIG_EAP_FAST=y
    CONFIG_EAP_PWD=y
    CONFIG_EAP_PAX=y
    CONFIG_EAP_SAKE=y
    CONFIG_EAP_GPSK=y
    CONFIG_EAP_GPSK_SHA256=y
    CONFIG_WPS=y
    CONFIG_WPS_ER=y
    CONFIG_WPS_NFS=y
    CONFIG_EAP_IKEV2=y
    CONFIG_EAP_EKE=y
    CONFIG_MACSEC=y
    CONFIG_HT_OVERRIDES=y
    CONFIG_VHT_OVERRIDES=y
    CONFIG_ELOOP=eloop
    CONFIG_ELOOP_EPOLL=y
    CONFIG_L2_PACKET=linux
    CONFIG_IEEE80211W=y
    CONFIG_TLS=openssl
    CONFIG_TLSV11=y
    CONFIG_TLSV12=y
    CONFIG_IEEE80211R=y
    CONFIG_DEBUG_SYSLOG=y
    CONFIG_PRIVSEP=y
    CONFIG_IEEE80211N=y
    CONFIG_IEEE80211AC=y
    CONFIG_INTERNETWORKING=y
    CONFIG_HS20=y
    CONFIG_MATCH_IFACE=y
    CONFIG_AP=y
    CONFIG_P2P=y
    CONFIG_TDLS=y
    CONFIG_FST=y
    CONFIG_ACS=y
    CONFIG_MBO=y
    CONFIG_IBSS_RSN=y
    CONFIG_MESH=y
    CONFIG_BGSCAN_SIMPLE=y
  '' + optionalString (pcsc-lite_lib != null) ''
    CONFIG_EAP_SIM=y
    CONFIG_EAP_AKA=y
    CONFIG_EAP_AKA_PRIME=y
    CONFIG_PCSC=y
  '' + optionalString (dbus != null) ''
    CONFIG_CTRL_IFACE_DBUS=y
    CONFIG_CTRL_IFACE_DBUS_NEW=y
    CONFIG_CTRL_IFACE_DBUS_INTRO=y
  '' + (if readline != null then ''
    CONFIG_READLINE=y
  '' else ''
    CONFIG_WPA_CLI_EDIT=y
  ''));

in
stdenv.mkDerivation rec {
  name = "wpa_supplicant-${version}";

  src = fetchurl {
    url = "https://w1.fi/releases/${name}.tar.gz";
    multihash = "QmZQbChZoTgj2nFQcVTMQVrrZLFWhYeizRdqdxkScrSvGo";
    hashOutput = false;
    sha256 = "76ea6b06b7a2ea8e6d9eb1a9166166f1656e6d48c7508914f592100c95c73074";
  };

  buildInputs = [
    dbus
    libnl
    ncurses
    openssl
    pcsc-lite_lib
    readline
  ];

  preBuild = ''
    cd wpa_supplicant
    cp -v defconfig .config
    cat '${extraConfigFile}' >> .config
    cat -n .config

    sed -i "s,/usr/local,$out,g" Makefile

    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE \
      -I$(echo "${libnl}"/include/libnl*/) \
      -I${pcsc-lite_lib}/include/PCSC/"
  '';

  postInstall = ''
    mkdir -p $out/share/man/man5 $out/share/man/man8
    cp -v "doc/docbook/"*.5 $out/share/man/man5/
    cp -v "doc/docbook/"*.8 $out/share/man/man8/
    mkdir -p $out/etc/dbus-1/system.d $out/share/dbus-1/system-services $out/etc/systemd/system
    cp -v "dbus/"*service $out/share/dbus-1/system-services
    sed -e "s@/sbin/wpa_supplicant@$out&@" -i "$out/share/dbus-1/system-services/"*
    cp -v dbus/dbus-wpa_supplicant.conf $out/etc/dbus-1/system.d
    cp -v "systemd/"*.service $out/etc/systemd/system
    rm $out/share/man/man8/wpa_priv.8
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") src.urls;
        pgpKeyFingerprint = "EC4A A0A9 91A5 F246 4582  D52D 2B6E F432 EFC8 95FA";
      };
    };
  };

  meta = with stdenv.lib; {
    homepage = http://hostap.epitest.fi/wpa_supplicant/;
    description = "A tool for connecting to WPA and WPA2-protected wireless networks";
    license = licenses.bsd3;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
