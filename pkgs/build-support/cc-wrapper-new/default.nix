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
, tools ? [ ]
, inputs ? [ ]
}:

(stdenv.override { cc = null; }).mkDerivation {
  name = "cc-wapper";

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
    inputs;

  buildCommand = ''
    mkdir -p "$out"/bin "$out"/nix-support

    wrap() {
      local prog="$1"
      local wrapper="$2"

      local target="$out"/bin/"$(basename "$prog")"
      if [ -e "$target" ]; then
        echo "WARNING: $target already exists" >&2
        return 0
      fi

      export prog
      substituteAll "$wrapper" "$target"
      chmod +x "$target"
      unset prog
    }

    wrap "$compiler"/bin/"$cc" '${./cc-wrapper.sh}'
    ln -sv "$cc" "$out"/bin/cc
    wrap "$compiler"/bin/"$cxx" '${./cc-wrapper.sh}'
    ln -sv "$cxx" "$out"/bin/c++
    if [ -e "$compiler"/bin/cpp ]; then
      wrap "$compiler"/bin/cpp '${./cc-wrapper.sh}'
    fi

    for bin in "$compiler" $tools; do
      echo "$bin" >>"$out"/nix-support/propagated-user-env-packages
      echo "$bin" >>"$out"/nix-support/propagated-native-build-inputs

      for prog in "$bin"/bin/ld*; do
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
