# This setup hook creates absolute references to pkgconfig files in the fixup phase.

fixupOutputHooks+=(_doAbsolutePkgconfig)

_doAbsolutePkgconfig() {
  if [ -n "${absolutePkgconfig-1}" ]; then
    header "Fixing up pkgconfig paths"
    addOutputPkgconfigPaths
    pkgconfigFiles | rewritePkgconfigFiles
  fi
}

rewritePkgconfigFiles() {
  local pkgfile
  while read pkgfile; do
    local absoluteDeps
    absoluteDeps="$(pkgconfigRequires "$pkgfile" | fixPkgconfigNameBug | toAbsoluteDependencies)"
    local absoluteDepsPrivate
    absoluteDepsPrivate="$(pkgconfigRequiresPrivate "$pkgfile" | fixPkgconfigNameBug | toAbsoluteDependencies)"

    sed -i "$pkgfile" \
      -e "s@^Requires:.*\$@Requires: $(echo $absoluteDeps)@g" \
      -e "s@^Requires.private:.*\$@Requires.private: $(echo $absoluteDepsPrivate)@g"
  done
}

toAbsoluteDependencies() {
  local dep
  while read dep; do
    local absoluteDep
    absoluteDep="$(pkgconfigPath $dep)"
    if [ "${absoluteDep:0:1}" != "/" ]; then
      echo "Found a non-absolute dependency $absoluteDep in $pkgfile" >&2
      return 1
    fi
    if [ "$absoluteDep" != "$dep" ] && [ "$(basename "$absoluteDep" | sed 's@^\(.*\)\.pc$@\1@g')" != "$dep" ]; then
      echo "Found a dependency that doesn't match: $absoluteDep != $dep in $pkgfile" >&2
      return 1
    fi
    echo "$absoluteDep"
  done
}

addOutputPkgconfigPaths() {
  local output;
  for output in $outputs; do
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH${PKG_CONFIG_PATH:+:}${!output}/lib/pkgconfig:${!output}/share/pkgconfig"
  done
}

pkgconfigRequires() {
  local name;
  name="$1"
  if ! pkg-config --print-requires "$name" | awk '{print $1}'; then
    echo "Failed to enumerate all of the 'Requires:' dependencies $name" >&2
    return 1
  fi
}

pkgconfigRequiresPrivate() {
  local name;
  name="$1"
  if ! pkg-config --print-requires-private "$name" | awk '{print $1}'; then
    echo "Failed to enumerate all of the 'Requires.private:' dependencies $name" >&2
    return 1
  fi
}

# When using pkgconfig 0.29, if absolute paths are specified in a requires
# field we get a prefixed slash sometimes. This removes it
fixPkgconfigNameBug() {
  sed 's,^/\([^./]*\)$,\1,g'
}

pkgconfigFiles() {
  find "${prefix}"/{lib,share}/pkgconfig -name \*.pc 2>/dev/null || true
}

# Takes a pkg name and returns the path to the pkgconfig file
pkgconfigPath() {
  local name; local path;
  name="$1"
  if [ "${name:0:1}" = "/" ] && [ -e "$name" ]; then
    echo "$name"
    return 0
  fi
  for path in $(echo "$PKG_CONFIG_PATH" | tr ':' '\n'); do
    if [ -e "$path/$name.pc" ]; then
      echo "$path/$name.pc"
      return 0
    fi
  done
  echo "Missing pkg-config file for $name" >&2
  return 1
}
