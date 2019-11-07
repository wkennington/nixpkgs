appendFlags() {
  local var="$1"
  local val="$2"

  export "$var"="${!var-}${!var+ }$val"
}

maybeAppendFlagsFromFile() {
  local var="$1"
  local file="$2"

  if [ -e "$file" ]; then
    appendFlags "$var" "$(cat "$file" | tr '\n' ' ')"
  else
    export "$var"="${!var-}"
  fi
}

maybeAppendFlagsFromFile CPPFLAGS '@libs@'/nix-support/stdinc
maybeAppendFlagsFromFile CPPFLAGS '@libs@'/nix-support/cflags
maybeAppendFlagsFromFile CPPFLAGS '@libs@'/nix-support/cflags-link

maybeAppendFlagsFromFile CXXFLAGS '@libs@'/nix-support/stdincxx
maybeAppendFlagsFromFile CXXFLAGS '@libs@'/nix-support/cxxflags
maybeAppendFlagsFromFile CXXFLAGS '@libs@'/nix-support/cxxflags-link

maybeAppendFlagsFromFile DYLD '@libs@'/nix-support/dynamic-linker
if [ -n "${DYLD-}" ]; then
  LDFLAGS_PRE="-dynamic-linker $DYLD"
fi
maybeAppendFlagsFromFile LDFLAGS_PRE '@libs@'/nix-support/ldflags
maybeAppendFlagsFromFile LDFLAGS_PRE '@libs@'/nix-support/ldflags-before
maybeAppendFlagsFromFile LDFLAGS_PRE '@libs@'/nix-support/ldflags-dynamic

dynamicLinker=
export LDFLAGS=
for LDFLAG in $LDFLAGS_PRE; do
  if [ -n "$dynamicLinker" ]; then
    dynamicLinker=
    LDFLAGS+=" -Wl,$LDFLAG"
  elif [ "$LDFLAG" = -dynamic-linker ]; then
    dynamicLinker=1
    LDFLAGS+=" -Wl,$LDFLAG"
  else
    if [ "${LDFLAG:0:2}" = -L ]; then
      LDFLAGS+=" -Wl,-rpath -Wl,${LDFLAG:2}"
    fi
    LDFLAGS+=" $LDFLAG"
  fi
done

export STRIP='strip'
export READELF='readelf'
