# This file defines the source of Rust / cargo's crates registry
#
# buildRustPackage will automatically download dependencies from the registry
# version that we define here. If you're having problems downloading / finding
# a Rust library, try updating this to a newer commit.

{ runCommand, fetchFromGitHub, git }:

let
  version = "2016-04-08";
  rev = "abf1c56651022ac429637bf781bd987ad250efa4";

  src = fetchFromGitHub {
    inherit rev;
    owner = "rust-lang";
    repo = "crates.io-index";
    sha256 = "ee8600865cb7412b4ae2e9abdb58ea660dcf227e4e44d8a9cd875575a8c1b51b";
  };

in

runCommand "rustRegistry-${version}-${builtins.substring 0 7 rev}" {} ''
  # For some reason, cargo doesn't like fetchgit's git repositories, not even
  # if we set leaveDotGit to true, set the fetchgit branch to 'master' and clone
  # the repository (tested with registry rev
  # 965b634156cc5c6f10c7a458392bfd6f27436e7e), failing with the message:
  #
  # "Target OID for the reference doesn't exist on the repository"
  #
  # So we'll just have to create a new git repository from scratch with the
  # contents downloaded with fetchgit...

  mkdir -p $out
  mkdir -p "$TMPDIR/unpack"

  cd "$TMPDIR/unpack"
  unpackFile "${src}"

  cd *
  mv * $out
  cd $out

  git="${git}/bin/git"

  $git init
  $git config --local user.email "example@example.com"
  $git config --local user.name "example"
  $git add .
  $git commit -m 'Rust registry commit'
''
