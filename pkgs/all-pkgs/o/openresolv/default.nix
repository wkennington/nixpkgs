{ stdenv
, fetchurl
, makeWrapper

, coreutils
}:

stdenv.mkDerivation rec {
  name = "openresolv-3.9.0";

  src = fetchurl {
    url = "mirror://roy/openresolv/${name}.tar.xz";
    multihash = "QmXDub6YQT57hbvVh1tscQavrUnQpHbmzSYf4Pt72Bk7Pv";
    sha256 = "51a04d39232bb797c9efeaad51a525cf50a1deefcb19a1ea5dd3475118634db8";
  };

  nativeBuildInputs = [
    makeWrapper
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
  ];

  postPatch = ''
    sed -i "1aexport PS4='+(\''${LINENO}): \''${FUNCNAME[0]:+\''${FUNCNAME[0]}(): }'" resolvconf.in
    sed -i '1aset -x' resolvconf.in
  '';

  preInstall = ''
    installFlagsArray+=("SYSCONFDIR=$out/etc")
  '';

  preFixup = ''
    # Scripts calls rm, cat & other executables
    wrapProgram "$out/sbin/resolvconf" \
      --prefix PATH : "${coreutils}/bin"
  '';

  meta = with stdenv.lib; {
    description = "A program to manage /etc/resolv.conf";
    homepage = http://roy.marples.name/projects/openresolv;
    license = licenses.bsd2;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
