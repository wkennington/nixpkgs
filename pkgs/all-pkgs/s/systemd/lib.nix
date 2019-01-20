{ stdenv
, fetchFromGitHub
, gnum4
, gperf
, meson
, ninja
, python3

, audit_lib
, libcap
, libgcrypt
, libgpg-error
, libidn2
, libselinux
, lz4
, util-linux_lib
, xz
}:

let
  # This is intentionally a separate version from the full build
  # in case we don't have any library changes
  version = "v242-19-gdb2e367bfc";
  rev = "db2e367bfc3b119609f837eb973d915f6c550b2f";
in
stdenv.mkDerivation {
  name = "libsystemd-${version}";

  src = fetchFromGitHub {
    version = 6;
    owner = "systemd";
    repo = "systemd-stable";
    inherit rev;
    sha256 = "632fbbb8f450542c4c7918ab0c3e929c5868f0adb8633b7b31af48cda3e194db";
  };

  nativeBuildInputs = [
    gnum4
    gperf
    meson
    ninja
    python3
  ];

  buildInputs = [
    audit_lib
    libcap
    libgcrypt
    libgpg-error
    libidn2
    libselinux
    lz4
    util-linux_lib
    xz
  ];

  postPatch = ''
    patchShebangs tools/generate-gperfs.py

    # Remove unused subdirs and everything after src/udev
    # which in this case happens to be src/network
    sed \
      -e '\#^subdir(.po#d' \
      -e '\#^subdir(.catalog#d' \
      -e '\#^subdir(.src/login#d' \
      -e '\#^subdir(.src/network#,$d' \
      -i meson.build

    # Remove udev binaries that aren't used, all use libudev_core
    sed -i '\#^libudev_core_includes#,$d' src/udev/meson.build
  '';

  mesonFlags = [
    "-Drootprefix=/run/current-system/sw"
  ];

  preInstall = ''
    export DESTDIR="$out"
  '';

  # We need to work around install locations with the root
  # prefix and dest dir
  postInstall = ''
    dir="$out$out"
    cp -ar "$dir"/* "$out"
    while [ "$dir" != "$out" ]; do
      rm -r "$dir"
      dir="$(dirname "$dir")"
    done
    cp -ar "$out"/run/current-system/sw/* "$out"
    rm -r "$out"/{etc,run,share,var}
  '';

  # Make sure we don't have superfluous libs
  preFixup = ''
    find "$out"/lib -mindepth 1 \( -type d -and -not -name pkgconfig \) -prune -exec rm -r {} \;
  '';

  meta = with stdenv.lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
