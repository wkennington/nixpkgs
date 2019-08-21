export NIX_CC='@out@'
export NIX_CC_TARGET='@target@'

addCVars () {
  if [ -e $1/nix-support/cc-wrapper-ignored ]; then
    return
  fi

  if [ -d $1/include ]; then
    export NIX_CFLAGS_COMPILE+=" ${ccIncludeFlag:--isystem} $1/include"
  fi

  if [ -d $1/lib64 -a ! -L $1/lib64 ]; then
    export NIX_LDFLAGS+=" -L$1/lib64"
  fi

  if [ -d $1/lib ]; then
    export NIX_LDFLAGS+=" -L$1/lib"
  fi
}

envHooks+=(addCVars)

export CC='@pfx@@cc@'
export CXX='@pfx@@cxx@'
export CPP='@pfx@@cpp@'
export STRIP='@strip@'

if [ -z "${nix_cc_done-}" ]; then
  nix_cc_done=1

  if [ -n "$NIX_CC_TARGET" -a -n "${addHost-1}" ]; then
    configureFlagsArray+=("--host=$NIX_CC_TARGET")
  fi

  # Add the output as an rpath.
  if [ -n "${NIX_LD_ADD_RPATH-1}" ]; then
    rpathOut="${outputs%% *}"
    if [[ "$outputs" =~ (^| )lib( |$) ]]; then
      rpathOut="lib"
    fi
    export NIX_LDFLAGS="$NIX_LDFLAGS -rpath ${!rpathOut}/lib"
  fi
fi
