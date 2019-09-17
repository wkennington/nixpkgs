export NIX@typefx@_CC='@out@'

export CC@typefx@='@pfx@@cc@'
export CXX@typefx@='@pfx@@cxx@'
export CPP@typefx@='@pfx@@cpp@'

@type@CCProg() {
  local prog
  prog="$('@out@'/bin/$CC@typefx@ -print-prog-name="$1" 2>/dev/null)"
  if [ -n "$prog" ]; then
    export ${1^^}@typefx@="$prog"
  fi
}

@type@CCProg ar
@type@CCProg ranlib
@type@CCProg ld
@type@CCProg readelf
@type@CCProg strip

@type@AddCVars () {
  if [ -e $1/nix-support/cc-wrapper-ignored ]; then
    return
  fi

  if [ -d $1/include ]; then
    export NIX@typefx@_CFLAGS_COMPILE+=" ${ccIncludeFlag:--isystem} $1/include"
  fi

  if [ -d $1/lib64 -a ! -L $1/lib64 ]; then
    export NIX@typefx@_LDFLAGS+=" -L$1/lib64"
  fi

  if [ -d $1/lib ]; then
    export NIX@typefx@_LDFLAGS+=" -L$1/lib"
  fi
}

if [ -z "${nix_@type@_cc_done-}" ]; then
  nix_@type@_cc_done=1

  # TODO: Support native libraries and proper cross compiling
  if [ -z "@typefx@" ]; then
    envHooks+=(@type@AddCVars)
  fi

  # Add the output as an rpath, we should only ever do this for host binaries
  # and not for builder binaries since those should never be installed.
  if [ -z "@typefx@" ] && [ -n "${NIX_LD_ADD_RPATH-1}" ]; then
    rpathOutputs=()
    # We prefer libdirs over all others
    for output in $outputs; do
      if [ "${output:0:3}" = "lib" ]; then
        rpathOutputs+=("$output")
      fi
    done
    # Bin outputs can have dynamic libraries
    for output in $outputs; do
      if [ "${output:0:3}" = "bin" ]; then
        rpathOutputs+=("$output")
      fi
    done
    if [ "${#rpathOutputs[@]}" -eq "0" ]; then
      rpathOutputs+=("$defaultOutput")
    fi
    for output in "${rpathOutputs[@]}"; do
      export NIX_LDFLAGS_BEFORE+=" -rpath ${!output}/lib"
    done
  fi
fi
