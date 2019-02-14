{ stdenv
, cmake
, fetchurl
, protobuf-cpp
, python3Packages
, yasm

, boost
, c-ares
, cryptopp
, curl
, expat
, fcgi
, fuse_2
, gnutls
, gperf
, jemalloc
, keyutils
, krb5_lib
, leveldb
, libaio
, liboath
, lz4
, nspr
, nss
, openldap
, openssl
, parted
, rdma-core
, rocksdb
, snappy
, systemd_lib
, util-linux_lib
, xfsprogs_lib
, zlib
, zstd

, channel
}:

let
  inherit (stdenv.lib)
    concatMapStrings
    head
    replaceChars;

  sources = (import ./sources.nix)."${channel}";

  inherit (sources)
    version;

  src = fetchurl {
    url = "https://github.com/wkennington/ceph/releases/download/${version}/ceph-${version}.tar.xz";
    inherit (sources) sha256;
  };

  cephDisk = python3Packages.buildPythonPackage {
    name = "ceph-disk-${version}";

    inherit src;

    pythonPath = [
      parted
    ];

    prePatch = ''
      cd src/ceph-disk
    '';

    postPatch = ''
      sed -i 's,/bin/\(u\|\)mount,\1mount,g' ceph_disk/main.py
      sed -i 's,/sbin/blkid,blkid,g' ceph_disk/main.py
    '';
  };

  cephVolume = python3Packages.buildPythonPackage {
    name = "ceph-volume-${version}";

    inherit src;

    prePatch = ''
      cd src/ceph-volume
    '';

    postPatch = ''
      grep -q 'locations = (' ceph_volume/util/system.py
      sed -i "/locations = (/a\        '/run/current-system/sw/bin'," ceph_volume/util/system.py
    '';
  };

  boosts = [
    boost
    python3Packages.boost
  ];

  boost' = stdenv.mkDerivation {
    name = "ceph-combined-${(head boosts).name}";

    buildCommand = ''
      mkdir -p "$out"
      cp -ans --no-preserve=mode ${concatMapStrings (n: "${n.lib}/lib ") boosts}"$out"
      mkdir -p "$out"/nix-support
      echo '${concatMapStrings (n: "${n.dev} ") boosts}' >"$out"/nix-support/propagated-native-build-inputs
      echo 'NIX_LDFLAGS="${concatMapStrings (n: "-rpath ${n.lib}/lib ") boosts} $NIX_LDFLAGS"' \
        >"$out"/nix-support/setup-hook
    '';
  };
in
stdenv.mkDerivation rec {
  name = "ceph-${version}";

  src = ../../../../../ceph.tar.xz;

  nativeBuildInputs = [
    cmake
    #protobuf-cpp
    python3Packages.sphinx
    python3Packages.cython
    python3Packages.python
    yasm
  ];

  buildInputs = [
    boost'
    #c-ares
    #cryptopp
    curl
    expat
    fuse_2
    #gnutls
    gperf
    jemalloc
    keyutils
    krb5_lib
    leveldb
    libaio
    liboath
    lz4
    nspr
    nss
    openldap
    openssl
    #protobuf-cpp
    rdma-core
    rocksdb
    snappy
    systemd_lib
    util-linux_lib
    xfsprogs_lib
    zlib
  ];

  # Needed by the ceph command line
  pythonPath = [
  ];

  postPatch = ''
    # We manually set the version of ceph directly so we don't have to depend on git
    sed \
      -e 's,GIT-NOTFOUND,${version},g' \
      -e 's,GITDIR-NOTFOUND,${replaceChars ["-" "."] ["" ""] version},g' \
      -i cmake/modules/GetGitRevisionDescription.cmake

    # Use up to date zstd sources
    unpackFile '${zstd.src}'
    mv zstd-* src/zstd
  '';

  preConfigure = ''
    cmakeFlagsArray+=(
      "-DCMAKE_INSTALL_INCLUDEDIR=$lib/include"
      "-DCMAKE_INSTALL_LIBDIR=$lib/lib"
    )
  '';

  cmakeFlags = [
    "-DWITH_GSSAPI=ON"
    "-DWITH_SPDK=OFF"
    "-DWITH_BLUEFS=ON"
    "-DWITH_LTTNG=OFF"
    "-DWITH_BABELTRACE=OFF"
    "-DWITH_RADOSGW_AMQP_ENDPOINT=OFF"
    "-DDEBUG_GATHER=OFF"
    "-DWITH_TESTS=OFF"
    "-DWITH_SYSTEM_ROCKSDB=ON"
    "-DWITH_SEASTAR=OFF"
    "-DWITH_SYSTEM_BOOST=ON"
    "-DWITH_GRAFANA=ON"
    "-DWITH_MGR_DASHBOARD_FRONTEND=OFF"

    "-DWITH_PYTHON3=ON"
  ];

  # Ensure we have the correct rpath already to work around
  # a broken patchelf.
  preBuild = ''
    export NIX_LDFLAGS="$NIX_LDFLAGS -rpath $lib/lib -rpath $(pwd)/lib"
  '';

  postInstall = ''
    # Move python libraries to lib
    mv "$out"/lib/python* "$lib"/lib
    rmdir "$out"/lib

    # Bring in lib as a native build input
    mkdir -p "$out"/nix-support
    echo "$lib" > "$out"/nix-support/propagated-native-build-inputs
  '';

  preFixup = ''
    wrapPythonPrograms "$out"/bin

    # Contain impure absolute paths
    find "$lib" -name SOURCES.txt -delete
  '';
  
  outputs = [
    "out"
    "lib"
  ];

  disallowedReferences = [
    boost'
  ];

  passthru = {
    disk = cephDisk;
    volume = cephVolume;
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
