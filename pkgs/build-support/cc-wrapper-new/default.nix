# The Nixpkgs CC is not directly usable, since it doesn't know where
# the C library and standard header files are. Therefore the compiler
# produced by that package cannot be installed directly in a user
# environment and used from the command line. So we use a wrapper
# script that sets up the right environment variables so that the
# compiler and the linker just "work".

{ stdenv
, coreutils
}:

{ compiler
, target ? null
, tools ? [ ]
, inputs ? [ ]
}:

(stdenv.override { cc = null; }).mkDerivation {
  name = "cc-wrapper";

  inherit (compiler)
    cc
    cpp
    cxx
    optFlags
    prefixMapFlag
    canStackClashProtect;

  pfx = if target == null then "" else "${target}-";

  inherit
    coreutils
    compiler
    tools
    inputs;

  buildCommand = ''
    mkdir -p "$out"/bin "$out"/nix-support

    wrap() {
      local prog="$1"
      local wrapper="$2"

      local pname="''${prog##*/}"
      local pdir="''${prog%/*}"
      if [ "''${pname:0:''${#pfx}}" = "$pfx" ]; then
        pname="''${pname:''${#pfx}}"
      fi

      local target="$out"/bin/"$pfx$pname"
      if [ -e "$target" ]; then
        echo "WARNING: $target already exists" >&2
        return 0
      fi

      prog="$pdir/$pfx$pname"
      if [ ! -e "$prog" ]; then
        prog="$pdir/$pname"
        if [ ! -e "$prog" ]; then
          echo "ERROR: Missing $prog" >&2
          exit 1
        fi
      fi

      export prog
      echo "Wrapping $prog -> $target" >&2
      substituteAll "$wrapper" "$target"
      chmod +x "$target"
      unset prog
    }

    maybeWrap() {
      local prog="$1"

      wrap "$@"
    }

    wrap "$compiler"/bin/"$cc" '${./cc-wrapper.sh}'
    ln -sv "$pfx$cc" "$out"/bin/"$pfx"cc
    wrap "$compiler"/bin/"$cxx" '${./cc-wrapper.sh}'
    ln -sv "$pfx$cxx" "$out"/bin/"$pfx"c++
    if [ -e "$compiler"/bin/"$pfx"cpp -o -e "$compiler"/bin/cpp ]; then
      wrap "$compiler"/bin/cpp '${./cc-wrapper.sh}'
    fi

    for bin in "$compiler" $tools; do
      for prog in "$bin"/bin/"$pfx"ld* "$bin"/bin/ld*; do
        wrap "$prog" '${./ld-wrapper.sh}'
      done

      for prog in "$bin"/bin/*; do
        [ -e "$out"/bin/"$(basename "$prog")" ] || ln -sv "$prog" "$out"/bin
      done
    done

    maybeAppend() {
      local file="$1"
      local input="$2"

      [ -e "$input"/nix-support/"$file" ] || return 0
      cat "$input"/nix-support/"$file" >>"$out"/nix-support/"$file"
    }

    for inc in "$compiler" $tools $inputs; do
      maybeAppend cflags-compile "$inc"
      maybeAppend cxxflags-compile "$inc"
      maybeAppend cflags-link "$inc"
      maybeAppend cxxflags-link "$inc"
      maybeAppend ldflags "$inc"
      maybeAppend ldflags-before "$inc"
      maybeAppend ldflags-dynamic "$inc"
    done

    substituteAll '${./setup-hook.sh}' "$out"/nix-support/setup-hook
    substituteAll '${./utils.sh}' "$out"/nix-support/utils.sh
  '';

  allowSubstitutes = false;
  preferLocalBuild = true;
}
