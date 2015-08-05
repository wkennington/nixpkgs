{ callPackage, fetchgit, ... } @ args:

callPackage ./generic.nix (args // rec {
  version = "2015-07-28";

  src = fetchgit {
    url = "git://git.gniibe.org/gnuk/gnuk.git";
    rev = "ec2a2e049f3074e5327e6c47140e582e883d1c8a";
    sha256 = "0y7g84klhby8gibi0zzlm829jh8bi9h9fdjmdjfr0rzbk20fi263";
  };
})
