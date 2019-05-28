{ stdenv
, lib

, brotli_1-0-3
, gnutar_1-30
, xz_5-2-4

, version ? 6
}:

let
  versions = {
    "6" = {
      brotli = brotli_1-0-3;
      tar = gnutar_1-30;
      xz = xz_5-2-4;
    };
  };

  pkgs = versions."${toString version}";

  inherit (lib)
    concatStringsSep;

  tarCmd = concatStringsSep " " [
    "${pkgs.tar}/bin/tar"
    "--sort=name"
    "--owner=0"
    "--group=0"
    "--numeric-owner"
    "--no-acls"
    "--no-selinux"
    "--no-xattrs"
    "--mode=go=rX,u+rw,a-s"
    "--clamp-mtime"
    "--mtime=@\${SOURCE_DATE_EPOCH:-1}"
    "-c"
    "\"$@\""
  ];

  brotliCmd = concatStringsSep " " [
    "${pkgs.brotli}/bin/brotli"
    "-6"
    "-c"
  ];

  zstdCmd = concatStringsSep " " [
    "${pkgs.zstd}/bin/zstd"
    "-9"
    "-c"
  ];

  fastCmd =
    if pkgs ? zstd then
      zstdCmd
    else
      brotliCmd;

  xzCmd = concatStringsSep " " [
    "${pkgs.xz}/bin/xz"
    "-9"
    "-e"
    "-c"
  ];

  slowCmd = xzCmd;
in
stdenv.mkDerivation {
  name = "deterministic-zip-${toString version}";

  buildCommand = ''
    mkdir -p "$out"/bin

    echo '#! ${stdenv.shell} -e' >>"$out"/bin/deterministic-zip-${toString version}
    echo '${tarCmd} | ${fastCmd}' >>"$out"/bin/deterministic-zip-${toString version}
    chmod +x "$out"/bin/deterministic-zip-${toString version}
    ln -sv deterministic-zip-${toString version} "$out"/bin/deterministic-zip

    echo '#! ${stdenv.shell} -e' >>"$out"/bin/deterministic-zip-dist-${toString version}
    echo '${tarCmd} | ${slowCmd}' >>"$out"/bin/deterministic-zip-dist-${toString version}
    chmod +x "$out"/bin/deterministic-zip-dist-${toString version}
    ln -sv deterministic-zip-dist-${toString version} "$out"/bin/deterministic-zip-dist
  '';

  passthru = pkgs // {
    fastExt = if pkgs ? zstd then "zst" else "br";
    slowExt = "xz";
  };

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    priority = -version;
  };
}
