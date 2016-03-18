{ stdenv
, cmake
, ensureNewerSourcesHook
, fetchgit
, fetchTritonPatch
, ninja
, pythonPackages
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
, libibverbs
, librdmacm
, linux-headers
, lz4
, nss
, nspr
, openssl
, rocksdb
, snappy
, systemd_lib
, util-linux_lib
, xfsprogs_lib
, zfs
, zlib

, channel ? "dev"
}:

let
  inherit ((import ./sources.nix).${channel})
    version
    rev
    sha256;
in
stdenv.mkDerivation {
  name="ceph-${version}";

  src = fetchgit {
    url = "https://github.com/ceph/ceph.git";
    inherit rev sha256;
  };

  nativeBuildInputs = [
    cmake
    (ensureNewerSourcesHook { year = "1980"; })
    ninja
    pythonPackages.cython
    pythonPackages.python
    pythonPackages.setuptools
    pythonPackages.argparse
    pythonPackages.sphinx # Used for docs
    pythonPackages.wrapPython
    yasm
  ];

  buildInputs = [
    boost
    libatomic_ops
    jemalloc
    gperftools
    pythonPackages.flask
    zlib
    bzip2
    linux-headers
    nss
    nspr
    openssl
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
    accelio
    libibverbs
    librdmacm
    lz4
  ];

  patches = [
    (fetchTritonPatch {
      rev = "addbd257dede61a9a7b400d6c06cd1960603d2be";
      file = "ceph/cmake-add-zfs.patch";
      sha256 = "cacb11da90ccef99c278bac5912d09ed4f3d688bc6a445d990ccc930ae7c49da";
    })
    ../../../../triton-patches/ceph/ninja-fix.patch
  ];

  postPatch = ''
    # Make sure we generate a failure for all find_package calls that fail
    while read file; do
      sed -i 's,\(find_package([^ ]*\)),\1 REQUIRED),g' "$file"
    done < <(find . -name CMakeLists.txt -or -name \*.cmake)

    sed -i 's,\$(MAKE),make,g' src/CMakeLists.txt

    sed \
      -e 's,@CEPH_GIT_NICE_VER@,${version},g' \
      -e 's,@CEPH_GIT_VER@,no_version,g' \
      -i src/ceph_ver.h.in.cmake src/ceph.in
  '';

  cmakeFlags = [
    "-DENABLE_GIT_VERSION=OFF"
    "-DALLOCATOR=jemalloc"
    "-DEXECINFO_INCLUDE_DIR=${stdenv.libc}/include"
    "-DEXECINFO_LIBRARY=${stdenv.libc}/lib/libc.so"
    "-DXFS_INCLUDE_DIR=${xfsprogs_lib}/include"
    "-DGPERFTOOLS_INCLUDE_DIR=${gperftools}/include"
    "-DKEYUTILS_INCLUDE_DIR=${keyutils}/include"
    "-DUUID_INCLUDE_DIR=${util-linux_lib}/include/uuid"
    "-DCURL_INCLUDE_DIR=${curl}/include"
  ];

  # Ninja doesn't like building external dependencies
  preBuild = ''
    cp ${rocksdb}/lib/librocksdb.a ../src/rocksdb/librocksdb.a
  '';

  preFixup = ''
    # Wrap all of the python scripts
    wrapPythonPrograms $out/bin
  '';

  optimize = false;
  fortifySource = false;

  meta = with stdenv.lib; {
    homepage = http://ceph.com/;
    description = "Distributed storage system";
    license = licenses.lgpl21;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
