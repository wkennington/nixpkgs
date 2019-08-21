#! @shell@ -e

set -o errexit
set -o pipefail
set -o nounset

path_backup="$PATH"
if [ -n "@coreutils@" ]; then
  PATH="@coreutils@/bin"
fi

source @out@/nix-support/utils.sh

# Optionally print debug info.
if [ -n "${NIX_DEBUG-}" ]; then
  echo "original flags to @prog@:" >&2
  for i in "$@"; do
      echo "  $i" >&2
  done
fi

if [ -z "${NIX_LD_WRAPPER_FLAGS_SET-}" ]; then
  export NIX_LD_WRAPPER_FLAGS_SET=1

  maybeAppendFlagsFromFile NIX_LDFLAGS '@out@'/nix-support/ldflags
  maybeAppendFlagsFromFile NIX_LDFLAGS_BEFORE '@out@'/nix-support/ldflags-before
  maybeAppendFlagsFromFile NIX_LDFLAGS_DYNAMIC '@out@'/nix-support/ldflags-dynamic
fi

params=($NIX_LDFLAGS_BEFORE)
: ${NIX_LD_HARDEN=1}

if [ "${NIX_LD_ADD_RPATH-1}" = "1" ]; then
  params+=('--enable-new-dtags')
fi
if [ "${NIX_LD_NOEXECSTACK-$NIX_LD_HARDEN}" = "1" ]; then
  params+=('-z' 'noexecstack')
fi
if [ "${NIX_LD_RELRO-$NIX_LD_HARDEN}" = "1" ]; then
  params+=('-z' 'relro')
fi
if [ "${NIX_LD_BINDNOW-$NIX_LD_HARDEN}" = "1" ]; then
  params+=('-z' 'now')
fi
# Remove compiler passed runtime paths
compilerFlags=
for p in "$@"; do
  if [ "$p" = -g ]; then
    compilerFlags=1
  fi
done
for (( i = 1; i <= "$#" ; i++ )); do
  p="${!i}"
  n=$((i + 1))
  p2="${!n-}"
  if [ "$p" = -g ]; then
    compilerFlags=
  elif [ -n "$compilerFlags" -a "$p" = -rpath ]; then
    i=$((i + 1))
  elif [ -n "$compilerFlags" -a "$p" = -dynamic-linker ]; then
    i=$((i + 1))
  else
    params+=("$p")
  fi
done
params+=($NIX_LDFLAGS)

# Determine if we are dynamically linking
dynamicLibs=
paramsStatic=
for p in "${params[@]}"; do
  if [ "$p" = -static ]; then
    paramsStatic=1
  elif [ "$p" = -Bdynamic ]; then
    paramsStatic=
  elif [ "$p" = -Bstatic ]; then
    paramsStatic=1
  elif [ -z "$paramsStatic" ] && [ "$p" = "-lc" ]; then
    dynamicLibs=1
  fi
done
if [ -n "$dynamicLibs" ]; then
  params+=(${NIX_LDFLAGS_DYNAMIC-})
fi

# Filter out paths that are considered bad
filtered_params=()
for (( i = 0; i < "${#params[@]}" ; i++ )); do
  p="${params[$i]}"
  p2="${params[$((i+1))]-}"
  if [ "${p:0:3}" = -L/ ] && badPath "${p:2}"; then
    skip "$p"
  elif [ "$p" = -L ] && badPath "$p2"; then
    i=$((i + 1))
    skip "$p2"
  elif [ "$p" = -rpath ] && badPath "$p2"; then
    i=$((i + 1))
    skip "$p2"
  elif [ "$p" = -dynamic-linker ] && badPath "$p2"; then
    i=$((i + 1))
    skip "$p2"
  elif [ "$p" = -plugin ]; then
    i=$((i + 1))
    filtered_params+=("$p" "$p2")
  elif [ "${p:0:1}" = / ] && badPath "$p"; then
    # We cannot skip this; barf.
    echo "impure path '$p' used in link" >&2
    exit 1
  else
    filtered_params+=("$p")
  fi
done
params=("${filtered_params[@]}")

# Add all used dynamic libraries to the rpath.
if [ -n "${NIX_LD_ADD_RPATH-1}" ]; then
  addToRPath() {
    # We need to follow library symlinks in order to pick the best rpath
    local link
    if link="$(readlink "$1")"; then
      if [ "${link:0:1}" = "/" ]; then
        addToRPath "$link"
       else
        addToRPath "$(realpath -sm "$1/../$link")"
      fi
    fi

    # If the path is not in the store, don't add it to the rpath.
    # This typically happens for libraries in /tmp that are later
    # copied to $out/lib.  If not, we're screwed.
    startsWith '@NIX_STORE@' "$1" || return 0

    local libdir="$(dirname "$1")"
    local rpath
    for rpath in "${rpaths[@]}"; do
      [ "$rpath" = "$libdir" ] && return 0
    done
    rpaths+=("$libdir")
  }

  addToLibs() {
    local lib
    for lib in "${libs[@]}"; do
      [ "$1" = "$lib" ] && return 0
    done
    libs+=("$1")
  }

  addToLibPath() {
    local libpath
    for libpath in "${libpaths[@]}"; do
      [ "$1" = "$libpath" ] && return 0
    done
    libpaths+=("$1")
  }

  libs=()
  libpaths=()
  rpaths=()
  paramsStatic=
  for (( i = 0; i < "${#params[@]}"; i++ )); do
    p="${params[$i]}"
    p2="${params[$((i+1))]-}"
    if [ "${p:0:3}" = -L/ ]; then
      addToLibPath "${p:2}"
    elif [ "$p" = -L ]; then
      i=$((i + 1))
      addToLibPath "$p2"
    elif [ "$p" = -static ]; then
      paramsStatic=1
    elif [ "$p" = -Bdynamic ]; then
      paramsStatic=
    elif [ "$p" = -Bstatic ]; then
      paramsStatic=1
    elif [ "$p" = -l ]; then
      i=$((i + 1))
      if [ -z "$paramsStatic" ]; then
        addToLibs "$p2"
      fi
    elif [ "${p:0:2}" = -l ]; then
      if [ -z "$paramsStatic" ]; then
        addToLibs ${p:2}
      fi
    elif [ "$p" = -dynamic-linker ]; then
      # Ignore the dynamic linker argument, or it
      # will get into the next 'elif'. We don't want
      # the dynamic linker path rpath to go always first.
      i=$((i + 1))
    elif [ "$p" = -plugin ]; then
      # Ignore the plugin argument, or it
      # will get into the next 'elif'. We don't want
      # the linker plugins added to the rpath since they are only used
      # by the linker itself
      i=$((i + 1))
    elif [[ "$p" =~ ^[^-].*\.so($|\.) ]]; then
      addToRPath "$p"
    fi
  done

  # -L flags apply to all -l switches regardless of order
  # Match them up accordingly now
  for lib in "${libs[@]}"; do
    for libpath in "${libpaths[@]}"; do
      sofile="$libpath/lib$lib.so"
      if [ -e "$sofile" ]; then
        addToRPath "$sofile"
        break
      fi
      [ -e "$libpath/lib$lib.a" ] && break
    done
  done

  # Finally, add `-rpath' switches.
  for i in "${rpaths[@]}"; do
    params+=('-rpath' "$i")
  done
fi

# Optionally print debug info.
if [ -n "${NIX_DEBUG-}" ]; then
  echo "new flags to @prog@:" >&2
  for i in ${params[@]}; do
    echo "  $i" >&2
  done
fi

PATH="$path_backup"
exec @prog@ "${params[@]}"
