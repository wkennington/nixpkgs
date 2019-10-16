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
, tools ? [ ]
, inputs ? [ ]
, type ? "host"
}:

let
  inherit (lib)
    optionalString;

  inherit (compiler)
    target;
in
assert target != "";
(stdenv.override { cc = null; }).mkDerivation {
  name = "cc-wrapper";

  inherit (compiler)
    cc
    cxx
    optFlags
    prefixMapFlag
    canStackClashProtect;

  inherit
    coreutils
    compiler
    tools
    inputs;

  inherit type;
  typefx = {
    "build" = "_FOR_BUILD";
    "host" = "";
  }."${type}";

  target = if target == null then "" else target;
  pfx = if target == null then "" else "${target}-";

  buildCommand = ''
    mkdir -p "$out"/bin "$out"/nix-support

    exists() {
      [ -h "$1" -o -e "$1" ]
    }

    wrap() {
      local prog="$1"
      local wrapper="$2"

      local pname="''${prog##*/}"
      local pdir="''${prog%/*}"
      if [ "''${pname:0:''${#pfx}}" = "$pfx" ]; then
        pname="''${pname:''${#pfx}}"
      fi

      local link="$out"/bin/"$pfx$pname"
      if exists "$link"; then
        echo "WARNING: $link already exists" >&2
        return 0
      fi

      prog="$pdir/$pfx$pname"
      if ! exists "$prog"; then
        prog="$pdir/$pname"
        if ! exists "$prog"; then
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

    for bin in "$compiler" $tools; do
      for prog in "$bin"/bin/"$pfx"ld* "$bin"/bin/ld*; do
        wrap "$prog" '${./ld-wrapper.sh}'
      done

      for prog in "$bin"/bin/*; do
        exists "$out"/bin/"$(basename "$prog")" || ln -sv "$prog" "$out"/bin
      done
    done
  '' + optionalString (target != null) ''
    mkdir -p "$out"/"${target}"/bin
    for prog in "$out"/bin/*; do
      local pname="''${prog##*/}"
      if [ "''${pname:0:''${#pfx}}" = "$pfx" ]; then
        pname="''${pname:''${#pfx}}"
      fi
      ln -sv "$prog" "$out"/"${target}"/bin/"$pname"
    done
  '' + ''
    maybeAppend() {
      local file="$1"
      local input="$2"

      exists "$input"/nix-support/"$file" || return 0
      cat "$input"/nix-support/"$file" >>"$out"/nix-support/"$file"
    }

    for inc in "$compiler" $tools $inputs; do
      maybeAppend cflags "$inc"
      maybeAppend cxxflags "$inc"
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
