{ stdenv
, fetchFromGitHub
, fetchurl
, lib

, kernel

, onlyHeaders ? false
}:

let
  inherit (lib)
    optionalString;

  version = "1.10";
in
stdenv.mkDerivation rec {
  name = "cryptodev-linux-${version}";

  src = fetchurl {
    name = "cryptodev-linux-${version}.tar.br";
    # Inject the tarball generated by fetchFromGitHub
    multihash = "QmNTdvMaDTzNP11eZh1zcVrRWpPdALaMkRV8VTrVLF6Wj5";
    hashOutput = false;
    sha256 = "7bf74db0e48741659c1f55eac5e429fd53d06dff19daa3e447fe964594d3ada9";
  };

  # If we are only building headers, just do that
  buildCommand = optionalString onlyHeaders ''
    unpackPhase
    install -D -m644 -v */crypto/cryptodev.h "$out"/include/crypto/cryptodev.h
  '';

  preBuild = optionalString (!onlyHeaders) ''
    makeFlagsArray+=(
      "-C" "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "SUBDIRS=$(pwd)"
      "INSTALL_PATH=$out"
    )
    installFlagsArray+=("INSTALL_MOD_PATH=$out")
  '';

  installTargets = [
    "modules_install"
  ];

  passthru = {
    srcVerification =
      let
        version = "1.10";
      in
      fetchFromGitHub {
        version = 6;
        owner = "cryptodev-linux";
        repo = "cryptodev-linux";
        rev = "cryptodev-linux-${version}";
        sha256 = "7bf74db0e48741659c1f55eac5e429fd53d06dff19daa3e447fe964594d3ada9";
      };
  };

  meta = with lib; {
    description = "Device that allows access to Linux kernel cryptographic drivers";
    homepage = http://home.gna.org/cryptodev-linux/;
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux ++
      x86_64-linux ++
      powerpc64le-linux;
  };
}
