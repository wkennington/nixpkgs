# The Nixpkgs CC is not directly usable, since it doesn't know where
# the C library and standard header files are. Therefore the compiler
# produced by that package cannot be installed directly in a user
# environment and used from the command line. So we use a wrapper
# script that sets up the right environment variables so that the
# compiler and the linker just "work".

{ name ? "", stdenv, nativeTools, nativeLibc, nativePrefix ? ""
, cc ? null, libc ? null, linux-headers ? null, libcxx ? null
, libgcc ? null, libidn2 ? null, binutils ? null, coreutils ? null
, shell ? stdenv.shell, gnugrep ? null
, extraPackages ? [], extraBuildCommands ? ""
}:

with stdenv.lib;

assert nativeTools -> nativePrefix != "";
assert !nativeTools ->
  cc != null && binutils != null && coreutils != null && gnugrep != null;
assert !nativeLibc -> libc != null;

let

  ccVersion = (builtins.parseDrvName cc.name).version;
  ccName = (builtins.parseDrvName cc.name).name;

  inherit (stdenv.lib.platforms)
    i686-linux
    x86_64-linux;

  isGlibc = (libc.impl or "") == "glibc";

in

stdenv.mkDerivation {
  name =
    (if name != "" then name else ccName + "-wrapper") +
    (if cc != null && ccVersion != "" then "-" + ccVersion else "");

  preferLocalBuild = true;

  inherit cc shell;

  optFlags =
    if cc.isGNU or false then
      if [ stdenv.targetSystem ] == x86_64-linux || [ stdenv.targetSystem ] == i686-linux then [
        "-mmmx"
        "-msse"
        "-msse2"
        "-msse3"
        "-mssse3"
        "-msse4"
        "-msse4.1"
        "-msse4.2"
        "-maes"
        "-mpclmul"
      ] else
        throw "Unknown optimization level for ${stdenv.targetSystem}"
    else  # TODO(wkennington): Figure out optimization flags for clang
      [ ];

  libc = if nativeLibc then null else libc;
  binutils = if nativeTools then "" else binutils;
  # The wrapper scripts use 'cat' and 'grep', so we may need coreutils
  # and gnugrep.
  coreutils = if nativeTools then "" else coreutils;
  gnugrep = if nativeTools then "" else gnugrep;

  passthru = rec {
    inherit nativeTools nativeLibc nativePrefix;
    runtimeLibcLibs = [
      libc
    ] ++ optionals isGlibc [
      libgcc
      libidn2
    ];
    runtimeLibcxxLibs = runtimeLibcLibs ++ [
      libcxx
    ];
  };

  buildCommand =
    ''
      mkdir -p $out/bin $out/nix-support

      wrap() {
        local dst="$1"
        local wrapper="$2"
        export prog="$3"
        substituteAll "$wrapper" "$out/bin/$dst"
        chmod +x "$out/bin/$dst"
      }
    ''

    + optionalString (!nativeLibc) ''
      dynamicLinker="$libc/lib/$dynamicLinker"
      echo $dynamicLinker > $out/nix-support/dynamic-linker

      if [ -e $libc/lib/32/ld-linux.so.2 ]; then
        echo $libc/lib/32/ld-linux.so.2 > $out/nix-support/dynamic-linker-m32
      fi

      # The dynamic linker is passed in `ldflagsBefore' to allow
      # explicit overrides of the dynamic linker by callers to gcc/ld
      # (the *last* value counts, so ours should come first).
      echo "-dynamic-linker" $dynamicLinker > $out/nix-support/libc-ldflags-before
    ''

    + optionalString (isGlibc && libgcc != null) ''
      echo -n " -L${libgcc}/lib --no-as-needed -lgcc_s" >>"$out"/nix-support/libc-ldflags-dynamic
    ''

    + optionalString (isGlibc && libidn2 != null) ''
      echo -n " -L${libidn2}/lib --no-as-needed -lidn2" >>"$out"/nix-support/libc-ldflags-dynamic
    ''

    + optionalString (!nativeLibc) ''
      # The "-B$libc/lib/" flag is a quick hack to force gcc to link
      # against the crt1.o from our own glibc, rather than the one in
      # /usr/lib.  (This is only an issue when using an `impure'
      # compiler/linker, i.e., one that searches /usr/lib and so on.)
      echo -n "-B$libc/lib/ -idirafter $libc/include" >"$out"/nix-support/libc-cflags
      ${optionalString (linux-headers != null) ''
        echo -n " -idirafter ${linux-headers}/include" >>"$out"/nix-support/libc-cflags
      ''}
      echo "" >> $out/nix-support/libc-cflags
      echo "-L$libc/lib" > $out/nix-support/libc-ldflags

      echo $libc > $out/nix-support/orig-libc
    ''

    + (if nativeTools then ''
      ccPath="${nativePrefix}/bin"
      ldPath="${nativePrefix}/bin"
    '' else ''
      echo $cc > $out/nix-support/orig-cc

      # GCC shows $cc/lib in `gcc -print-search-dirs', but not
      # $cc/lib64 (even though it does actually search there...)..
      # This confuses libtool.  So add it to the compiler tool search
      # path explicitly.
      if [ -e "$cc/lib64" -a ! -L "$cc/lib64" ]; then
        ccLDFlags+=" -L$cc/lib64"
        ccCFlags+=" -B$cc/lib64"
      fi
      ccLDFlags+=" -L$cc/lib"

      # Find the gcc libraries path (may work only without multilib).
      ${optionalString cc.langAda or false ''
        basePath=`echo $cc/lib/*/*/*`
        ccCFlags+=" -B$basePath -I$basePath/adainclude"
        gnatCFlags="-aI$basePath/adainclude -aO$basePath/adalib"
        echo "$gnatCFlags" > $out/nix-support/gnat-cflags
      ''}

      if [ -e $ccPath/clang ]; then
        # Need files like crtbegin.o from gcc
        # It's unclear if these will ever be provided by an LLVM project
        ccCFlags="$ccCFlags -B$basePath"
        ccCFlags="$ccCFlags -isystem$cc/lib/clang/$ccVersion/include"
      fi

      echo "$ccLDFlags" > $out/nix-support/cc-ldflags
      echo "$ccCFlags" > $out/nix-support/cc-cflags

      ccPath="$cc/bin"
      ldPath="$binutils/bin"

      # Determine the prefix mapping flag
      export prefixMapFlag="-fdebug-prefix-map"
      if echo "" | "$ccPath"/cc -ffile-prefix-map=hi=hi -E - >/dev/null; then
        prefixMapFlag="-ffile-prefix-map"
      fi

      # Determine if we have stack clash protection
      export canStackClashProtect=0
      if echo "" | "$ccPath"/cc -fstack-clash-protection -E - >/dev/null; then
        canStackClashProtect=1
      fi

      # Propagate the wrapped cc so that if you install the wrapper,
      # you get tools like gcov, the manpages, etc. as well (including
      # for binutils and Glibc).
      echo $cc $binutils $libc > $out/nix-support/propagated-user-env-packages

      echo $cc $binutils $libc ${toString extraPackages} > $out/nix-support/propagated-native-build-inputs
    '')

    + ''
      # Create a symlink to as (the assembler).  This is useful when a
      # cc-wrapper is installed in a user environment, as it ensures that
      # the right assembler is called.
      if [ -e $ldPath/as ]; then
        ln -s $ldPath/as $out/bin/as
      fi

      wrap ld ${./ld-wrapper.sh} ''${ld:-$ldPath/ld}

      if [ -e $binutils/bin/ld.gold ]; then
        wrap ld.gold ${./ld-wrapper.sh} $binutils/bin/ld.gold
      fi

      if [ -e $binutils/bin/ld.bfd ]; then
        wrap ld.bfd ${./ld-wrapper.sh} $binutils/bin/ld.bfd
      fi

      export real_cc=cc
      export real_cxx=c++
      export default_cxx_stdlib_compile=""
      export default_cxx_stdlib_link=""
    ''

    + optionalString (libcxx != null) ''
      default_cxx_stdlib_compile="-isystem $(echo "${libcxx}"/include/c++/*)"
      default_cxx_stdlib_link="-L${libcxx}/lib"
    ''

    + ''
      if [ -e $ccPath/gcc ]; then
        wrap gcc ${./cc-wrapper.sh} $ccPath/gcc
        ln -s gcc $out/bin/cc
        export real_cc=gcc
        export real_cxx=g++
      elif [ -e $ccPath/clang ]; then
        wrap clang ${./cc-wrapper.sh} $ccPath/clang
        ln -s clang $out/bin/cc
        export real_cc=clang
        export real_cxx=clang++
      fi

      if [ -e $ccPath/g++ ]; then
        wrap g++ ${./cc-wrapper.sh} $ccPath/g++
        ln -s g++ $out/bin/c++
      elif [ -e $ccPath/clang++ ]; then
        wrap clang++ ${./cc-wrapper.sh} $ccPath/clang++
        ln -s clang++ $out/bin/c++
      fi

      if [ -e $ccPath/cpp ]; then
        wrap cpp ${./cc-wrapper.sh} $ccPath/cpp
      fi
    ''

    + optionalString cc.langFortran or false ''
      wrap gfortran ${./cc-wrapper.sh} $ccPath/gfortran
      ln -sv gfortran $out/bin/g77
      ln -sv gfortran $out/bin/f77
    ''

    + optionalString cc.langJava or false ''
      wrap gcj ${./cc-wrapper.sh} $ccPath/gcj
    ''

    + optionalString cc.langGo or false ''
      wrap gccgo ${./cc-wrapper.sh} $ccPath/gccgo
    ''

    + optionalString cc.langAda or false ''
      wrap gnatgcc ${./cc-wrapper.sh} $ccPath/gnatgcc
      wrap gnatmake ${./gnat-wrapper.sh} $ccPath/gnatmake
      wrap gnatbind ${./gnat-wrapper.sh} $ccPath/gnatbind
      wrap gnatlink ${./gnatlink-wrapper.sh} $ccPath/gnatlink
    ''

    + optionalString cc.langVhdl or false ''
      ln -s $ccPath/ghdl $out/bin/ghdl
    ''

    + ''
      substituteAll ${./setup-hook.sh} $out/nix-support/setup-hook.tmp
      cat $out/nix-support/setup-hook.tmp >> $out/nix-support/setup-hook
      rm $out/nix-support/setup-hook.tmp

      substituteAll ${./add-flags} $out/nix-support/add-flags.sh
      cp -p ${./utils.sh} $out/nix-support/utils.sh
    ''
    + extraBuildCommands;

  # The dynamic linker has different names on different Linux platforms.
  dynamicLinker =
    if !nativeLibc then
      (if stdenv.system == "i686-linux" then "ld-linux.so.2" else
       if stdenv.system == "x86_64-linux" then "ld-linux-x86-64.so.2" else
       abort "Don't know the name of the dynamic linker for this platform.")
    else "";

  crossAttrs = {
    shell = shell.crossDrv + shell.crossDrv.shellPath;
    libc = stdenv.ccCross.libc;
    coreutils = coreutils.crossDrv;
    binutils = binutils.crossDrv;
    cc = cc.crossDrv;
    #
    # This is not the best way to do this. I think the reference should be
    # the style in the gcc-cross-wrapper, but to keep a stable stdenv now I
    # do this sufficient if/else.
    dynamicLinker =
      (if stdenv.lib.hasSuffix "pc-gnu" stdenv.cross.config then "ld.so.1" else
       abort "don't know the name of the dynamic linker for this platform");
  };

  meta =
    let cc_ = if cc != null then cc else {}; in
    (if cc_ ? meta then removeAttrs cc.meta ["priority"] else {}) //
    { description =
        stdenv.lib.attrByPath ["meta" "description"] "System C compiler" cc_
        + " (wrapper script)";
    };
}
