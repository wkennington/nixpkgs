{ stdenv, fetchgit, gnat, spark-ada }:

stdenv.mkDerivation {
  name = "muen-git-";

  src = fetchgit {
    url = "http://git.codelabs.ch/git/muen.git";
    rev = "sdfsdf";
    sha256 = "1nhi5m0nnrb7v2gqpa3181p32k5hm5jwkf647vs80r14750gxlpd";
  };

  buildInputs = [ gnat spark-ada ];

  outputs = [ "iso" "pxe" ];

  buildPhase = ''
    make
    make iso
  '';

  installPhase = ''
    mkdir -p $iso $pxe
    cp emulate/muen.iso $iso/muen.iso
  '';

  meta = with stdenv.lib; {
    homepage = http://muen.codelabs.ch;
    description = "a specialized microkernel that provides virtualized execution environments";
    license = licenses.gpl3;
    platforms = platforms.unix;
  };
}
