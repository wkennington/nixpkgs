# The Nixpkgs CC is not directly usable, since it doesn't know where
# the C library and standard header files are. Therefore the compiler
# produced by that package cannot be installed directly in a user
# environment and used from the command line. So we use a wrapper
# script that sets up the right environment variables so that the
# compiler and the linker just "work".

{ stdenv
, lib
, coreutils
}:

lib.makeOverridable
({ compiler
, target ? ""
, tools ? [ ]
, inputs ? [ ]
, type ? "host"
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

  inherit
    coreutils
    compiler
    tools
    inputs
    target;

  inherit type;
  typefx = {
    "build" = "_FOR_BUILD";
    "host" = "";
  }."${type}";

  pfx = if target == "" then "" else "${target}-";

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

      local link="$out"/bin/"$pfx$pname"
      if [ -e "$link" ]; then
        echo "WARNING: $link already exists" >&2
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
      echo "Wrapping $link -> $prog" >&2
      substituteAll "$wrapper" "$link"
      chmod +x "$link"
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

    if [ -n "${target}" ]; then
      mkdir -p "$out"/"${target}"/bin
      for prog in "$out"/bin/*; do
        local pname="''${prog##*/}"
        if [ "''${pname:0:''${#pfx}}" = "$pfx" ]; then
          pname="''${pname:''${#pfx}}"
        fi
        ln -sv "$prog" "$out"/"${target}"/bin/"$pname"
      done
    fi

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
})
