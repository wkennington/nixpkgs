BINS="awk basename bash bzip2 cat chmod cksum cmp cp cut date diff dirname \
     egrep env expr false fgrep find gawk grep gzip head id install join ld \
     ln ls make mkdir mktemp mv nl nproc od patch readlink rm rmdir sed sh \
     sleep sort stat tar tail tee test touch tsort tr true xz xargs uname uniq wc"
COMPILERS="as ar cpp gcc g++ ld objdump ranlib readelf strip"

echo Unpacking the bootstrap tools...
export PATH=/bin:/usr/bin:/run/current-system/sw/bin
if mkdir --help >/dev/null 2>&1; then
  echo Using native tooling
  findbin() {
    local oldifs="$IFS"
    IFS=:
    local found=
    for p in $PATH; do
      if [ -e "$p"/$1 ]; then
        found="$p"/$1
        break
      fi
    done
    if [ -z "$found" ]; then
      echo "Failed to find: $1" >&2
      exit 1
    fi
    echo "$found"
    IFS="$oldifs"
  }
  mkdir -p "$out"/bin "$compiler"/bin "$glibc"
  for util in $BINS; do
    ln -sv "$(findbin "$util")" "$out"/bin/$util
  done
  for util in $COMPILERS; do
    ln -sv "$(findbin "$util")" "$compiler"/bin/$util
  done
  exit 0
fi

# Unpack the bootstrap tools tarball.
$busybox mkdir $out
< $tarball $busybox unxz | $busybox tar x -C $out

# Set the ELF interpreter / RPATH in the bootstrap binaries.
echo Patching the bootstrap tools...

LD_BINARY=$out/lib/ld-*so

# On x86_64, ld-linux-x86-64.so.2 barfs on patchelf'ed programs.  So
# use a copy of patchelf.
LD_LIBRARY_PATH=$out/lib $LD_BINARY $out/bin/cp $out/bin/patchelf $out/lib/*.so* .

for i in $out/bin/* $out/libexec/gcc/*/*/*; do
  if [ -L "$i" ]; then continue; fi
  if [ -z "${i##*/liblto*}" ]; then continue; fi
  echo patching "$i"
  LD_LIBRARY_PATH=. ./ld-*so ./patchelf --set-interpreter $LD_BINARY --set-rpath $out/lib --force-rpath "$i"
done

for i in $out/lib/lib*.so*; do
  if [ -L "$i" ]; then continue; fi
  echo patching "$i"
  LD_LIBRARY_PATH=. ./ld-*so ./patchelf --set-rpath $out/lib --force-rpath "$i" || true
done

LD_LIBRARY_PATH=. ./ld-*so $out/bin/mv $out/bin $out/sbin
export PATH="$out"/sbin
mkdir -p "$out"/bin "$compiler"/bin

# Fix the libc linker script.
for file in "$out"/lib/*; do
  if head -n 1 "$file" | grep -q '^/\*'; then
    sed "s,/nix/store/e*-[^/]*,$out,g" "$file" >"$file.tmp"
    mv "$file.tmp" "$file"
  fi
done

# Provide some additional symlinks.
ln -s bash $out/bin/sh

# Provide fgrep/egrep.
echo "#! $out/bin/sh" > $out/bin/egrep
echo "exec $out/bin/grep -E \"\$@\"" >> $out/bin/egrep
echo "#! $out/bin/sh" > $out/bin/fgrep
echo "exec $out/bin/grep -F \"\$@\"" >> $out/bin/fgrep

chmod +x $out/bin/egrep $out/bin/fgrep

# Link all of the needed tools
for util in $BINS; do
  [ -e "$out"/bin/$util ] && continue
  if [ ! -e "$out"/sbin/$util ]; then
    echo "Failed to find: $util" >&2
    exit 1
  fi
  ln -sv ../sbin/$util "$out"/bin/$util
done
for util in $COMPILERS; do
  [ -e "$compiler"/bin/$util ] && continue
  if [ ! -e "$out"/sbin/$util ]; then
    echo "Failed to find: $util" >&2
    exit 1
  fi
  ln -sv "$out"/sbin/$util "$compiler"/bin/$util
done

# Create a separate glibc
mkdir -p $glibc
ln -s $out/lib $glibc/lib
ln -s $out/include-glibc $glibc/include

# Make sure the cc-wrapper picks up the right thing
mkdir -p "$glibc"/nix-support
cxxinc="$(dirname "$(dirname "$out"/include/c++/*/*/bits/c++config.h)")"
echo "-idirafter $cxxinc" >>"$glibc"/nix-support/cxxflags-compile
echo "-idirafter $(dirname "$cxxinc")" >>"$glibc"/nix-support/cxxflags-compile
gccinc="$glibc"/lib/gcc/*/*/include
echo "-idirafter $gccinc" >>"$glibc"/nix-support/cflags-compile
echo "-idirafter $gccinc-fixed" >>"$glibc"/nix-support/cflags-compile
echo "-idirafter $glibc/include" >>"$glibc"/nix-support/cflags-compile
echo "-B$glibc/lib" >>"$glibc"/nix-support/cflags-compile
dyld="$glibc"/lib/ld-*.so
echo "-dynamic-linker $dyld" >>"$glibc"/nix-support/ldflags-before
echo "-L$glibc/lib" >>"$glibc"/nix-support/ldflags
