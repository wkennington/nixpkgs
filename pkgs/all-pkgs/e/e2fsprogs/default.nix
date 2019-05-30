{ stdenv
, fetchurl

, fuse_2
, systemd-dummy
, util-linux_lib
}:

let
  version = "1.45.2";
in
stdenv.mkDerivation rec {
  name = "e2fsprogs-${version}";

  src = fetchurl {
    url = "mirror://sourceforge/e2fsprogs/e2fsprogs/v${version}/${name}.tar.gz";
    hashOutput = false;
    sha256 = "ee69a57e8499814b07b7f72ff6bc4a41c51d729db5bbbc25dcc66888c497287e";
  };

  buildInputs = [
    fuse_2
    systemd-dummy
    util-linux_lib
  ];

  configureFlags = [
    "--enable-symlink-install"
    "--enable-relative-symlinks"
    "--enable-elf-shlibs"
    "--disable-profile"
    "--disable-gcov"
    "--enable-hardening"
    "--disable-jbd-debug"
    "--disable-blkid-debug"
    "--disable-testio-debug"
    "--disable-libuuid"
    "--disable-libblkid"
    "--disable-backtrace"
    "--enable-debugfs"
    "--enable-imager"
    "--enable-resizer"
    "--enable-defrag"
    "--enable-fsck"
    "--disable-e2initrd-helper"
    "--enable-tls"
    "--disable-uuidd"  # Broken in 1.44.0
    "--enable-mmp"
    "--enable-tdb"
    "--enable-bmap-stats"
    "--enable-bmap-stats-ops"
    "--enable-fuse2fs"
    "--enable-lto"
  ];

  installTargets = [
    "install"
    "install-libs"
  ];

  postInstall = ''
    find "$out"/lib -name '*'.a -delete
  '';

  # Parallel install is broken
  installParallel = false;

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") src.urls;
        pgpKeyFingerprint = "3AB0 57B7 E78D 945C 8C55  91FB D36F 769B C118 04F0";
      };
    };
  };

  meta = with stdenv.lib; {
    description = "Tools for creating and checking ext2/ext3/ext4 filesystems";
    homepage = http://e2fsprogs.sourceforge.net/;
    license = licenses.gpl2;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
