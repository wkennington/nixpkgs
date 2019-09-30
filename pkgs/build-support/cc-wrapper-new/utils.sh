skip () {
  if [ -n "${CC_WRAPPER_DEBUG-}" ]; then
    echo "skipping impure path $1" >&2
  fi
}

startsWith() {
  local prefix="$1"
  local path="$2"

  [ "${path:0:${#prefix}}" = "$prefix" ]
}

# Checks whether a path is impure.  E.g., `/lib/foo.so' is impure, but
# `/nix/store/.../lib/foo.so' isn't.
badPath() {
  local p="$1"

  # Relative paths are okay (since they're presumably relative to
  # the temporary build directory).
  [ "${p:0:1}" != / ] && return 1

  # We don't want any /no-such-paths
  startsWith '/no-such-path' "$p" && return 0

  # Purity checks happen after this stage
  [ -z "${CC_WRAPPER_ENFORCE_PURITY-}" ] && return 1

  # Otherwise, the path should refer to the store or some temporary
  # directory (including the build directory).
  [ "$p" == "/dev/null" ] && return 1
  startsWith '@NIX_STORE@' "$p" && return 1
  startsWith "$NIX_BUILD_TOP" "$p" && return 1
  startsWith "${TMPDIR:-/tmp}" "$p" && return 1
  return 0
}

appendFlags() {
  local var="$1"
  local val="$2"

  export "$var"="${!var-}${!var+ }$val"
}

maybeAppendFlagsFromFile() {
  local var="$1"
  local file="$2"

  if [ -e "$file" ]; then
    appendFlags "$var" "$(cat "$file")"
  else
    export "$var"="${!var-}"
  fi
}
