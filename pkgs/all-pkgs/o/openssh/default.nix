{ stdenv
, fetchTritonPatch
, fetchurl

, audit_lib
, kerberos
, ldns
, libbsd
, libedit
, openssl
, pam
, zlib
}:

stdenv.mkDerivation rec {
  name = "openssh-8.1p1";

  src = fetchurl {
    url = "mirror://openbsd/OpenSSH/portable/${name}.tar.gz";
    hashOutput = false;
    sha256 = "02f5dbef3835d0753556f973cd57b4c19b6b1f6cd24c03445e23ac77ca1b93ff";
  };

  buildInputs = [
    audit_lib
    kerberos
    ldns
    libbsd
    libedit
    openssl
    pam
    zlib
  ];

  patches = [
    (fetchTritonPatch {
      rev = "0adef9010d48cf06dd295edc65d6ffc1c618ba10";
      file = "o/openssh/0001-Pass-LOCALE_ARCHIVE-to-children.patch";
      sha256 = "0dd79faa9cb039c4c34aea5a8307dc0a55464a839ddd7e5f9c5ec5a0c2baec5c";
    })
  ];

  postPatch = ''
    # setuid can't be in a nixbuild
    grep -q 'INSTALL.*-m 4' Makefile.in
    sed -i '/INSTALL/s,-m 4,-m 0,' Makefile.in
  '';

  configureFlags = [
    "--sysconfdir=/etc/ssh"
    "--localstatedir=/var"
    "--with-pid-dir=/run"
    "--with-ldns"
    "--with-libedit"
    "--with-audit=linux"
    "--with-pie"
    "--with-ssl-dir=${openssl}"
    "--with-ssl-engine"
    "--with-pam"
    "--with-kerberos5"
    "--with-mantype=man"
    "--with-privsep-user=nobody"
  ];

  preInstall = ''
    installFlagsArray+=(
      "sysconfdir=$out/etc/ssh"
      "localstatedir=$TMPDIR"
      "PRIVSEP_PATH=$TMPDIR"
    )
  '';

  installTargets = [
    "install-nokeys"
  ];

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit (src)
        urls
        outputHash
        outputHashAlgo;
      fullOpts = {
        pgpsigUrls = map (n: "${n}.asc") src.urls;
        pgpKeyFingerprint = "59C2 118E D206 D927 E667  EBE3 D3E5 F56B 6D92 0D30";
      };
    };
  };

  meta = with stdenv.lib; {
    homepage = "http://www.openssh.org/";
    description = "An implementation of the SSH protocol";
    license = licenses.bsd2;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
