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
if [ -n "${CC_WRAPPER_DEBUG-}" -o -n "${CC_WRAPPER@typefx@_LD_DEBUG-}" ]; then
  echo "original flags to @prog@:" >&2
  for i in "$@"; do
      echo "  $i" >&2
  done
  set -x
fi

if [ -z "${CC_WRAPPER@typefx@_LD_WRAPPER_FLAGS_SET-}" ]; then
  export CC_WRAPPER@typefx@_LD_WRAPPER_FLAGS_SET=1

  maybeAppendFlagsFromFile CC_WRAPPER@typefx@_LDFLAGS '@out@'/nix-support/ldflags
  maybeAppendFlagsFromFile CC_WRAPPER@typefx@_LDFLAGS_BEFORE '@out@'/nix-support/ldflags-before
  maybeAppendFlagsFromFile CC_WRAPPER@typefx@_LDFLAGS_DYNAMIC '@out@'/nix-support/ldflags-dynamic
fi

params=($CC_WRAPPER@typefx@_LDFLAGS_BEFORE)
: ${CC_WRAPPER@typefx@_LD_HARDEN=1}

if [ "${CC_WRAPPER@typefx@_LD_NEW_DTAGS-1}" = "1" ]; then
  params+=('--enable-new-dtags')
fi
if [ "${CC_WRAPPER@typefx@_LD_NOEXECSTACK-$CC_WRAPPER@typefx@_LD_HARDEN}" = "1" ]; then
  params+=('-z' 'noexecstack')
fi
if [ "${CC_WRAPPER@typefx@_LD_RELRO-$CC_WRAPPER@typefx@_LD_HARDEN}" = "1" ]; then
  params+=('-z' 'relro')
fi
if [ "${CC_WRAPPER@typefx@_LD_BINDNOW-$CC_WRAPPER@typefx@_LD_HARDEN}" = "1" ]; then
  params+=('-z' 'now')
fi
# Remove compiler passed runtime paths
compilerFlags=
for p in "$@"; do
  if [ "$p" = -g ]; then
    compilerFlags=1
  fi
done
haveDyldFlag=
if [[ "${CC_WRAPPER@typefx@_LDFLAGS_BEFORE-}" =~ (^| )-dynamic-linker\  ]]; then
  haveDyldFlag=1
fi
for (( i = 1; i <= "$#" ; i++ )); do
  p="${!i}"
  n=$((i + 1))
  p2="${!n-}"
  if [ "$p" = -g ]; then
    compilerFlags=
  elif [ "$p" = -rpath -a -n "$compilerFlags" ]; then
    i=$((i + 1))
  elif [ "$p" = -dynamic-linker -a -n "$compilerFlags" -a -n "$haveDyldFlag" ]; then
    i=$((i + 1))
  else
    params+=("$p")
  fi
done
params+=($CC_WRAPPER@typefx@_LDFLAGS)

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
  params+=(${CC_WRAPPER@typefx@_LDFLAGS_DYNAMIC-})
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
if [ -n "${CC_WRAPPER@typefx@_LD_ADD_RPATH-1}" ]; then
  addToRPath() {
    local libdir="$(dirname "$1")"
    local prevdir="${2-$libdir}"

    # We need to follow library symlinks in order to pick the best rpath
    local link
    if link="$(readlink "$1")"; then
      if [ "${link:0:1}" = "/" ]; then
        addToRPath "$link" "$libdir"
       else
        addToRPath "$libdir/$link" "$libdir"
      fi
    else
      local comment
      read -N 2 comment <"$1"
      # We might be a linker script
      if [ "$comment" = "/*" ]; then
        set -o noglob
        local arr
        arr=($(cat "$1"))
        set +o noglob
        local p
        for p in "${arr[@]}"; do
          if [ "${p:0:2}" = '-l' ]; then
            addToLibs "l=${p:2}"
          elif [[ "$p" =~ ^[^-].*\.so($|\.) ]]; then
            if [ "${p:0:1}" = '/' ]; then
              addToRPath "$p" "$libdir"
            else
              addToRPath "$libdir/$p" "$libdir"
            fi
          fi
        done
      elif [[ "$1" =~ ^[^-].*\.so($|\.) ]]; then
        rpathsNeeded["$libdir"]=1
      fi
    fi

    rpaths+=" $libdir $prevdir"
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
  rpaths=""
  declare -A rpathsNeeded
  paramsStatic=
  for (( i = 0; i < "${#params[@]}"; i++ )); do
    p="${params[$i]}"
    p2="${params[$((i+1))]-}"
    if [ "$p" = -L ]; then
      i=$((i + 1))
      addToLibPath "$p2"
    elif [ "${p:0:2}" = -L ]; then
      addToLibPath "${p:2}"
    elif [ "$p" = -z ]; then
      i=$((i + 1))
    elif [ "$p" = -rpath ]; then
      i=$((i + 1))
    elif [ "$p" = -rpath-link ]; then
      i=$((i + 1))
    elif [ "$p" = -static ]; then
      paramsStatic=1
    elif [ "$p" = -Bdynamic ]; then
      paramsStatic=
    elif [ "$p" = -Bstatic ]; then
      paramsStatic=1
    elif [ "$p" = -l ]; then
      i=$((i + 1))
      if [ -z "$paramsStatic" ]; then
        addToLibs "l=$p2"
      fi
    elif [ "${p:0:2}" = -l ]; then
      if [ -z "$paramsStatic" ]; then
        addToLibs "l=${p:2}"
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
    elif [ "$p" = -o ]; then
      # We don't need to look at the output object
      i=$((i + 1))
    elif [[ "$p" =~ ^[^-].*$ ]]; then
      [ -e "$p" -a ! -d "$p" ] && addToLibs "p=$p"
    fi
  done

  # -L flags apply to all -l switches regardless of order
  # Match them up accordingly now
  n=0
  while [ "$n" -lt "${#libs[@]}" ]; do
    lib="${libs[$n]}"
    if [ "${lib:0:2}" = "l=" ]; then
      for libpath in "${libpaths[@]}"; do
        sofile="$libpath/lib${lib:2}.so"
        if [ -e "$sofile" ]; then
          addToRPath "$sofile"
          break
        fi
        [ -e "$libpath/lib${lib:2}.a" ] && break
      done
    else
      addToRPath "${lib:2}"
    fi
    n=$(( n + 1 ))
  done

  # Finally, add `-rpath' switches.
  beforeParams=()
  for i in $(echo "$rpaths" | tsort); do
    [ -n "${rpathsNeeded["$i"]-}" ] || continue

    # If the path is not in the store, don't add it to the rpath.
    # This typically happens for libraries in /tmp that are later
    # copied to $out/lib.  If not, we're screwed.
    startsWith '@CC_WRAPPER_STORE@' "$i" || continue

    beforeParams+=('-rpath' "$i")
  done
  params=("${beforeParams[@]}" "${params[@]}")
fi

# Optionally print debug info.
if [ -n "${CC_WRAPPER_DEBUG-}" -o -n "${CC_WRAPPER@typefx@_LD_DEBUG-}" ]; then
  echo "new flags to @prog@:" >&2
  for i in ${params[@]}; do
    echo "  $i" >&2
  done
fi

PATH="$path_backup"
exec @prog@ "${params[@]}"
