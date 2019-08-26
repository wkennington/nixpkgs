export NIX@typefx@_CC='@out@'

export CC@typefx@='@pfx@@cc@'
export CXX@typefx@='@pfx@@cxx@'
export CPP@typefx@='@pfx@@cpp@'
export STRIP@typefx@='@strip@'

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

  @type@EnvHooks+=(@type@AddCVars)

  # Add the output as an rpath, we should only ever do this for host binaries
  # and not for builder binaries since those should never be installed.
  if [ -z "@typefx@" ] && [ -n "${NIX_LD_ADD_RPATH-1}" ]; then
    rpathOut="${outputs%% *}"
    if [[ "$outputs" =~ (^| )lib( |$) ]]; then
      rpathOut="lib"
    fi
    export NIX_LDFLAGS+=" -rpath ${!rpathOut}/lib"
  fi
fi
