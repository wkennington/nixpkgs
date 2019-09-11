echo Unpacking the bootstrap tools...
export PATH=/bin:/usr/bin:/run/current-system/sw/bin
if mkdir --help >/dev/null 2>&1; then
  echo Using native tooling
  mkdir -p "$out"/bin "$glibc"
  for util in awk as ar basename bash bzip2 cat chmod cksum cmp cp cpp cut date \
      diff dirname egrep env expr false fgrep find gawk gcc g++ grep gzip head id \
      install join ld ln ls make mkdir mktemp mv nl nproc objcopy objdump od patch \
      ranlib readelf readlink rm rmdir sed sh sleep sort stat strip tar tail \
      tee test touch tsort tr true xz xargs uname uniq wc; do
    oldifs="$IFS"
    IFS=:
    found=
    for p in $PATH; do
      if [ -e "$p"/$util ]; then
        found="$p"/$util
        break
      fi
    done
    if [ -z "$found" ]; then
      echo "Failed to find: $util"
      exit 1
    fi
    ln -sv "$found" "$out"/bin/$util
    IFS="$oldifs"
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

# Fix the libc linker script.
export PATH=$out/bin
for file in "$out"/lib/*; do
  if head -n 1 "$file" | grep -q '^/\*'; then
    sed "s,/nix/store/e*-[^/]*,$out,g" "$file" >"$file.tmp"
    mv "$file.tmp" "$file"
  fi
done

# Provide some additional symlinks.
ln -s bash $out/bin/sh
ln -s bzip2 $out/bin/bunzip2

# Provide a gunzip script.
cat > $out/bin/gunzip <<EOF
#!$out/bin/sh
exec $out/bin/gzip -d "\$@"
EOF
chmod +x $out/bin/gunzip

# Provide fgrep/egrep.
echo "#! $out/bin/sh" > $out/bin/egrep
echo "exec $out/bin/grep -E \"\$@\"" >> $out/bin/egrep
echo "#! $out/bin/sh" > $out/bin/fgrep
echo "exec $out/bin/grep -F \"\$@\"" >> $out/bin/fgrep

chmod +x $out/bin/egrep $out/bin/fgrep

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
