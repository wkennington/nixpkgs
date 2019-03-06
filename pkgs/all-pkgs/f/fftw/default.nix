{ stdenv
, fetchurl
, lib

, precision
}:

let
  inherit (stdenv)
    targetSystem;
  inherit (lib)
    boolEn
    elem
    optionals
    platforms;

  version = "3.3.8";
in

assert elem precision [
  "single" # libfftw3f
  "double" # libfftw3
  "long-double" # libfftw3l
  "quad-precision" # libfftw3q
];

stdenv.mkDerivation rec {
  name = "fftw-${precision}-${version}";

  src = fetchurl rec {
    url = "http://www.fftw.org/fftw-${version}.tar.gz";
    multihash = "QmTWiByEtQ9DnuVnMESfnT6jgiGYRtuTy33xKY1FDQ8kXg";
    hashOutput = false;
    sha256 = "6113262f6e92c5bd474f2875fa1b01054c4ad5040f6b0da7c03c98821d9ae303";
  };

  configureFlags = [
    "--help"
    "--${boolEn (precision == "single")}-single"
    "--${boolEn (precision == "single")}-float"
    ###"--${boolEn (precision == "double")}-double"
    "--${boolEn (precision == "long-double")}-long-double"
    "--${boolEn (precision == "quad-precision")}-quad-precision"
    "--disable-fortran"
    "--enable-openmp"
    "--enable-threads"
  ];

  # Since this is used in a lot of shared libraries we need fPIC
  NIX_CFLAGS_COMPILE = [
    "-fPIC"
  ];

  passthru = {
    srcVerification = fetchurl {
      inherit (src)
        outputHash
        outputHashAlgo
        urls;
      md5Url = map (n: "${n}.md5sum") src.urls;
      failEarly = true;
    };
  };

  meta = with lib; {
    description = "Library for Fast Discrete Fourier Transform";
    homepage = http://www.fftw.org/;
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [
      codyopel
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
