{ stdenv
, lib
, fetchurl
, gettext

, coreutils
, kernel
, pciutils
}:

stdenv.mkDerivation {
  name = "bpftool-${kernel.version}";

  src = kernel.src;

  patches = kernel.patches;

  nativeBuildInputs = [
    gettext
  ];

  buildInputs = [
    pciutils
  ];

  postPatch = ''
    cd tools/bpf/bpftool
  '';

  preBuild = ''
    makeFlagsArray+=(
      "prefix=$out"
      "bash_compdir=$out/share/bash-completion/completions"
    )
  '';

  installTargets = [
    "install"
    "doc-install"
  ];

  meta = with lib; {
    description = "Tool to examine and tune power saving features";
    homepage = https://www.kernel.org.org/;
    license = licenses.gpl2;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
