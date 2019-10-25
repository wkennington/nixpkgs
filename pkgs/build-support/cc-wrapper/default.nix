# The Nixpkgs CC is not directly usable, since it doesn't know where
# the C library and standard header files are. Therefore the compiler
# produced by that package cannot be installed directly in a user
# environment and used from the command line. So we use a wrapper
# script that sets up the right environment variables so that the
# compiler and the linker just "work".

{ stdenv
, lib
, fetchurl
, srco ? null
}:

lib.makeOverridable
({ compiler
, tools ? [ ]
, inputs ? [ ]
, type ? "host"
}:

let
  inherit (lib)
    concatStringsSep
    optionalString;

  inherit (compiler)
    impl
    target
    prefixMapFlag;

  typefx = {
    "build" = "_FOR_BUILD";
    "host" = "";
  }."${type}";

  targetfx = if target == null then "" else "${target}-";

  tooldirs = map (n: "${n}/bin") (tools ++ [ compiler ]);

  version = "0.1";
in
assert target != "";
stdenv.mkDerivation rec {
  name = "cc-wrapper-${version}";

  src = if srco != null then srco else fetchurl {
    url = "https://github.com/triton/cc-wrapper/releases/download/v${version}/${name}.tar.xz";
    sha256 = "1906ba61c39e79dc1a05561d7fd53e283b9fb4686ba7361b4697826e37a4dfc5";
  };

  preConfigure = ''
    configureFlagsArray+=("--with-pure-prefixes=$NIX_STORE")

    exists() {
      [ -h "$1" -o -e "$1" ]
    }

    declare -gA vars=()
    maybeAppend() {
      local file="$1"
      local input="$2"

      exists "$input"/nix-support/"$file" || return 0
      vars["$file"]+=" $(tr '\n' ' ' <"$input"/nix-support/"$file")"
    }

    for inc in "$compiler" $tools $inputs; do
      maybeAppend cflags "$inc"
      maybeAppend cxxflags "$inc"
      maybeAppend cflags-link "$inc"
      maybeAppend cxxflags-link "$inc"
      maybeAppend ldflags "$inc"
      maybeAppend ldflags-before "$inc"
      maybeAppend ldflags-dynamic "$inc"
    done

    for var in "''${!vars[@]}"; do
      configureFlagsArray+=("--with-$var=''${vars["$var"]}")
    done
  '';

  configureFlags = [
    (optionalString (target != null) "--target=${target}")
    "--disable-tests"
    "--with-tooldirs=${concatStringsSep ":" tooldirs}"
    "--with-preferred-compiler=${impl}"
    "--with-prefix-map-flag-${impl}=${prefixMapFlag}"
    "--with-var-prefix=CC_WRAPPER${typefx}"
    "--with-build-dir-env-var=NIX_BUILD_TOP"
  ];

  postInstall = ''
    mkdir -p "$out"/nix-support
    for var in "''${!vars[@]}"; do
      echo "''${vars["$var"]}" >"$out"/nix-support/"$var"
    done
  '';

  preFixup = ''
    export targetbin="$(find "$out"/lib -name bin)"
  '';

  inherit
    compiler
    tools
    inputs
    targetfx
    type
    typefx;

  setupHook = ./setup-hook.sh;

  meta = with lib; {
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux ++
      x86_64-linux ++
      powerpc64le-linux;
  };
})
