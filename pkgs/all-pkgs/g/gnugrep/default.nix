{ stdenv
, fetchurl
, pcre

, type ? "full"
}:

let
  inherit (stdenv.lib)
    optionalString
    optionals;

  version = "3.3";

  tarballUrls = version: [
    "mirror://gnu/grep/grep-${version}.tar.xz"
  ];
in
stdenv.mkDerivation rec {
  name = "gnugrep-${version}";

  src = fetchurl {
    urls = tarballUrls version;
    hashOutput = false;
    sha256 = "b960541c499619efd6afe1fa795402e4733c8e11ebf9fafccc0bb4bccdc5b514";
  };

  buildInputs = [
    pcre
  ];

  # Fix reference to sh in bootstrap-tools, and invoke grep via
  # absolute path rather than looking at argv[0].
  postInstall = ''
    rm "$bin"/bin/egrep "$bin"/bin/fgrep
    echo "#! /bin/sh" > "$bin"/bin/egrep
    echo "exec '$bin'/bin/grep -E \"\$@\"" >> "$bin"/bin/egrep
    echo "#! /bin/sh" > "$bin"/bin/fgrep
    echo "exec '$bin'/bin/grep -F \"\$@\"" >> "$bin"/bin/fgrep
    chmod +x "$bin"/bin/egrep "$bin"/bin/fgrep
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

  dontPatchShebangs = true;

  passthru = {
    srcVerification = fetchurl rec {
      failEarly = true;
      urls = tarballUrls "3.3";
      inherit (src) outputHashAlgo;
      outputHash = "b960541c499619efd6afe1fa795402e4733c8e11ebf9fafccc0bb4bccdc5b514";
      fullOpts = {
        pgpsigUrls = map (n: "${n}.sig") urls;
        pgpKeyFingerprint = "155D 3FC5 00C8 3448 6D1E  EA67 7FD9 FCCB 000B EEEE";
      };
    };
  };

  meta = with stdenv.lib; {
    homepage = http://www.gnu.org/software/grep/;
    description = "GNU implementation of the Unix grep command";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      i686-linux
      ++ x86_64-linux;
  };
}
