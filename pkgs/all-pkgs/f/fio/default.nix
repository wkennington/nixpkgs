{ stdenv
, bison
, fetchFromGitHub
, flex

, ceph
, glusterfs
, libaio
, numactl
, rdma-core
, zlib
}:

stdenv.mkDerivation rec {
  name = "fio-3.8";

  src = fetchFromGitHub {
    version = 6;
    owner = "axboe";
    repo = "fio";
    rev = name;
    sha256 = "43a346ba01923abbb7b4402b42be8b562113cd43213471dd5e6674e7d57081a6";
  };

  nativeBuildInputs = [
    bison
    flex
  ];

  buildInputs = [
    ceph
    glusterfs
    libaio
    numactl
    rdma-core
    zlib
  ];

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
