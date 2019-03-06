{ stdenv
, bison
, fetchurl
, flex
, perl
, python3
}:

rec {
  name = "qemu-3.1.0";

  src = fetchurl {
    url = "http://wiki.qemu-project.org/download/${name}.tar.bz2";
    multihash = "QmUNAfRNAsQm5DZQKsDVSytkeKC1GFUjVU5S3Hqxn3Njz3";
    hashOutput = false;
    sha256 = "98fee0c86b299ebaf08587ba8df1dc8bb7152708d62937a0631875d95cc8d921";
  };

  nativeBuildInputs = [
    bison
    flex
    perl  # pod2man for man pages
    python3  # Required by configure
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    "--disable-blobs"
  ];

  preInstall = ''
    installFlagsArray+=(
      "sysconfdir=$out/etc"
      "qemu_confdir=$out/etc/qemu"
      "qemu_localstatedir=$TMPDIR"
    )
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.sig") src.urls;
        pgpKeyFingerprint = "CEAC C9E1 5534 EBAB B82D  3FA0 3353 C9CE F108 B584";
      };
    };
  };

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
