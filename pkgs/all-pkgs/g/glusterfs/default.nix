{ stdenv
, automake
, bison
, fetchurl
, flex
, makeWrapper
, python2
, rpcsvc-proto

, acl
, attr
, coreutils_small
, gawk_small
, gnugrep
, gnused_small
, libaio
, libtirpc
, liburcu
, libxml2
, ncurses
, openssl
, rdma-core
, readline
, sqlite
, util-linux_lib
, which
, zlib
}:

let
  inherit (stdenv.lib)
    concatStringsSep;

  mountPath = [
    attr
    coreutils_small
    gawk_small
    gnugrep
    gnused_small
    which
  ];

  versionMajor = "6";
  versionMinor = "1";
  version = "${versionMajor}.${versionMinor}";
in
stdenv.mkDerivation rec {
  name = "glusterfs-${version}";

  src = fetchurl {
    url = "https://download.gluster.org/pub/gluster/glusterfs/${versionMajor}/"
      + "${version}/${name}.tar.gz";
    sha256 = "32ac75c883cdf18e081893ce5210b2331f1ee9ba25e3f3f56136d9878b194dc7";
  };

  nativeBuildInputs = [
    bison
    flex
    makeWrapper
    python2
    rpcsvc-proto
  ];

  buildInputs = [
    acl
    attr
    libaio
    libtirpc
    liburcu
    libxml2
    ncurses
    openssl
    rdma-core
    readline
    sqlite
    util-linux_lib
    zlib
  ];

  postPatch = ''
    # Fix hardcoded python path
    grep -q 'PYTHON=/usr/bin/python2' configure
    sed -i 's,PYTHON=/usr/bin/python2,PYTHON=${python2.interpreter},' configure

    # Glusterfs ships broken config.* files
    cp ${automake}/share/automake*/config.* .

    # Don't chown / setuid anything
    grep -q 'chmod u+s' contrib/fuse-util/Makefile.in
    sed -i '\,\(chown root\|chmod u+s\),d' contrib/fuse-util/Makefile.in

    # Remove hard coded work directory
    grep -q '@GLUSTERD_WORKDIR@' events/Makefile.in
    sed -i '\,@GLUSTERD_WORKDIR@,d' events/Makefile.in
  '';

  preConfigure = ''
    configureFlagsArray+=(
      "--with-systemddir=$out/lib/systemd/system"
      "--with-initdir=$out/etc/init.d"
    )
  '';

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    "--with-ipv6-default"
    "--with-mountutildir=/run/current-system/sw/bin"
  ];

  preInstall = ''
    find . -name Makefile -exec sed -i {} \
      -e "s,^sysconfdir[ ]*=.*,sysconfdir = $out/etc," \
      -e "s,^localstatedir[ ]*=.*,localstatedir = $TMPDIR," \
      -e "s,^mountutildir[ ]*=.*,mountutildir = $out/bin," \
      -e "s,^utildir[ ]*=.*,utildir = $out/bin," \
      -e "s,^GLUSTERD_WORKDIR[ ]*=.*,GLUSTERD_WORKDIR = $TMPDIR," \
      \;
  '';

  preFixup = ''
    # Fix mount.glusterfs
    sed -i '/export PATH/d' "$out"/bin/mount.glusterfs
    wrapProgram "$out"/bin/mount.glusterfs \
      --set PATH "${concatStringsSep ":" (map (n: "${n}/bin") mountPath)}"
  '';

  meta = with stdenv.lib; {
    description = "Distributed storage system";
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
