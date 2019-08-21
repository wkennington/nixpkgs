#! @shell@

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

# Figure out if linker flags should be passed.  GCC prints annoying
# warnings when they are not needed.
dontLink=
shared=
nonFlagArgs=
noStartFiles=
noDefaultLibs=
noStdLib=
noLibc=
noStdInc=
noStdIncxx=

for i in "$@"; do
  if [ "$i" = -c ]; then
    dontLink=1
  elif [ "$i" = -shared ]; then
    shared=1
  elif [ "$i" = -S ]; then
    dontLink=1
  elif [ "$i" = -E ]; then
    dontLink=1
  elif [ "$i" = -E ]; then
    dontLink=1
  elif [ "$i" = -M ]; then
    dontLink=1
  elif [ "$i" = -MM ]; then
    dontLink=1
  elif [ "$i" = -x ]; then
    # At least for the cases c-header or c++-header we should set dontLink.
    # I expect no one use -x other than making precompiled headers.
    dontLink=1
  elif [ "$i" = -nostartfiles ]; then
    noStartFiles=1
  elif [ "$i" = -nodefaultlibs ]; then
    noDefaultLibs=1
  elif [ "$i" = -nostdlib ]; then
    noStdlib=1
  elif [ "$i" = -nolibc ]; then
    noLibc=1
  elif [ "$i" = -nostdinc ]; then
    noStdInc=1
  elif [ "$i" = -nostdincxx ]; then
    noStdIncxx=1
  elif [ "${i:0:1}" != - ]; then
    nonFlagArgs=1
  fi
done

# If we don't have any input files, we won't call the linker
if [ -z "$nonFlagArgs" ]; then
  dontLink=1
fi

if [ -z "${NIX_CC_WRAPPER_FLAGS_SET-}" ]; then
  export NIX_CC_WRAPPER_FLAGS_SET=1

  # `-B@out@/bin' forces cc to use ld-wrapper.sh when calling ld.
  appendFlags NIX_CFLAGS_COMPILE '-B@out@/bin'
  appendFlags NIX_CFLAGS_COMPILE '-B@out@/@target@/bin'

  if [ -z "$noStdInc" ]; then
    maybeAppendFlagsFromFile NIX_CFLAGS_COMPILE '@out@'/nix-support/cflags-compile
    if [ -z "$noStdIncxx" ]; then
      maybeAppendFlagsFromFile NIX_CXXFLAGS_COMPILE '@out@'/nix-support/cxxflags-compile
    fi
  fi
  maybeAppendFlagsFromFile NIX_CXXFLAGS_LINK '@out@'/nix-support/cxxflags-link
  maybeAppendFlagsFromFile NIX_CFLAGS_LINK '@out@'/nix-support/cflags-link
fi

params=('-nostdinc')
if [ -z "$dontLink" ]; then
  params+=('-Wl,-g')
fi
: ${NIX_CC_HARDEN=1}

if [ -n "${NIX_CC_CPU_OPT-$NIX_CC_HARDEN}" ]; then
  params+=(@optFlags@)
fi

if [ -n "${NIX_CC_PIC-$NIX_CC_HARDEN}" -a -z "$dontLink" -a -n "$shared" ]; then
  params+=("-pie")
fi

if [ -n "${NIX_CC_PIC-$NIX_CC_HARDEN}" ]; then
  params+=("-fPIC")
fi

if [ -n "${NIX_CC_NO_STRICT_OVERFLOW-$NIX_CC_HARDEN}" ]; then
  params+=("-fno-strict-overflow")
fi

if [ -n "${NIX_CC_FORTIFY_SOURCE-$NIX_CC_HARDEN}" ]; then
  params+=("-D_FORTIFY_SOURCE=2")
fi

if [ -n "${NIX_CC_STACK_PROTECTOR-$NIX_CC_HARDEN}" ]; then
  params+=("-fstack-protector-strong")
fi

if [ -n "@canStackClashProtect@" -a -n "${NIX_CC_STACK_CLASH_PROTECTION-$NIX_CC_HARDEN}" ]; then
  params+=("-fstack-clash-protection")
fi

if [ -n "${NIX_CC_OPTIMIZE-$NIX_CC_HARDEN}" ]; then
  params+=("-O2")
fi

# Remove any flags which may interfere with hardening
for (( i = 1; i <= "$#"; i++ )); do
  p="${!i}"
  if [ -n "${NIX_CC_FORTIFY_SOURCE-$NIX_CC_HARDEN}" ] && [[ "$p" =~ ^-D_FORTIFY_SOURCE ]]; then
    continue
  fi
  if [ -n "${NIX_CC_NO_STRICT_OVERFLOW-$NIX_CC_HARDEN}" ] && [[ "$p" =~ ^-f.*strict-overflow ]]; then
    continue
  fi
  if [ -n "${NIX_CC_STACK_PROTECTOR-$NIX_CC_HARDEN}" ] && [[ "$p" =~ ^-f.*stack-protector.* ]]; then
    continue
  fi
  if [[ "$p" =~ ^-m(arch|tune)=native$ ]]; then
    continue
  fi
  if [ -n "${NIX_CC_PIC-$NIX_CC_HARDEN}" ] && [[ "$p" =~ ^-f(pic|PIC|pie|PIE)$ ]]; then
    continue
  fi
  if [ -n "${NIX_CC_OPTIMIZE-$NIX_CC_HARDEN}" ] && [[ "$p" =~ ^-O([0-9]|s|g|fast)$ ]]; then
    continue
  fi
  params+=("$p")
done

linkFlags=()
if [[ "@prog@" = *++ ]]; then
  params+=($NIX_CXXFLAGS_COMPILE)
  linkFlags+=($NIX_CXXFLAGS_LINK)
fi
params+=($NIX_CFLAGS_COMPILE)
linkFlags+=($NIX_CFLAGS_LINK)
if [ -z "$dontLink" ]; then
  params+=("${linkFlags[@]}")
fi

# Filter out any bad paths
filtered_params=()
for (( i=0; i < "${#params[@]}"; ++i )); do
  p="${params[$i]}"
  p2="${params[$((i+1))]-}"
  if [ "${p:0:3}" = -L/ ] && badPath "${p:2}"; then
    skip "$p"
  elif [ "$p" = -L ] && badPath "$p2"; then
    i=$((i + 1))
    skip "$p2"
  elif [ "${p:0:3}" = -I/ ] && badPath "${p:2}"; then
    skip "$p"
  elif [ "$p" = -I ] && badPath "$p2"; then
    i=$((i + 1))
    skip "$p2"
  elif [ "$p" = -isystem ] && badPath "$p2"; then
    i=$((i + 1))
    skip "$p2"
  else
    filtered_params+=("$p")
  fi
done
params=("${filtered_params[@]}")

nix_store='@NIX_STORE@'
add_filter_path() {
  startsWith "$nix_store" "$1" || return 0
  drv="${1:${#nix_store}+1}"
  drv="${drv%%/*}"
  filter_paths["$nix_store/$drv"]=1
}

# Filter out any debug information
declare -A filter_paths
for (( i = 0; i < "${#params[@]}"; i++ )); do
  p="${params[$i]}"
  p2="${params[$((i+1))]-}"
  if [ "${p:0:3}" = -I/ ]; then
    add_filter_path "${p:2}"
  elif [ "$p" = -isystem ] || [ "$p" = -I ] || [ "$p" = -idirafter ]; then
    i=$((i + 1))
    add_filter_path "$p2"
  fi
done

for n in "${!filter_paths[@]}"; do
  name="${n:${#nix_store}}"
  name="${name#*-}"
  params+=("@prefixMapFlag@=$n=/no-such-path/$name")
done

if [ -n "${NIX_BUILD_TOP-}" ]; then
  params+=("@prefixMapFlag@=$NIX_BUILD_TOP=/no-such-path/build")
fi

# Optionally print debug info.
if [ -n "${NIX_DEBUG-}" ]; then
  echo "new flags to @prog@:" >&2
  for i in "${params[@]}"; do
    echo "  $i" >&2
  done
fi

PATH="$path_backup"
exec @prog@ "${params[@]}"
