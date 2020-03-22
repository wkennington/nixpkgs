{ stdenv
, cc
, hostcc
, fetchurl
, lib

, ncurses
, readline

, type ? "full"
}:

let
  inherit (lib)
    attrNames
    filter
    flip
    length
    mapAttrsToList
    optionals
    optionalAttrs
    optionalString;

  patchSha256s = import ./patches.nix;

  version = "5.0";
in
stdenv.mkDerivation rec {
  name = "bash-${type}-${version}-p${toString (length (attrNames patchSha256s))}";

  src = fetchurl {
    url = "mirror://gnu/bash/bash-${version}.tar.gz";
    sha256 = "0kgvfwqdcd90waczf4gx39xnrxzijhjrzyzv7s8v4w31qqm0za5l";
  };

  nativeBuildInputs = [
    cc
    hostcc
  ];

  buildInputs = optionals (type == "full") [
    ncurses
    readline
  ];

  patchFlags = [
    "-p0"
  ];

  patches = flip mapAttrsToList patchSha256s (name: sha256: fetchurl {
    inherit name sha256;
    url = "mirror://gnu/bash/bash-${version}-patches/${name}";
  });

  postPatch = optionalString (type == "small") ''
    # Make sure we don't build readline
    find lib/readline -name '*'.c -delete
  '';

  preBuild = ''
    export CC_WRAPPER_CFLAGS+=' -DSYS_BASHRC="/etc/${passthru.systemBashrcName}"'
    export CC_WRAPPER_CFLAGS+=' -DSYS_BASH_LOGOUT="/etc/${passthru.systemBashlogoutName}"'
    export CC_WRAPPER_CFLAGS+=' -DDEFAULT_PATH_VALUE="/no-such-path"'
    export CC_WRAPPER_CFLAGS+=' -DSTANDARD_UTILS_PATH="/no-such-path"'
    export CC_WRAPPER_CFLAGS+=' -DNON_INTERACTIVE_LOGIN_SHELLS'
    export CC_WRAPPER_CFLAGS+=' -DSSH_SOURCE_BASHRC'
  '';

  configureFlags = optionals (type == "small") [
    "--disable-bang-history"
    "--disable-readline"
    "--disable-history"
  ] ++ optionals (type == "full") [
    "--with-installed-readline=${readline}"
  ];

  postInstall = ''
    ln -s bash "$bin/bin/sh"
  '';

  preFixup = ''
    rm -rv "$bin"/include
    rm -rv "$bin"/lib

    # Remove impurities
    rm -v "$bin"/bin/bashbug
  '';

  postFixup = ''
    mkdir -p "$bin"/share2
  '' + optionalString (type == "full") ''
    mv "$bin"/share/locale "$bin"/share2
  '' + ''
    rm -rv "$bin"/share
    mv "$bin"/share2 "$bin"/share
  '';

  outputs = [
    "bin"
  ] ++ optionals (type == "full") [
    "man"
  ];

  outputChecks = {
    bin.disallowedRequisites = optionals (type == "full") [ "man" ];
  } // optionalAttrs (type == "full") {
    man.allowedReferences = [ ];
  };

  passthru = rec {
    shellPath = "/bin/bash";
    systemBashrcName = "bash.bashrc";
    systemBashlogoutName = "bash.bash_logout";
  };

  meta = with lib; {
    description = "The standard GNU Bourne again shell";
    homepage = http://www.gnu.org/software/bash/;
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux ++
      x86_64-linux ++
      powerpc64le-linux;
  };
}
