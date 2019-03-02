{ stdenv
, docbook_xml_dtd_42
, docbook_xml_dtd_45
, docbook-xsl
, fetchFromGitHub
, gettext
, gnum4
, gperf
, libxslt
, meson
, ninja
, python3

, acl
, audit_lib
, bash-completion
, bzip2
, cryptsetup
, curl
, elfutils
, gnu-efi
, gnutls
, iptables
, kmod
, libcap
, libgcrypt
, libgpg-error
, libidn2
, libmicrohttpd
, libseccomp
, libselinux
, libxkbcommon
, linux-headers_triton
, lz4
, pam
, pcre2_lib
, qrencode
, systemd_lib
, util-linux_lib
, xz
, zlib
}:

let
  elfutils_libs = stdenv.mkDerivation {
    name = "elfutils-libs-${elfutils.version}";

    buildCommand = ''
      mkdir -p $out
      ln -sv ${elfutils}/{lib,include} $out
    '';
  };

  version = "v242-19-gdb2e367bfc";
  rev = "db2e367bfc3b119609f837eb973d915f6c550b2f";
in
stdenv.mkDerivation {
  name = "systemd-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "systemd";
    repo = "systemd-stable";
    inherit rev;
    sha256 = "632fbbb8f450542c4c7918ab0c3e929c5868f0adb8633b7b31af48cda3e194db";
  };

  nativeBuildInputs = [
    docbook_xml_dtd_42
    docbook_xml_dtd_45
    docbook-xsl
    gettext
    gnum4
    gperf
    libxslt
    meson
    ninja
    python3
  ];

  buildInputs = [
    acl
    audit_lib
    bash-completion
    bzip2
    cryptsetup
    curl
    elfutils_libs
    gnu-efi
    gnutls
    iptables
    kmod
    libcap
    libgcrypt
    libgpg-error
    libidn2
    libmicrohttpd
    libseccomp
    libselinux
    libxkbcommon
    linux-headers_triton
    lz4
    pam
    pcre2_lib
    qrencode
    util-linux_lib
    xz
    zlib
  ];

  NIX_LDFLAGS = "-rpath ${systemd_lib}/lib";

  postPatch = ''
    patchShebangs tools
    patchShebangs src/resolve/generate-dns_type-gperf.py
  '';

  mesonFlags = [
    "-Dversion-tag=${version}"
    "-Drootprefix=/run/current-system/sw"
    "-Dquotaon-path=/run/current-system/sw/bin/quotaon"
    "-Dquotacheck-path=/run/current-system/sw/bin/quotacheck"
    "-Dkmod-path=/run/current-system/sw/bin/kmod"
    "-Dkexec-path=/run/current-system/sw/bin/kexec"
    "-Dsulogin-path=/run/current-system/sw/bin/sulogin"
    "-Dmount-path=/run/current-system/sw/bin/mount"
    "-Dumount-path=/run/current-system/sw/bin/umount"
    "-Dloadkeys-path=/run/current-system/sw/bin/loadkeys"
    "-Dsetfont-path=/run/current-system/sw/bin/setfont"
    "-Dldconfig=false"
    "-Dfallback-hostname=triton"
    "-Ddefault-hierarchy=unified"
    "-Dsystem-uid-max=1000"
    "-Dsystem-gid-max=1000"
    "-Dtty-gid=3"
    "-Dusers-gid=100"
    "-Ddefault-locale=C.UTF-8"
    "-Ddns-over-tls=gnutls"
    "-Dlibidn2=true"
    "-Defi-includedir=${gnu-efi}/include/efi"
    "-Defi-libdir=${gnu-efi}/lib"
    "-Dtests=false"
  ];

  preInstall = ''
    export DESTDIR="$out"
  '';

  # We need to work around install locations with the root
  # prefix and dest dir
  postInstall = ''
    dir="$out$out"
    cp -ar "$dir"/* "$out"
    while [ "$dir" != "$out" ]; do
      rm -r "$dir"
      dir="$(dirname "$dir")"
    done
    cp -ar "$out"/run/current-system/sw/* "$out"
    rm -r "$out"/{run,var}
  '';

  preFixup = ''
    # Remove anything from systemd_lib
    pushd '${systemd_lib}' >/dev/null
    find . -not -type d -exec rm -v "$out"/{} \;
    popd >/dev/null
  '';

  meta = with stdenv.lib; {
    homepage = "http://www.freedesktop.org/wiki/Software/systemd";
    description = "A system and service manager for Linux";
    licenses = licenses.gpl2;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
