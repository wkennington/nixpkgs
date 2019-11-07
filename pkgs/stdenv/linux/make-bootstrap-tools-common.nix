{ stdenv
, nukeReferences

, bash_small
, busybox_bootstrap
, glibc_lib_gcc
, gcc
, gcc_lib_glibc
, gcc_runtime_glibc
, linux-headers
}:

rec {
  build = stdenv.mkDerivation {
    name = "stdenv-bootstrap-tools";

    nativeBuildInputs = [
      nukeReferences
    ];

    buildCommand = ''
      root="$TMPDIR/root"
      mkdir -pv "$root"/{bin,lib,libexec}

      cp -dv '${glibc_lib_gcc.dev}'/lib/{libc.so,libc_nonshared.a,*.o} "$root"/lib
      cp -dv '${gcc_lib_glibc.dev}'/lib/{libgcc_s.so,libgcc.a,*.o} "$root"/lib
      sed -i "s,$NIX_STORE[^ ]*/,,g" "$root"/lib/lib{c,gcc_s}.so
      chmod -R u+w "$root"/lib
      cp -rLv '${linux-headers}'/include "$root"
      chmod -R u+w "$root"/include
      rm -rv "$root"/include/{xen,drm,rdma,sound}
      cp -rLv '${glibc_lib_gcc.dev}'/include "$root"
      chmod -R u+w "$root"/include
      cp -rLv '${gcc.cc_headers}'/include "$root"/include-gcc
      cp -rLv '${gcc.cc_headers}'/include-fixed "$root"/include-fixed-gcc
      cp -rLv '${gcc_runtime_glibc.dev}'/include/c++/* "$root"/include-c++

      copy_bin_and_deps() {
        local file="$1"
        local outdir="$2"

        echo "Copying $file" >&2
        local outfile="$outdir/$(basename "$file")"
        if [ -e "$outfile" ]; then
          echo "Already have: $outfile" >&2
          return 0
        fi
        cp -dv "$file" "$outfile"
        local needed=""
        if ! needed+=" $(patchelf --print-interpreter "$file")"; then
          return 0
        fi
        needed+=" $(patchelf --print-needed "$file")" || true
        local lib
        for lib in $needed; do
          echo "Looking''${lib:0:1}:$lib" >&2
          if [ "''${lib:0:1}" = "/" ]; then
            copy_bin_and_deps "$lib" "$root"/lib
            continue
          fi
        done
      }

      copy_bin_and_deps '${bash_small.bin}'/bin/bash "$root"/bin

      nuke-refs "$root"/{bin,lib,libexec}/*

      mkdir -pv "$out"/on-server
      tar --sort=name --owner=0 --group=0 --numeric-owner \
        --no-acls --no-selinux --no-xattrs \
        --mode=go=rX,u+rw,a-s \
        --clamp-mtime --mtime=@946713600 \
        -c -C "$root" . | xz -9 -e > "$out"/on-server/bootstrap-tools.tar.xz
      cp ${busybox_bootstrap}/bin/busybox "$out"/on-server/bootstrap-busybox
      chmod u+w $out/on-server/bootstrap-busybox
      nuke-refs $out/on-server/bootstrap-busybox
    '';

    # The result should not contain any references (store paths) so
    # that we can safely copy them out of the store and to other
    # locations in the store.
    allowedReferences = [ ];
  };

  dist = stdenv.mkDerivation {
    name = "stdenv-bootstrap-dist";

    buildCommand = ''
      mkdir -p $out/nix-support
      echo "file tarball '${build}'/on-server/bootstrap-tools.tar.xz" >> $out/nix-support/hydra-build-products
      echo "file busybox '${build}'/on-server/busybox" >> $out/nix-support/hydra-build-products
    '';
  };

}
