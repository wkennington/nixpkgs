{ stdenv
, autoconf
, automake
, ensureNewerSourcesHook
, fetchgit
, fetchTritonPatch
, git
, libtool
, pythonPackages
, which
, yasm

, accelio
, boost
, bzip2
, curl
, expat
, fcgi
, fuse
, gperftools
, jemalloc
, keyutils
, leveldb
, libaio
, libatomic_ops
, libedit
, libibverbs
, librdmacm
, libs3
, libxml2
, linux-headers
, lz4
, nss
, nspr
, openldap
, openssl
, rocksdb
, snappy
, systemd_lib
, util-linux_lib
, xfsprogs_lib
, zfs
, zlib

, channel ? "10"
}:

let
  inherit (stdenv.lib)
    optionals
    optionalString
    versionAtLeast
    versionOlder;

  inherit ((import ./sources.nix).${channel})
    version
    rev
    sha256;

  hasXio = versionAtLeast version "9.0.3";

  hasRocksdb = versionAtLeast version "9.0.0" && !hasStaticRocksdb;

  hasStaticRocksdb = versionAtLeast version "10.0.1";

  # Malloc implementation (can be jemalloc or tcmalloc)
  malloc = if versionAtLeast version "10.0.4" || !hasStaticRocksdb then jemalloc else gperftools;
in

stdenv.mkDerivation rec {
  name="ceph-${version}";

  src = fetchgit {
    url = "https://github.com/ceph/ceph.git";
    inherit rev sha256;
  };

  patches = [
    (fetchTritonPatch {
      rev = "3e20a6c39775b724eff44af93f08b38205be1f5b";
      file = "ceph/0001-Makefile-env-Don-t-force-sbin.patch";
      sha256 = "025agxpjkp5dj1fpx2ln0j9s43wklzgld6v6zk3vmgs0l4q138g0";
    })
  ] ++ optionals (versionOlder version "9.0.0") [
    (fetchTritonPatch {
      rev = "3e20a6c39775b724eff44af93f08b38205be1f5b";
      file = "ceph/fix-pgrefdebugging.patch";
      sha256 = "11xn226mlzh6c13j9h1xavr9pnnfvkykkxzmf7c0w7hqm3w8r0gs";
    })
  ] ++ optionals (versionAtLeast version "9.0.0" && versionOlder version "10.0.0") [
    #./fix-sphinx.patch
    (fetchTritonPatch {
      rev = "3e20a6c39775b724eff44af93f08b38205be1f5b";
      file = "ceph/fix-pythonpath.patch";
      sha256 = "1chf2n7rac07kvvbrs00vq2nkv31v3l6lqdlqpq09wgcbin2qpkk";
    })
  ] ++ optionals (versionAtLeast version "10.0.0") [
    (fetchTritonPatch {
      rev = "a8e11633b115050e9d0ea558d6480ed1d5fe9eeb";
      file = "ceph/fix-pythonpath.patch";
      sha256 = "0iq52pa4i0nldm5mmm8bshbpzbmrjndswa1cysglcmv2ncbvmyzz";
    })
  ];

  nativeBuildInputs = [
    autoconf
    automake
    (ensureNewerSourcesHook { year = "1980"; })
    git
    libtool
    pythonPackages.python
    pythonPackages.wrapPython
    which
    yasm
  ] ++ optionals (versionAtLeast version "9.0.2") [
    pythonPackages.argparse
    pythonPackages.setuptools
    #pythonPackages.sphinx # Used for docs
  ] ++ optionals (versionAtLeast version "10.0.2") [
    pythonPackages.cython
  ];

  pythonPath = [
    pythonPackages.flask
    pythonPackages.itsdangerous
    pythonPackages.jinja2
    pythonPackages.werkzeug
  ];

  buildInputs = pythonPath ++ [
    boost
    libxml2
    libatomic_ops
    malloc
    zlib
    bzip2
    linux-headers
    nss
    nspr
    util-linux_lib
    systemd_lib
    keyutils
    libaio
    xfsprogs_lib
    zfs
    snappy
    leveldb
    fcgi
    expat
    curl
    fuse
  ] ++ optionals (versionOlder version "10.0.4") [
    libedit
  ] ++ optionals (versionAtLeast version "10.0.0") [
    lz4
  ] ++ optionals hasXio [
    accelio
    libibverbs
    librdmacm
  ] ++ optionals hasRocksdb [
    rocksdb
  ] ++ optionals (versionOlder version "9.1.0") [
    libs3
  ] ++ optionals (versionAtLeast version "10.1.0") [
    openldap
    openssl
  ];

  postPatch = ''
    patchShebangs .

    # Fix zfs pkgconfig detection
    sed -i 's,\[zfs\],\[libzfs\],g' configure.ac

    # Fix GNU_SOURCE
    sed -i '/AC_INIT/aAC_GNU_SOURCE' configure.ac
  '' + optionalString (versionAtLeast version "10.1.0") ''
    # Fix LDAP linking
    ! grep '\(-lldap\|LDAP_LIB\)' src/rgw/Makefile.am
    sed -i 's,LIBRGW_DEPS +=,\0 -lldap,g' src/rgw/Makefile.am

    # Remove anything that depends on virtualenv
    sed -i '/include ceph-\(disk\|detect-init\)/d' src/Makefile.am
  '';

  preConfigure = ''
    # Ceph expects the arch command to be usable during configure
    # for detecting the assembly type
    mkdir -p mybin
    echo "#${stdenv.shell} -e" >> mybin/arch
    echo "uname -m" >> mybin/arch
    chmod +x mybin/arch
    PATH="$PATH:$(pwd)/mybin"

    ./autogen.sh

    # Fix the python site-packages install directory
    sed -i "s,\(PYTHON\(\|_EXEC\)_PREFIX=\).*,\1'$lib',g" configure

    # Fix the PYTHONPATH for installing ceph-detect-init to $out
    mkdir -p "$(toPythonPath $out)"
    export PYTHONPATH="$(toPythonPath $out):$PYTHONPATH"
  '';

  configureFlags = [
    "--disable-silent-rules"
    "--exec_prefix=\${out}"
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    "--libdir=\${lib}/lib"
    "--includedir=\${lib}/include"
    "--with-rbd"
    "--with-cephfs"
    "--with-radosgw"
    "--with-radosstriper"
    "--with-mon"
    "--with-osd"
    "--with-mds"
    "--enable-client"
    "--enable-server"
    "--without-cryptopp"
    "--with-nss"
    "--disable-root-make-check"
    "--without-profiler"
    "--without-debug"
    "--disable-coverage"
    "--with-fuse"
    "--${if malloc == jemalloc then "with" else "without"}-jemalloc"
    "--${if malloc == gperftools then "with" else "without"}-tcmalloc"
    "--disable-pgrefdebugging"
    "--disable-cephfs-java"
    "--${if hasXio then "enable" else "disable"}-xio"
    "--with-libatomic-ops"
    "--with-ocf"
    "--without-kinetic"
    "--${if hasRocksdb then "with" else "without"}-librocksdb"
    "--${if hasStaticRocksdb then "with" else "without"}-librocksdb-static"
    "--with-libaio"
    "--with-libxfs"
    "--with-libzfs"
  ] ++ optionals (versionAtLeast version "0.94.3") [
    "--without-tcmalloc-minimal"
  ] ++ optionals (versionAtLeast version "9.0.1") [
    "--without-valgrind"
  ] ++ optionals (versionAtLeast version "9.0.2") [
    "--without-man-pages"  # TODO(wkennington): Fix
  ] ++ optionals (versionAtLeast version "9.0.2" && versionOlder version "10.0.4") [
    "--with-systemd-libexec-dir=\${out}/libexec"
  ] ++ optionals (versionOlder version "9.1.0") [
    "--with-system-libs3"
    "--with-rest-bench"
  ] ++ optionals (versionAtLeast version "9.1.0") [
    "--with-systemd-unit-dir=\${out}/etc/systemd/system"
    "--without-selinux"  # TODO: Implement
  ] ++ optionals (versionAtLeast version "9.1.0" && versionOlder version "10.0.4") [
    "--with-rgw-user=rgw"
    "--with-rgw-group=rgw"
  ] ++ optionals (versionAtLeast version "10.0.2") [
    "--with-cython"
  ] ++ optionals (versionAtLeast version "10.0.4") [
    "--with-eventfd"
    "--without-spdk" # TODO: Implement
  ] ++ optionals (versionAtLeast version "10.1.0") [
    "--enable-subman"
    "--with-openldap"
  ];

  preBuild = optionalString (versionAtLeast version "9.0.0") ''
    (cd src/gmock; make -j $NIX_BUILD_CORES)
  '';

  installFlags = [
    "sysconfdir=\${out}/etc"
  ];

  outputs = [ "out" "lib" ];

  postInstall = ''
    wrapPythonPrograms $out/bin

    # Bring in lib as a native build input
    mkdir -p $out/nix-support
    echo "$lib" > $out/nix-support/propagated-native-build-inputs

    # Fix the python library loading
    find $lib/lib -name \*.pyc -or -name \*.pyd -exec rm {} \;
    for PY in $(find $lib/lib -name \*.py); do
      LIBS="$(sed -n "s/.*find_library('\([^)]*\)').*/\1/p" "$PY")"

      # Delete any calls to find_library
      sed -i '/find_library/d' "$PY"

      # Fix each find_library call
      for LIB in $LIBS; do
        REALLIB="$lib/lib/lib$LIB.so"
        sed -i "s,\(lib$LIB = CDLL(\).*,\1'$REALLIB'),g" "$PY"
      done

      # Reapply compilation optimizations
      NAME=$(basename -s .py "$PY")
      rm -f "$PY"{c,o}
      pushd "$(dirname $PY)"
      python -c "import $NAME"
      python -O -c "import $NAME"
      popd
      test -f "$PY"c
      test -f "$PY"o
    done
  '';

  meta = with stdenv.lib; {
    description = "Distributed storage system";
    homepage = https://ceph.com/;
    license = licenses.lgpl21;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };

  passthru.version = version;
}
