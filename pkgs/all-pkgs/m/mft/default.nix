{ stdenv
, elfutils
, fetchurl

, kernel
}:

let
  version = "4.11.0-103";

  urls' = arch: [
    "http://www.mellanox.com/downloads/MFT/mft-${version}-${arch}.tgz"
  ];

  sources = {
    "x86_64-linux" = {
      urls = urls' "x86_64-deb";
      md5Confirm = "5b8663ea0048add032cdb3ebc01b5ccc";
      sha256 = "f7f0cf1b333753ccc82f369f5dc5852b5d5e2d31a467d44f227efebdb35a3f3e";
    };
  };

  uarches = {
    "x86_64-linux" = "x86_64";
  };

  inherit (stdenv.lib)
    optionals
    optionalString;

  inherit (sources."${stdenv.targetSystem}")
    urls
    md5Confirm
    sha256;
in
stdenv.mkDerivation rec {
  name = "mft-${version}${optionalString (kernel != null) "-${kernel.version}"}";

  src = fetchurl {
    inherit urls sha256;
    hashOutput = false;
  };

  nativeBuildInputs = optionals (kernel != null) [
    elfutils
  ];

  preBuild = optionalString (kernel != null) ''
    ar vx SDEBS/*
    tar xf data.tar.*

    cd usr/src/*

    makeFlagsArray+=("INSTALL_MOD_PATH=$out")
  '';

  makeFlags = optionals (kernel != null) [
    "KPVER=${kernel.modDirVersion}"
    "KSRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "CPU_ARCH=${uarches."${stdenv.targetSystem}"}"
  ];

  buildPhase = optionalString (kernel == null) ''
    ar vx DEBS/${name}*
    tar xf data.tar.*

    rm usr/bin/mst
    mv etc/init.d/mst usr/bin
    sed \
      -e 's,/sbin/modprobe,modprobe,g' \
      -e 's,/sbin/lsmod,lsmod,g' \
      -e "s,^mbindir=.*,mbindir='$out/bin',g" \
      -i usr/bin/mst
    rmdir etc/init.d

    for file in $(echo usr/bin/*); do
      echo "$(basename "$file"): Checking if ELF" >&2
      if readelf -h "$file" >/dev/null 2>&1; then
        echo "$(basename "$file"): Patching" >&2
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" --set-rpath "${stdenv.cc.cc}/lib" "$file"
      fi
    done
  '';

  installPhase = optionalString (kernel == null) ''
    mkdir -p "$out"
    mv etc usr/{bin,share} "$out"
  '' + optionalString (kernel != null) ''
    modDir="$out/lib/modules/${kernel.modDirVersion}/extra"
    mkdir -p "$modDir"
    for module in $(find . -name \*.ko); do
      xz -9 -c "$module" >"$modDir/$(basename "$module").xz"
    done
  '';

  # Kernel code doesn't support our hardening flags
  optFlags = kernel == null;
  pie = kernel == null;
  fpic = kernel == null;
  noStrictOverflow = kernel == null;
  fortifySource = kernel == null;
  stackProtector = kernel == null;
  optimize = kernel == null;

  # Binaries are broken by this
  dontStrip = true;

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      inherit urls sha256;
      fullOpts.md5Confirm = md5Confirm;
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
