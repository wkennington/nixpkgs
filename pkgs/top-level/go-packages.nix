/* This file defines the composition for Go packages. */

{ overrides, stdenv, go, buildGoPackage, git
, fetchgit, fetchhg, fetchurl, fetchzip, fetchFromGitHub, fetchFromBitbucket, fetchbzr, pkgs }:

let
  self = _self // overrides; _self = with self; {

  inherit go buildGoPackage;

  fetchGxPackage = { multihash, sha256 }: stdenv.mkDerivation {
    name = "gx-src-${multihash}";
    buildCommand = ''
      if ! [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        echo "Missing /etc/ssl/certs/ca-certificates.crt" >&2
        echo "Please update to a version of nix which supports ssl." >&2
        exit 1
      fi
      gx get -o $out "${multihash}"
    '';
    buildInputs = [ gx.bin ];
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = sha256;
    preferLocalBuild = true;
  };

  buildFromGitHub = { rev, date ? null, owner, repo, sha256, name ? repo, goPackagePath ? "github.com/${owner}/${repo}", ... }@args: buildGoPackage (args // {
    inherit rev goPackagePath;
    name = "${name}-${if date != null then date else if builtins.stringLength rev != 40 then rev else stdenv.lib.strings.substring 0 7 rev}";
    src  = fetchFromGitHub { inherit rev owner repo sha256; };
  });

  buildFromGoogle = { rev, date ? null, repo, sha256, name ? repo, goPackagePath ? "google.golang.org/${repo}", ... }@args: buildGoPackage (args // {
    inherit rev goPackagePath;
    name = "${name}-${if date != null then date else if builtins.stringLength rev != 40 then rev else stdenv.lib.strings.substring 0 7 rev}";
    src  = fetchzip {
      url = "https://code.googlesource.com/go${repo}/+archive/${rev}.tar.gz";
      inherit sha256;
      stripRoot = false;
    };
  });

  ## OFFICIAL GO PACKAGES

  appengine = buildFromGitHub {
    rev = "6a436539be38c296a8075a871cc536686b458371";
    date = "2016-02-05";
    owner = "golang";
    repo = "appengine";
    sha256 = "0fgxfpfb4mla89yk45rgpsmdkbjnb7ck8dkwc24x879bhpz545kh";
    goPackagePath = "google.golang.org/appengine";
    propagatedBuildInputs = [ protobuf net ];
  };

  crypto = buildFromGitHub {
    rev = "1f22c0103821b9390939b6776727195525381532";
    date = "2016-01-26";
    owner    = "golang";
    repo     = "crypto";
    sha256 = "1acy12f396sr3lrnbcnym5q72qnlign5bagving41qijzjnc219m";
    goPackagePath = "golang.org/x/crypto";
    goPackageAliases = [
      "code.google.com/p/go.crypto"
      "github.com/golang/crypto"
    ];
  };

  glog = buildFromGitHub {
    rev = "23def4e6c14b4da8ac2ed8007337bc5eb5007998";
    date = "2016-01-25";
    owner  = "golang";
    repo   = "glog";
    sha256 = "0jb2834rw5sykfr937fxi8hxi2zy80sj2bdn9b3jb4b26ksqng30";
  };

  codesearch = buildFromGitHub {
    rev    = "a45d81b686e85d01f2838439deaf72126ccd5a96";
    date   = "2015-06-17";
    owner  = "google";
    repo   = "codesearch";
    sha256 = "12bv3yz0l3bmsxbasfgv7scm9j719ch6pmlspv4bd4ix7wjpyhny";
  };

  image = buildFromGitHub {
    rev = "7c492694a6443a92fd349fda0c4c7b587040f161";
    date = "2016-01-02";
    owner = "golang";
    repo = "image";
    sha256 = "05c5qrph5r5ikzxw1mlgihx8396hawv38q2syjvwbxdiib9gfg9k";
    goPackagePath = "golang.org/x/image";
    goPackageAliases = [ "github.com/golang/image" ];
  };

  net = buildFromGitHub {
    rev = "8968c61983e8f51a91b8c0ef25bf739278c89634";
    date = "2016-02-11";
    owner  = "golang";
    repo   = "net";
    sha256 = "1lwlscq2z3srphfga3pnlp1hlp2w5mp7f2vy4mnizcwsybgcnkyq";
    goPackagePath = "golang.org/x/net";
    goPackageAliases = [
      "code.google.com/p/go.net"
      "github.com/hashicorp/go.net"
      "github.com/golang/net"
    ];
    propagatedBuildInputs = [ text crypto ];
  };

  oauth2 = buildFromGitHub {
    rev = "8a57ed94ffd43444c0879fe75701732a38afc985";
    date = "2015-12-29";
    owner = "golang";
    repo = "oauth2";
    sha256 = "10pxnbsy1lnx7a1x6g3cna5gdm11aal1r446dpmpgj94xiw96mxv";
    goPackagePath = "golang.org/x/oauth2";
    goPackageAliases = [ "github.com/golang/oauth2" ];
    propagatedBuildInputs = [ net gcloud-golang-compute-metadata ];
  };


  protobuf = buildFromGitHub {
    rev = "0dfe8f37844c14cb32c7247925270e0f7ba90973";
    date = "2016-02-11";
    owner = "golang";
    repo = "protobuf";
    sha256 = "1y31sqwcjmbxyad4ain22fmrii4xrgii1kpl9x70h9shknz8n66k";
    goPackagePath = "github.com/golang/protobuf";
    goPackageAliases = [ "code.google.com/p/goprotobuf" ];
  };

  snappy = buildFromGitHub {
    rev = "cc71ae7cc5b621a5a0d6c776ca4c571ab629f495";
    date = "2016-02-13";
    owner  = "golang";
    repo   = "snappy";
    sha256 = "0y1d3fpz1dqkjbmxg1nwwaanjk37gm49arj6nadxdq56hdcsjwm9";
    goPackageAliases = [ "code.google.com/p/snappy-go/snappy" ];
  };

  sys = buildFromGitHub {
    rev = "50c6bc5e4292a1d4e65c6e9be5f53be28bcbe28e";
    date = "2016-02-04";
    owner  = "golang";
    repo   = "sys";
    sha256 = "0v6a1qh4znxwx5zdfsp8hwa1jrvqas9k4m6iaf734izqngyq5vmw";
    goPackagePath = "golang.org/x/sys";
    goPackageAliases = [
      "github.com/golang/sys"
    ];
  };

  text = buildFromGitHub {
    rev = "07b9a78963006a15c538ec5175243979025fa7a8";
    date = "2016-02-11";
    owner = "golang";
    repo = "text";
    sha256 = "0qr8hhkkyw4zfqz8wpmhfz5ghjrzn78jdzh7icl4dmyyy0qb1hpn";
    goPackagePath = "golang.org/x/text";
    goPackageAliases = [ "github.com/golang/text" ];
  };

  tools = buildFromGitHub {
    rev = "608d57b3ae930138a65e85b64edf2ba1b3450b06";
    date = "2016-02-12";
    owner = "golang";
    repo = "tools";
    sha256 = "0d7cab4xl4byf98qghlwan20j46vsih28p28nzcyc3bj6i3a6chh";
    goPackagePath = "golang.org/x/tools";
    goPackageAliases = [ "code.google.com/p/go.tools" ];

    preConfigure = ''
      # Make the builtin tools available here
      mkdir -p $bin/bin
      eval $(go env | grep GOTOOLDIR)
      find $GOTOOLDIR -type f | while read x; do
        ln -sv "$x" "$bin/bin"
      done
      export GOTOOLDIR=$bin/bin
    '';

    excludedPackages = "\\("
      + stdenv.lib.concatStringsSep "\\|" ([ "testdata" ] ++ stdenv.lib.optionals (stdenv.lib.versionAtLeast go.meta.branch "1.5") [ "vet" "cover" ])
      + "\\)";

    buildInputs = [ appengine net ];

    # Do not copy this without a good reason for enabling
    # In this case tools is heavily coupled with go itself and embeds paths.
    allowGoReference = true;

    # Set GOTOOLDIR for derivations adding this to buildInputs
    postInstall = ''
      mkdir -p $bin/nix-support
      substituteAll ${../development/go-modules/tools/setup-hook.sh} $bin/nix-support/setup-hook.tmp
      cat $bin/nix-support/setup-hook.tmp >> $bin/nix-support/setup-hook
      rm $bin/nix-support/setup-hook.tmp
    '';
  };


  ## THIRD PARTY

  ace = buildFromGitHub {
    rev    = "899eede6af0d99400b2c8886d86fd8d351074d37";
    owner  = "yosssi";
    repo   = "ace";
    sha256 = "0xdzqfzaipyaa973j41yq9lbijw36kyaz523sw05kci4r5ivq4f5";
    buildInputs = [ gohtml ];
  };

  adapted = buildFromGitHub {
    rev = "eaea06aaff855227a71b1c58b18bc6de822e3e77";
    date = "2015-06-03";
    owner = "michaelmacinnis";
    repo = "adapted";
    sha256 = "0f28sn5mj48087zhjdrph2sjcznff1i1lwnwplx32bc5ax8nx5xm";
    propagatedBuildInputs = [ sys ];
  };

  afero = buildFromGitHub {
    rev    = "90b5a9bd18a72dbf3e27160fc47acfaac6c08389";
    owner  = "spf13";
    repo   = "afero";
    sha256 = "1xqvbwny61j85psymcs8hggmqyyg4yq3q4cssnvnvbsl3aq8kn4k";
    propagatedBuildInputs = [ text ];
  };

  amber = buildFromGitHub {
    rev    = "144da19a9994994c069f0693294a66dd310e14a4";
    owner  = "eknkc";
    repo   = "amber";
    sha256 = "079wwdq4cn9i1vx5zik16z4bmghkc7zmmvbrp1q6y4cnpmq95rqk";
  };

  ansicolor = buildFromGitHub {
    date   = "2015-11-19";
    rev    = "a422bbe96644373c5753384a59d678f7d261ff10";
    owner  = "shiena";
    repo   = "ansicolor";
    sha256 = "1dcn8a9z6a5dxa2m3fkppnajcls8lanbl38qggkf646yi5qsk1hc";
  };

  asciinema = buildFromGitHub {
    rev = "v1.1.1";
    owner = "asciinema";
    repo = "asciinema";
    sha256 = "0k48k8815k433s25lh8my2swl89kczp0m2gbqzjlpy1xwmk06nxc";
  };

  asn1-ber = buildFromGitHub {
    rev = "v1.1";
    owner  = "go-asn1-ber";
    repo   = "asn1-ber";
    sha256 = "13p8s74kzklb5lklfpxwxb78rknihawv1civ4s9bfqx565010fwk";
    goPackageAliases = [
      "github.com/nmcclain/asn1-ber"
      "github.com/vanackere/asn1-ber"
      "gopkg.in/asn1-ber.v1"
    ];
  };

  assertions = buildGoPackage rec {
    version = "1.5.0";
    name = "assertions-${version}";
    goPackagePath = "github.com/smartystreets/assertions";
    src = fetchurl {
      name = "${name}.tar.gz";
      url = "https://github.com/smartystreets/assertions/archive/${version}.tar.gz";
      sha256 = "1s4b0v49yv7jmy4izn7grfqykjrg7zg79dg5hsqr3x40d5n7mk02";
    };
    buildInputs = [ oglematchers ];
    propagatedBuildInputs = [ goconvey ];
    doCheck = false;
  };

  aws-sdk-go = buildFromGitHub {
    rev = "v1.1.2";
    owner  = "aws";
    repo   = "aws-sdk-go";
    sha256 = "1vrr53syabv59iq7spiwrig5wl2fdwxpqa49x0sww18gzphzyrg7";
    buildInputs = [ testify go-jmespath ini gucumber tools ];
    propagatedBuildInputs = [ go-ini ];

    preBuild = ''
      pushd go/src/$goPackagePath
      make generate
      popd
    '';
  };

  b = buildFromGitHub {
    date = "2016-02-10";
    rev = "47184dd8c1d2c7e7f87dae8448ee2007cdf0c6c4";
    owner  = "cznic";
    repo   = "b";
    sha256 = "1sdn73xv1l9hdiy57dhjlyrqs8xibb95lnm5jjycn5f9izjv5mba";
  };

  bigfft = buildFromGitHub {
    date = "2013-09-13";
    rev = "a8e77ddfb93284b9d58881f597c820a2875af336";
    owner = "remyoudompheng";
    repo = "bigfft";
    sha256 = "1h1jwfz5hbsdrf94h0x1h0dajcbklhgf58f5m0kphg4mzdaviq26";
  };

  bleve = buildFromGitHub {
    rev    = "fc34a97875840b2ae24517e7d746b69bdae9be90";
    date   = "2016-01-19";
    owner  = "blevesearch";
    repo   = "bleve";
    sha256 = "0ny7nvilrxmmzcdvpivwyrjkynnhc22c5gdrxzs421jly35jw8jx";
    buildFlags = [ "-tags all" ];
    propagatedBuildInputs = [ protobuf goleveldb kagome gtreap bolt text
     rcrowley_go-metrics bitset segment go-porterstemmer ];
  };

  binarydist = buildFromGitHub {
    rev    = "9955b0ab8708602d411341e55fffd7e0700f86bd";
    owner  = "kr";
    repo   = "binarydist";
    sha256 = "11wncbbbrdcxl5ff3h6w8vqfg4bxsf8709mh6vda0cv236flkyn3";
  };

  bitset = buildFromGitHub {
    rev    = "bb0da3785c4fe9d26f6029c77c8fce2aa4d0b291";
    date   = "2016-01-13";
    owner  = "willf";
    repo   = "bitset";
    sha256 = "1d4z2hjjs9jk6aysi4mf50p8lbbzag4ir4y1f0z4sz8gkwagh7b7";
  };

  blackfriday = buildFromGitHub {
    rev    = "d18b67ae0afd61dae240896eae1785f00709aa31";
    owner  = "russross";
    repo   = "blackfriday";
    sha256 = "1l78hz8k1ixry5fjw29834jz1q5ysjcpf6kx2ggjj1s6xh0bfzvf";
    propagatedBuildInputs = [ sanitized_anchor_name ];
  };

  bolt = buildFromGitHub {
    rev = "v1.1.0";
    owner  = "boltdb";
    repo   = "bolt";
    sha256 = "0722fn1y4nc6nmfvp408lqb16b5j0lpr397ss7qcgy5xp4x3l5j0";
  };

  bufio = buildFromGitHub {
    rev    = "24e7e48f60fc2d9e99e43c07485d9fff42051e66";
    owner  = "vmihailenco";
    repo   = "bufio";
    sha256 = "0x46qnf2f15v7m0j2dcb16raxjamk5rdc7hqwgyxfr1sqmmw3983";
  };

  bufs = buildFromGitHub {
    date   = "2014-08-18";
    rev    = "3dcccbd7064a1689f9c093a988ea11ac00e21f51";
    owner  = "cznic";
    repo   = "bufs";
    sha256 = "0w75wc15k0gayvj6fhnqgap1y2rhq51zvslhp3v4y1vcb11mbdw9";
  };

  cascadia = buildGoPackage rec {
    rev = "54abbbf07a45a3ef346ebe903e0715d9a3c19352"; #master
    name = "cascadia-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/andybalholm/cascadia";
    goPackageAliases = [ "code.google.com/p/cascadia" ];
    propagatedBuildInputs = [ net ];
    buildInputs = propagatedBuildInputs;
    doCheck = true;

    src = fetchFromGitHub {
      inherit rev;
      owner = "andybalholm";
      repo = "cascadia";
      sha256 = "1z21w6p5bp7mi2pvicvcqc871k9s8a6262pkwyjm2qfc859c203m";
    };
  };

  cast = buildFromGitHub {
    rev    = "ee815aaf958c707ad07547cd62150d973710f747";
    owner  = "spf13";
    repo   = "cast";
    sha256 = "144xwvmjbrv59zjj1gnq5j9qpy62dgyfamxg5l3smdwfwa8vpf5i";
    buildInputs = [ jwalterweatherman ];
  };

  check-v1 = buildGoPackage rec {
    rev = "871360013c92e1c715c2de6d06b54899468a8a2d";
    name = "check-v1-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "gopkg.in/check.v1";
    src = fetchgit {
      inherit rev;
      url = "https://github.com/go-check/check.git";
      sha256 = "0i83qjmd4ri9mrfddhsbpj9nb43rf2j9803k030fj155j31klwcx";
    };
  };

  circbuf = buildFromGitHub {
    date   = "2015-08-26";
    rev    = "bbbad097214e2918d8543d5201d12bfd7bca254d";
    owner  = "armon";
    repo   = "circbuf";
    sha256 = "1idpr0lzb2px2p3wgfq2276yl7jpaz43df6n91kf790404s4zmk3";
  };

  mitchellh-cli = buildFromGitHub {
    date = "2016-02-03";
    rev = "5c87c51cedf76a1737bf5ca3979e8644871598a6";
    owner = "mitchellh";
    repo = "cli";
    sha256 = "1ajxzh3winjnmqhd4yn6b6f155vfzi0dszhzl4a00zb5pdppp1rd";
    propagatedBuildInputs = [ crypto go-radix speakeasy go-isatty ];
  };

  codegangsta-cli = buildFromGitHub {
    rev = "0ab42fd482c27cf2c95e7794ad3bb2082c2ab2d7";
    owner = "codegangsta";
    repo = "cli";
    sha256 = "1pwpbifydwgbcsxsz7pnqr2fmwl09p7w5v95424j3mfrjbhybbrm";
  };

  cli-spinner = buildFromGitHub {
    rev    = "610063bb4aeef25f7645b3e6080456655ec0fb33";
    owner  = "odeke-em";
    repo   = "cli-spinner";
    sha256 = "13wzs2qrxd72ah32ym0ppswhvyimjw5cqaq3q153y68vlvxd048c";
  };

  cobra = buildFromGitHub {
    rev    = "ee6224d01f6a83f543ae90f881b703cf195782ba";
    owner  = "spf13";
    repo   = "cobra";
    sha256 = "0skmq1lmkh2xzl731a2sfcnl2xbcy9v1050pcf10dahwqzsbx6ij";
    propagatedBuildInputs = [ pflag-spf13 mousetrap go-md2man viper ];
  };

  cli-go = buildFromGitHub {
    rev = "0ab42fd482c27cf2c95e7794ad3bb2082c2ab2d7";
    owner  = "codegangsta";
    repo   = "cli";
    sha256 = "1pwpbifydwgbcsxsz7pnqr2fmwl09p7w5v95424j3mfrjbhybbrm";
  };

  columnize = buildFromGitHub {
    date   = "2015-09-15";
    rev    = "983d3a5fab1bf04d1b412465d2d9f8430e2e917e";
    owner  = "ryanuber";
    repo   = "columnize";
    sha256 = "0m9jhagb1k44zfcdai76xdf9vpi3bqdl7p078ffyibmz0z9jfap6";
  };

  command = buildFromGitHub {
    rev    = "91ca5ec5e9a1bc2668b1ccbe0967e04a349e3561";
    owner  = "odeke-em";
    repo   = "command";
    sha256 = "1ghckzr8h99ckagpmb15p61xazdjmf9mjmlym634hsr9vcj84v62";
  };

  copystructure = buildFromGitHub {
    date = "2016-01-28";
    rev = "80adcec1955ee4e97af357c30dee61aadcc02c10";
    owner = "mitchellh";
    repo = "copystructure";
    sha256 = "0sqiw6gwpgmjm420348indfmg7d8ymq9ilxf6100kkzq3kppzf3s";
    buildInputs = [ reflectwalk ];
  };

  confd = buildGoPackage rec {
    rev = "v0.9.0";
    name = "confd-${rev}";
    goPackagePath = "github.com/kelseyhightower/confd";
    preBuild = "export GOPATH=$GOPATH:$NIX_BUILD_TOP/go/src/${goPackagePath}/Godeps/_workspace";
    src = fetchFromGitHub {
      inherit rev;
      owner = "kelseyhightower";
      repo = "confd";
      sha256 = "0rz533575hdcln8ciqaz79wbnga3czj243g7fz8869db6sa7jwlr";
    };
    subPackages = [ "./" ];
  };

  consul = buildFromGitHub {
    rev = "v0.6.3";
    owner = "hashicorp";
    repo = "consul";
    sha256 = "14vsm3f968qbbcx048il8rz2sgkn8yqgf4k2vnyfd92q86gqw9jq";

    buildInputs = [
      datadog-go circbuf armon_go-metrics go-radix speakeasy bolt
      go-bindata-assetfs go-dockerclient errwrap go-checkpoint go-cleanhttp
      go-immutable-radix go-memdb ugorji_go go-multierror go-reap go-syslog
      golang-lru hcl logutils memberlist net-rpc-msgpackrpc raft raft-boltdb
      scada-client serf yamux muxado dns mitchellh-cli mapstructure columnize crypto sys
    ];

    # Keep consul.ui for backward compatability
    passthru.ui = pkgs.consul-ui;
  };

  consul-api = buildFromGitHub {
    inherit (consul) rev owner repo sha256;
    buildInputs = [ go-cleanhttp serf ];
    subPackages = [ "api" ];
  };

  consul-alerts = buildFromGitHub {
    rev = "6eb4bc556d5f926dbf15d86170664d35d504ae54";
    date = "2015-08-09";
    owner = "AcalephStorage";
    repo = "consul-alerts";
    sha256 = "191bmxix3nl4pr26hcdfxa9qpv5dzggjvi86h2slajgyd2rzn23b";

    renameImports = ''
      # Remove all references to included dependency store
      rm -rf go/src/github.com/AcalephStorage/consul-alerts/Godeps
      govers -d -m github.com/AcalephStorage/consul-alerts/Godeps/_workspace/src/ ""
    '';

    # Temporary fix for name change
    postPatch = ''
      sed -i 's,SetApiKey,SetAPIKey,' notifier/opsgenie-notifier.go
    '';

    buildInputs = [ logrus docopt-go hipchat-go gopherduty consul-api opsgenie-go-sdk influxdb8-client ];
  };

  consul-template = buildGoPackage rec {
    rev = "v0.9.0";
    name = "consul-template-${rev}";
    goPackagePath = "github.com/hashicorp/consul-template";

    src = fetchFromGitHub {
      inherit rev;
      owner = "hashicorp";
      repo = "consul-template";
      sha256 = "1k64rjskzn7cxn7rxab978847jq8gr4zj4cnzgznhn44nzasgymj";
    };

    # We just want the consul api not all of consul and vault
    extraSrcs = [
      { inherit (consul) src goPackagePath; }
      { inherit (vault) src goPackagePath; }
    ];

    buildInputs = [ go-multierror go-syslog hcl logutils mapstructure ];
  };

  context = buildGoPackage rec {
    rev = "215affda49addc4c8ef7e2534915df2c8c35c6cd";
    name = "config-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/gorilla/context";

    src = fetchFromGitHub {
      inherit rev;
      owner = "gorilla";
      repo = "context";
      sha256 = "1ybvjknncyx1f112mv28870n0l7yrymsr0861vzw10gc4yn1h97g";
    };
  };

  cookoo = buildFromGitHub {
    rev    = "v1.2.0";
    owner  = "Masterminds";
    repo   = "cookoo";
    sha256 = "1mxqnxddny43k1shsvd39sfzfs0d20gv3vm9lcjp04g3b0rplck1";
  };

  crypt = buildFromGitHub {
    rev    = "749e360c8f236773f28fc6d3ddfce4a470795227";
    owner  = "xordataexchange";
    repo   = "crypt";
    sha256 = "17g9122b8bmbdpshyzhl7cxsp0nvhk0rc6syc92djavggmbpl6ig";
    preBuild = ''
      substituteInPlace go/src/github.com/xordataexchange/crypt/backend/consul/consul.go \
        --replace 'github.com/armon/consul-api' 'github.com/hashicorp/consul/api' \
        --replace 'consulapi' 'api'
    '';
    propagatedBuildInputs = [ go-etcd consul-api crypto ];
  };

  cssmin = buildFromGitHub {
    rev    = "fb8d9b44afdc258bfff6052d3667521babcb2239";
    owner  = "dchest";
    repo   = "cssmin";
    sha256 = "09sdijfx5d05z4cd5k6lhl7k3kbpdf2amzlngv15h5v0fff9qw4s";
  };

  datadog-go = buildFromGitHub {
    date = "2016-02-12";
    rev = "694a2805f0014581c9da2bfbe2acd3192517eac7";
    owner = "DataDog";
    repo = "datadog-go";
    sha256 = "15rn7brx6r4hdak5iikwfjlv1n9v0dnh89c3lkq9d1zn2ffcbkdk";
    postPatch = ''
      grep -q '(e.text,' statsd/statsd.go
      sed -i 's,e.text,e.Text,g' statsd/statsd.go
    '';
  };

  dbus = buildGoPackage rec {
    rev = "a5942dec6340eb0d57f43f2003c190ce06e43dea";
    name = "dbus-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/godbus/dbus";

    src = fetchFromGitHub {
      inherit rev;
      owner = "godbus";
      repo = "dbus";
      sha256 = "1vk31wal7ncvjwvnb8q1myrkihv1np46f3q8dndi5k0csflbxxdf";
    };
  };

  deis = buildFromGitHub {
    rev = "v1.12.2";
    owner = "deis";
    repo = "deis";
    sha256 = "03lznzcij3gn08kqj2p6skifcdv5aw09dm6zxgvqw7nxx2n1j2ib";
    subPackages = [ "client" ];
    buildInputs = [ docopt-go crypto yaml-v2 ];
    postInstall = ''
      if [ -f "$bin/bin/client" ]; then
        mv "$bin/bin/client" "$bin/bin/deis"
      fi
    '';
  };

  discosrv = buildFromGitHub {
    rev = "v0.12.2";
    owner = "syncthing";
    repo = "discosrv";
    sha256 = "03q89n741ayvywssq7k30iacvlj8nrmf0vxjkj3hlx86h5jhknli";
    buildInputs = [ ql groupcache pq ratelimit syncthing-lib ];
  };

  dns = buildFromGitHub {
    rev = "83f7d658ac219335d42f7ec4397a76e35ca7f835";
    date = "2016-02-05";
    owner  = "miekg";
    repo   = "dns";
    sha256 = "0rvvm0c84mw77bd95a06cpqn289qiim88iw38qhy8fvlnd9plpd7";
  };

  docopt-go = buildFromGitHub {
    rev    = "854c423c810880e30b9fecdabb12d54f4a92f9bb";
    owner  = "docopt";
    repo   = "docopt-go";
    sha256 = "1sddkxgl1pwlipfvmv14h8vg9b9wq1km427j1gjarhb5yfqhh3l1";
  };

  duo_api_golang = buildFromGitHub {
    date = "2015-06-09";
    rev = "16da9e74793f6d9b97b227a0696fe32bcdaecb42";
    owner = "duosecurity";
    repo = "duo_api_golang";
    sha256 = "1g7j0hjpfgk3py7sqkc2xw1lghn5zypyswkpygmsmjm4mxk9sxdm";
  };

  cache = buildFromGitHub {
    rev = "b51b08cb6cf889deda6c941a5205baecfd16f3eb";
    owner = "odeke-em";
    repo = "cache";
    sha256 = "1rmm1ky7irqypqjkk6qcd2n0xkzpaggdxql9dp9i9qci5rvvwwd4";
  };

  exercism = buildFromGitHub {
    rev = "v2.2.1";
    name = "exercism";
    owner = "exercism";
    repo = "cli";
    sha256 = "13kwcxd7m3xv42j50nlm9dd08865dxji41glfvnb4wwq9yicyn4g";
    buildInputs = [ net cli-go osext ];
  };

  exponential-backoff = buildFromGitHub {
    rev = "96e25d36ae36ad09ac02cbfe653b44c4043a8e09";
    owner = "odeke-em";
    repo = "exponential-backoff";
    sha256 = "1as21p2jj8xpahvdxqwsw2i1s3fll14dlc9j192iq7xl1ybwpqs6";
  };

  extractor = buildFromGitHub {
    rev = "801861aedb854c7ac5e1329e9713023e9dc2b4d4";
    owner = "odeke-em";
    repo = "extractor";
    sha256 = "036zmnqxy48h6mxiwywgxix2p4fqvl4svlmcp734ri2rbq3cmxs1";
  };

  open-golang = buildFromGitHub {
    rev = "c8748311a7528d0ba7330d302adbc5a677ef9c9e";
    owner = "skratchdot";
    repo = "open-golang";
    sha256 = "0qhn2d00v3m9fiqk9z7swdm599clc6j7rnli983s8s1byyp0x3ac";
  };

  pretty-words = buildFromGitHub {
    rev = "9d37a7fcb4ae6f94b288d371938482994458cecb";
    owner = "odeke-em";
    repo = "pretty-words";
    sha256 = "1466wjhrg9lhqmzil1vf8qj16fxk32b5kxlcccyw2x6dybqa6pkl";
  };

  meddler = buildFromGitHub {
    rev = "d2b51d2b40e786ab5f810d85e65b96404cf33570";
    owner = "odeke-em";
    repo = "meddler";
    sha256 = "0m0fqrn3kxy4swyk4ja1y42dn1i35rq9j85y11wb222qppy2342x";
  };

  dts = buildFromGitHub {
    rev    = "ec2daabf2f9078e887405f7bcddb3d79cb65502d";
    owner  = "odeke-em";
    repo   = "dts";
    sha256 = "0vq3cz4ab9vdsz9s0jjlp7z27w218jjabjzsh607ps4i8m5d441s";
  };

  du = buildFromGitHub {
    rev = "v1.0.0";
    owner  = "calmh";
    repo   = "du";
    sha256 = "1mv6mkbslfc8giv47kyl97ny0igb3l7jya5hc75sm54xi6g205wa";
  };

  ed25519 = buildGoPackage rec {
    rev = "d2b94fd789ea21d12fac1a4443dd3a3f79cda72c";
    name = "ed25519-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/agl/ed25519";
    src = fetchgit {
      inherit rev;
      url = "git://${goPackagePath}.git";
      sha256 = "83e3010509805d1d315c7aa85a356fda69d91b51ff99ed98a503d63adb3613e9";
    };
  };

  errwrap = buildFromGitHub {
    date   = "2014-10-27";
    rev    = "7554cd9344cec97297fa6649b055a8c98c2a1e55";
    owner  = "hashicorp";
    repo   = "errwrap";
    sha256 = "0kmv0p605di6jc8i1778qzass18m0mv9ks9vxxrfsiwcp4la82jf";
  };

  etcd = buildFromGitHub {
    rev = "v2.2.5";
    owner  = "coreos";
    repo   = "etcd";
    sha256 = "1g5wizd35lhc25c442vlh2sg8xfpmipa7fndryihc31ddjlhhkm8";
  };

  etcd-client = buildFromGitHub {
    rev = "v2.2.5";
    owner  = "coreos";
    repo   = "etcd";
    sha256 = "1g5wizd35lhc25c442vlh2sg8xfpmipa7fndryihc31ddjlhhkm8";
    subPackages = [
      "client"
      "pkg/pathutil"
      "pkg/transport"
      "pkg/types"
      "Godeps/_workspace/src/golang.org/x/net"
      "Godeps/_workspace/src/github.com/ugorji/go/codec"
    ];
  };

  exp = buildFromGitHub {
    date   = "2015-12-07";
    rev    = "c21cce1fce3e6e5bc84854aa3d02a808de44229b";
    owner  = "cznic";
    repo   = "exp";
    sha256 = "1v9j1klhs8y2459y38mghbhnyhx4b8akf9khgi14xw5ydrrxljpk";
    propagatedBuildInputs = [ bufs fileutil mathutil sortutil zappy ];
  };

  fileutil = buildFromGitHub {
    date   = "2015-07-08";
    rev    = "1c9c88fbf552b3737c7b97e1f243860359687976";
    owner  = "cznic";
    repo   = "fileutil";
    sha256 = "1imk4wjgfhyb4m8dm8qbm5lz263lyb27602v3mx8j3dzqjpagg8g";
    buildInputs = [ mathutil ];
  };

  fs = buildFromGitHub {
    date = "2013-11-07";
    rev = "2788f0dbd16903de03cb8186e5c7d97b69ad387b";
    owner  = "kr";
    repo   = "fs";
    sha256 = "1c0fipl4rsh0v5liq1ska1dl83v3llab4k6lm8mvrx9c4dyp71ly";
  };

  fsnotify.v0 = buildGoPackage rec {
    rev = "v0.9.3";
    name = "fsnotify.v0-${rev}";
    goPackagePath = "gopkg.in/fsnotify.v0";
    goPackageAliases = [ "github.com/howeyc/fsnotify" ];

    src = fetchFromGitHub {
      inherit rev;
      owner = "go-fsnotify";
      repo = "fsnotify";
      sha256 = "15wqjpkfzsxnaxbz6y4r91hw6812g3sc4ipagxw1bya9klbnkdc9";
    };
  };

  flannel = buildFromGitHub {
    rev = "v0.5.3";
    owner = "coreos";
    repo = "flannel";
    sha256 = "0d9khv0bczvsaqnz16p546m4r5marmnkcrdhi0f3ajnwxb776r9p";
  };

  fsnotify.v1 = buildGoPackage rec {
    rev = "v1.2.0";
    name = "fsnotify.v1-${rev}";
    goPackagePath = "gopkg.in/fsnotify.v1";

    src = fetchFromGitHub {
      inherit rev;
      owner = "go-fsnotify";
      repo = "fsnotify";
      sha256 = "1308z1by82fbymcra26wjzw7lpjy91kbpp2skmwqcq4q1iwwzvk2";
    };
  };

  fsync = buildFromGitHub {
    rev    = "c2544e79b93fda5653255f907a30fba1c2ac2638";
    owner  = "spf13";
    repo   = "fsync";
    sha256 = "0hzfk2f8pm756j10zgsk8b8gbfylcf8h6q4djz0ka9zpg76s26lz";
    buildInputs = [ afero ];
  };

  fzf = buildFromGitHub {
    rev = "0.11.1";
    owner = "junegunn";
    repo = "fzf";
    sha256 = "1zw1kq4d5sb1qia44q04i33yii9qwlwlwz8vxhln03d4631mhsra";

    buildInputs = [
      crypto ginkgo gomega junegunn.go-runewidth go-shellwords pkgs.ncurses text
    ];

    postInstall= ''
      cp $src/bin/fzf-tmux $bin/bin
    '';
  };

  g2s = buildFromGitHub {
    rev    = "ec76db4c1ac16400ac0e17ca9c4840e1d23da5dc";
    owner  = "peterbourgon";
    repo   = "g2s";
    sha256 = "1p4p8755v2nrn54rik7yifpg9szyg44y5rpp0kryx4ycl72307rj";
  };

  gawp = buildFromGitHub {
    rev    = "488705639109de54d38974cc31353d34cc2cd609";
    date = "2015-08-31";
    owner  = "martingallagher";
    repo   = "gawp";
    sha256 = "0iqqd63nqdijdskdb9f0jwnm6akkh1p2jw4p2w7r1dbaqz1znyay";
    dontInstallSrc = true;
    buildInputs = [ fsnotify.v1 yaml-v2 ];

    meta = with stdenv.lib; {
      homepage    = "https://github.com/martingallagher/gawp";
      description = "A simple, configurable, file watching, job execution tool implemented in Go.";
      maintainers = with maintainers; [ kamilchm ];
      license     = licenses.asl20 ;
      platforms   = platforms.all;
    };
  };

  gcloud-golang = buildFromGoogle {
    rev = "13a9796a2e309e58ed41962c740c11042bc9db63";
    repo = "cloud";
    sha256 = "17nyry9alxdp2y9pm6861nhsvry5djyi2qhc2jxy3f508vks3raw";
    propagatedBuildInputs = [ net oauth2 protobuf google-api-go-client grpc ];
    excludedPackages = "oauth2";
    meta.hydraPlatforms = [ ];
    date = "2016-02-11";
  };

  gcloud-golang-compute-metadata = buildFromGoogle {
    inherit (gcloud-golang) rev repo sha256 date;
    subPackages = [ "compute/metadata" "internal" ];
    buildInputs = [ net ];
  };

  gettext-go = buildFromGitHub {
    rev    = "783c0fb3da95b06dd89c4ba2771f1dc289ecc27c";
    owner  = "chai2010";
    repo   = "gettext-go";
    sha256 = "1iz4wjxc3zkj0xkfs88ig670gb08p1sd922l0ig2cxpjcfjp1y99";
  };

  ginkgo = buildFromGitHub {
    rev = "07d85e6b10c4289c7d612f9b13f45ba36f66d55b";
    owner = "onsi";
    repo = "ginkgo";
    sha256 = "0yhl9mn22imrazi2z53ram3145rz09m0d1b1v86mz9iyxm1vahpy";
  };

  git-annex-remote-b2 = buildFromGitHub {
    buildInputs = [ go go-backblaze ];
    owner = "encryptio";
    repo = "git-annex-remote-b2";
    rev = "v0.2";
    sha256 = "1139rzdvlj3hanqsccfinprvrzf4qjc5n4f0r21jp9j24yhjs6j2";
  };

  git-appraise = buildFromGitHub {
    rev = "v0.3";
    owner = "google";
    repo = "git-appraise";
    sha256 = "124hci9whsvlcywsfz5y20kkj3nhy176a1d5s1lkvsga09yxq6wm";
  };

  git-lfs = buildFromGitHub {
    rev = "v1.0.0";
    owner = "github";
    repo = "git-lfs";
    sha256 = "1zlg3rm5yxak6d88brffv1wpj0iq4qgzn6sgg8xn0pbnzxjd1284";

    # Tests fail with 'lfstest-gitserver.go:46: main redeclared in this block'
    excludedPackages = [ "test" ];

    preBuild = ''
      pushd go/src/github.com/github/git-lfs
        go generate ./commands
      popd
    '';

    postInstall = ''
      rm -v $bin/bin/{man,script}
    '';
  };

  glide = buildFromGitHub {
    rev    = "0.6.1";
    owner  = "Masterminds";
    repo   = "glide";
    sha256 = "1v66c2igm8lmljqrrsyq3cl416162yc5l597582bqsnhshj2kk4m";
    buildInputs = [ cookoo cli-go go-gypsy vcs ];
  };

  gls = buildFromGitHub {
    rev    = "9a4a02dbe491bef4bab3c24fd9f3087d6c4c6690";
    owner  = "jtolds";
    repo   = "gls";
    sha256 = "1gvgkx7llklz6plapb95fcql7d34i6j7anlvksqhdirpja465jnm";
  };

  ugorji_go = buildFromGitHub {
    date = "2016-02-11";
    rev = "f4485b318aadd133842532f841dc205a8e339d74";
    owner = "ugorji";
    repo = "go";
    sha256 = "1gvjah9swa9i14gc43cb2m8bk99lnsywlb8185kbf87q5r9sn8v3";
    goPackageAliases = [ "github.com/hashicorp/go-msgpack" ];
  };

  go4 = buildFromGitHub {
    date = "2016-02-08";
    rev = "40a0492aa096a3be30c750c4e2216de52a6cf2e3";
    owner = "camlistore";
    repo = "go4";
    sha256 = "1la2jj92mxgvlszhas4vx879pc244f4iyb1svbws30f057kq5psd";
    goPackagePath = "go4.org";
    goPackageAliases = [ "github.com/camlistore/go4" ];
    buildInputs = [ gcloud-golang net ];
    autoUpdatePath = "github.com/camlistore/go4";
  };

  goamz = buildGoPackage rec {
    rev = "2a8fed5e89ab9e16210fc337d1aac780e8c7bbb7";
    name = "goamz-${rev}";
    goPackagePath = "github.com/goamz/goamz";
    src = fetchFromGitHub {
      inherit rev;
      owner  = "goamz";
      repo   = "goamz";
      sha256 = "0rlinp0cvgw66qjndg4padr5s0wd3n7kjfggkx6czqj9bqaxcz4b";
    };
    propagatedBuildInputs = [ go-ini ];

    # These might need propagating too, but I haven't tested the entire library
    buildInputs = [ sets go-simplejson check-v1 ];
  };

  goautoneg = buildGoPackage rec {
    name = "goautoneg-2012-12-27";
    goPackagePath = "bitbucket.org/ww/goautoneg";
    rev      = "75cd24fc2f2c2a2088577d12123ddee5f54e0675";

    src = fetchFromBitbucket {
      inherit rev;
      owner  = "ww";
      repo   = "goautoneg";
      sha256 = "19khhn5xhqv1yp7d6k987gh5w5rhrjnp4p0c6fyrd8z6lzz5h9qi";
    };

    meta.autoUpdate = false;
  };

  dgnorton.goback = buildFromGitHub {
    rev    = "a49ca3c0a18f50ae0b8a247e012db4385e516cf4";
    owner  = "dgnorton";
    repo   = "goback";
    sha256 = "1nyg6sckwd0iafs9vcmgbga2k3hid2q0avhwj29qbdhj3l78xi47";
  };

  gocryptfs = buildFromGitHub {
    rev = "v0.5";
    owner = "rfjakob";
    repo = "gocryptfs";
    sha256 = "0jsdz8y7a1fkyrfwg6353c9r959qbqnmf2cjh57hp26w1za5bymd";
    buildInputs = [ crypto go-fuse openssl-spacemonkey ];
  };

  gocheck = buildGoPackage rec {
    rev = "87";
    name = "gocheck-${rev}";
    goPackagePath = "launchpad.net/gocheck";
    src = fetchbzr {
      inherit rev;
      url = "https://${goPackagePath}";
      sha256 = "1y9fa2mv61if51gpik9isls48idsdz87zkm1p3my7swjdix7fcl0";
    };
  };

  gocql = buildFromGitHub {
    rev = "pre-node-events";
    owner  = "gocql";
    repo   = "gocql";
    sha256 = "1bgdk2qx25zh6y9h19wl1fiqvz50n76pwqbf0l5qikk27kl9ml17";
    propagatedBuildInputs = [ inf snappy hailocab_go-hostpool ];
  };

  gocode = buildFromGitHub {
    rev = "680a0fbae5119fb0dbea5dca1d89e02747a80de0";
    date = "2015-09-03";
    owner = "nsf";
    repo = "gocode";
    sha256 = "1ay2xakz4bcn8r3ylicbj753gjljvv4cj9l4wfly55cj1vjybjpv";
  };

  gocolorize = buildGoPackage rec {
    rev = "v1.0.0";
    name = "gocolorize-${rev}";
    goPackagePath = "github.com/agtorre/gocolorize";

    src = fetchFromGitHub {
      inherit rev;
      owner = "agtorre";
      repo = "gocolorize";
      sha256 = "1dj7s8bgw9qky344d0k9gz661c0m317a08a590184drw7m51hy9p";
    };
  };

  goconvey = buildGoPackage rec {
    version = "1.5.0";
    name = "goconvey-${version}";
    goPackagePath = "github.com/smartystreets/goconvey";
    src = fetchurl {
      name = "${name}.tar.gz";
      url = "https://github.com/smartystreets/goconvey/archive/${version}.tar.gz";
      sha256 = "0g3965cb8kg4kf9b0klx4pj9ycd7qwbw1jqjspy6i5d4ccd6mby4";
    };
    buildInputs = [ oglematchers ];
    doCheck = false; # please check again
  };

  gohtml = buildFromGitHub {
    rev    = "ccf383eafddde21dfe37c6191343813822b30e6b";
    owner  = "yosssi";
    repo   = "gohtml";
    sha256 = "1cghwgnx0zjdrqxzxw71riwiggd2rjs2i9p2ljhh76q3q3fd4s9f";
    propagatedBuildInputs = [ net ];
  };

  gotty = buildFromGitHub {
    rev     = "v0.0.10";
    owner   = "yudai";
    repo    = "gotty";
    sha256  = "0gvnbr61d5si06ik2j075jg00r9b94ryfgg06nqxkf10dp8lgi09";

    buildInputs = [ cli-go go manners go-bindata-assetfs go-multierror structs websocket hcl pty ];

    meta = with stdenv.lib; {
      description = "Share your terminal as a web application";
      homepage = "https://github.com/yudai/gotty";
      maintainers = with maintainers; [ matthiasbeyer ];
      license = licenses.mit;
    };
  };

  govers = buildFromGitHub {
    rev = "3b5f175f65d601d06f48d78fcbdb0add633565b9";
    date = "2015-01-09";
    owner = "rogpeppe";
    repo = "govers";
    sha256 = "0din5a7nff6hpc4wg0yad2nwbgy4q1qaazxl8ni49lkkr4hyp8pc";
    dontRenameImports = true;
  };

  golang-lru = buildFromGitHub {
    date = "2016-02-07";
    rev = "a0d98a5f288019575c6d1f4bb1573fef2d1fcdc4";
    owner  = "hashicorp";
    repo   = "golang-lru";
    sha256 = "1z3h4aca31l3qs0inqr5l49vrlycpjm7vq1l9nh1mp0mb2ij0kmp";
  };

  golang-petname = buildFromGitHub {
    rev    = "13f8b3a4326b9a6579358543cffe82713c1d6ce4";
    owner  = "dustinkirkland";
    repo   = "golang-petname";
    sha256 = "1xx6lpv1r2sji8m9w35a2fkr9v4vsgvxrrahcq9bdg75qvadq91d";
  };

  golang_protobuf_extensions = buildFromGitHub {
    rev = "d0c3fe89de86839aecf2e0579c40ba3bb336a453";
    date = "2015-10-11";
    owner  = "matttproud";
    repo   = "golang_protobuf_extensions";
    sha256 = "0jkjgpi1s8l9bdbf14fh8050757jqy36kn1l1hxxlb2fjn1pcg0r";
    buildInputs = [ protobuf ];
  };

  goleveldb = buildFromGitHub {
    rev = "e7e6f5b5ef25adb580feac515f9ccec514d0bda8";
    date = "2016-02-09";
    owner = "syndtr";
    repo = "goleveldb";
    sha256 = "122v2x1ia5k20y734v64215lja384yiqkz5nl3nw10n38bkjwc4f";
    propagatedBuildInputs = [ ginkgo gomega snappy ];
  };

  gollectd = buildFromGitHub {
    rev    = "cf6dec97343244b5d8a5485463675d42f574aa2d";
    owner  = "kimor79";
    repo   = "gollectd";
    sha256 = "1f3ml406cprzjc192csyr2af4wcadkc74kg8n4c0zdzglxxfsqxa";
  };

  gomega = buildFromGitHub {
    rev = "c72df929b80ef4930aaa75d5e486887ff2f3e06a";
    owner  = "onsi";
    repo   = "gomega";
    sha256 = "0jgfi3nbvvyxbja8wza9wqymc0cz0h70jh444lzp4dsygm2vv4bv";
    buildInputs = [ protobuf ];
  };

  google-api-go-client = buildFromGitHub {
    rev = "ad6c2cd766aa31d72fe3fce08189e0ba6e5002b9";
    date = "2016-02-04";
    owner = "google";
    repo = "google-api-go-client";
    sha256 = "1fa68j700aw27vskqcfss87cdk32xa6v826q9pyy1n5gb0sphfd0";
    goPackagePath = "google.golang.org/api";
    goPackageAliases = [ "github.com/google/google-api-client" ];
    buildInputs = [ net ];
  };

  odeke-em.google-api-go-client = buildGoPackage rec {
    rev = "30f4c144b02321ebbc712f35dc95c3e72a5a7fdc";
    name = "odeke-em-google-api-go-client-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/odeke-em/google-api-go-client";
    src = fetchFromGitHub {
      inherit rev;
      owner = "odeke-em";
      repo = "google-api-go-client";
      sha256 = "1fidlljxnd82i2r9yia0b9gh0vv3hwb5k65papnvw7sqpc4sriby";
    };
    buildInputs = [ net ];
    propagatedBuildInputs = [ google-api-go-client ];
  };

  gopass = buildFromGitHub {
    date = "2015-11-20";
    rev = "ae71a9cc54fddb61d946abe9191d05a24ac0e21b";
    owner = "howeyc";
    repo = "gopass";
    sha256 = "120j9sxxznka0akhfhvg7x8y2ig46bjbwjl91kkizl5bry15s0yi";
    propagatedBuildInputs = [ crypto ];
  };

  gopherduty = buildFromGitHub {
    rev    = "f4906ce7e59b33a50bfbcba93e2cf58778c11fb9";
    owner  = "darkcrux";
    repo   = "gopherduty";
    sha256 = "11w1yqc16fxj5q1y5ha5m99j18fg4p9lyqi542x2xbrmjqqialcf";
  };

  goproxy = buildFromGitHub {
    rev    = "2624781dc373cecd1136cafdaaaeba6c9bb90e96";
    date   = "2015-07-26";
    owner  = "elazarl";
    repo   = "goproxy";
    sha256 = "1zz425y8byjaa9i7mslc9anz9w2jc093fjl0562rmm5hh4rc5x5f";
    buildInputs = [ go-charset ];
  };

  goreq = buildFromGitHub {
    rev    = "72c51a544272e007ab3da4f7d9ac959b7af7af03";
    date   = "2015-08-18";
    owner  = "franela";
    repo   = "goreq";
    sha256 = "0dnqbijdzp2dgsf6m934nadixqbv73q0zkqglaa956zzw0pyhcxp";
  };

  gotags = buildFromGitHub {
    rev    = "be986a34e20634775ac73e11a5b55916085c48e7";
    date   = "2015-08-03";
    owner  = "jstemmer";
    repo   = "gotags";
    sha256 = "071wyq90b06xlb3bb0l4qjz1gf4nnci4bcngiddfcxf2l41w1vja";
  };

  gosnappy = buildFromGitHub {
    rev    = "ce8acff4829e0c2458a67ead32390ac0a381c862";
    owner  = "syndtr";
    repo   = "gosnappy";
    sha256 = "0ywa52kcii8g2a9lbqcx8ghdf6y56lqq96sl5nl9p6h74rdvmjr7";
  };

  gox = buildGoPackage rec {
    rev = "e8e6fd4fe12510cc46893dff18c5188a6a6dc549";
    name = "gox-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/mitchellh/gox";
    src = fetchFromGitHub {
      inherit rev;
      owner  = "mitchellh";
      repo   = "gox";
      sha256 = "14jb2vgfr6dv7zlw8i3ilmp125m5l28ljv41a66c9b8gijhm48k1";
    };
    buildInputs = [ iochan ];
  };

  govalidator = buildFromGitHub {
    rev = "9699ab6b38bee2e02cd3fe8b99ecf67665395c96";
    owner = "asaskevich";
    repo = "govalidator";
    sha256 = "0v892axbmqxxxjy7z5bz4cch88d368sl3gycb737rn98lp4w74j3";
  };

  gozim = buildFromGitHub {
    rev    = "ea9b7c39cb1d13bd8bf19ba4dc4e2a16bab52f14";
    date   = "2016-01-15";
    owner  = "akhenakh";
    repo   = "gozim";
    sha256 = "1n50fdd56r3s1sgjbpa72nvdh50gfpf6fq55c077w2p3bxn6p8k6";
    propagatedBuildInputs = [ bleve go-liblzma groupcache go-rice goquery ];
    buildInputs = [ pkgs.zip ];
    postInstall = ''
      pushd $NIX_BUILD_TOP/go/src/$goPackagePath/cmd/gozimhttpd
      ${go-rice.bin}/bin/rice append --exec $bin/bin/gozimhttpd
      popd
    '';
    dontStrip = true;
  };

  go-assert = buildGoPackage rec {
    rev = "e17e99893cb6509f428e1728281c2ad60a6b31e3";
    name = "assert-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/bmizerany/assert";
    src = fetchFromGitHub {
      inherit rev;
      owner = "bmizerany";
      repo = "assert";
      sha256 = "1lfrvqqmb09y6pcr76yjv4r84cshkd4s7fpmiy7268kfi2cvqnpc";
    };
    propagatedBuildInputs = [ pretty ];
  };

  go-backblaze = buildFromGitHub {
    buildInputs = [ go-flags go-humanize uilive uiprogress ];
    goPackagePath = "gopkg.in/kothar/go-backblaze.v0";
    rev = "373819725fc560fa962c6cd883b533d2ebec4844";
    owner = "kothar";
    repo = "go-backblaze";
    sha256 = "1kmlwfnnfd4h46bb9pz2gw1hxqm1pzkwvidfmnc0zkrilaywk6fx";
  };

  go-base58 = buildFromGitHub {
    rev = "6237cf65f3a6f7111cd8a42be3590df99a66bc7d";
    owner  = "jbenet";
    repo   = "go-base58";
    sha256 = "11yp7yg62bhw6jqdrlf2144bffk12jmb1nvqkm172pdhxfwrp3bf";
    date = "2015-03-17";
  };

  go-bencode = buildGoPackage rec {
    version = "1.1.1";
    name = "go-bencode-${version}";
    goPackagePath = "github.com/ehmry/go-bencode";

    src = fetchurl {
      url = "https://${goPackagePath}/archive/v${version}.tar.gz";
      sha256 = "0y2kz2sg1f7mh6vn70kga5d0qhp04n01pf1w7k6s8j2nm62h24j6";
    };
  };

  go-bindata = buildGoPackage rec {
    rev = "a0ff2567cfb70903282db057e799fd826784d41d";
    date = "2015-10-23";
    version = "${date}-${stdenv.lib.strings.substring 0 7 rev}";
    name = "go-bindata-${version}";
    goPackagePath = "github.com/jteeuwen/go-bindata";
    src = fetchFromGitHub {
      inherit rev;
      repo = "go-bindata";
      owner = "jteeuwen";
      sha256 = "0d6zxv0hgh938rf59p1k5lj0ymrb8kcps2vfrb9kaarxsvg7y69v";
    };

    subPackages = [ "./" "go-bindata" ]; # don't build testdata

    meta = with stdenv.lib; {
      homepage    = "https://github.com/jteeuwen/go-bindata";
      description = "A small utility which generates Go code from any file, useful for embedding binary data in a Go program";
      maintainers = with maintainers; [ cstrahan ];
      license     = licenses.cc0 ;
      platforms   = platforms.all;
    };
  };

  go-bindata-assetfs = buildFromGitHub {
    rev = "57eb5e1fc594ad4b0b1dbea7b286d299e0cb43c2";
    owner   = "elazarl";
    repo    = "go-bindata-assetfs";
    sha256 = "1za29pa15y2xsa1lza97jlkax9qj93ks4a2j58xzmay6rczfkb9i";

    date = "2015-12-24";

    meta = with stdenv.lib; {
      description = "Serves embedded files from jteeuwen/go-bindata with net/http";
      homepage = "https://github.com/elazarl/go-bindata-assetfs";
      maintainers = with maintainers; [ matthiasbeyer ];
      license = licenses.bsd2;
    };
  };

  pmylund.go-cache = buildGoPackage rec {
    rev = "93d85800f2fa6bd0a739e7bd612bfa3bc008b72d";
    name = "go-cache-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/pmylund/go-cache";
    goPackageAliases = [
      "github.com/robfig/go-cache"
      "github.com/influxdb/go-cache"
    ];

    src = fetchFromGitHub {
      inherit rev;
      owner = "pmylund";
      repo = "go-cache";
      sha256 = "08wfwm7nk381lv6a95p0hfgqwaksn0vhzz1xxdncjdw6w71isyy7";
    };
  };

  go-charset = buildFromGitHub {
    rev    = "61cdee49014dc952076b5852ce4707137eb36b64";
    date   = "2014-07-13";
    owner  = "paulrosania";
    repo   = "go-charset";
    sha256 = "0jp6rwxlgl66dipk6ssk8ly55jxncvsxs7jc3abgdrhr3rzccab8";
    goPackagePath = "code.google.com/p/go-charset";

    preBuild = ''
      find go/src/$goPackagePath -name \*.go | xargs sed -i 's,github.com/paulrosania/go-charset,code.google.com/p/go-charset,g'
    '';
  };

  go-checkpoint = buildFromGitHub {
    date   = "2015-10-22";
    rev    = "e4b2dc34c0f698ee04750bf2035d8b9384233e1b";
    owner  = "hashicorp";
    repo   = "go-checkpoint";
    sha256 = "0qjfk1fh5zmn04yzxn98zam8j4ay5mzd5kryazqj01hh7szd0sh5";
    buildInputs = [ go-cleanhttp ];
  };

  go-cleanhttp = buildFromGitHub {
    date = "2015-12-17";
    rev = "ce617e79981a8fff618bb643d155133a8f38db96";
    owner = "hashicorp";
    repo = "go-cleanhttp";
    sha256 = "1gm5zid2h790mpc70ka6h2np9j0ilnya3kw7kk9d7q1j6h6z75ar";
  };

  go-colorable = buildFromGitHub {
    rev    = "40e4aedc8fabf8c23e040057540867186712faa5";
    owner  = "mattn";
    repo   = "go-colorable";
    sha256 = "0pwc0s5lvz209dcyamv1ba1xl0c1r5hpxwlq0w5j2xcz8hzrcwkl";
  };

  go-colortext = buildFromGitHub {
    rev    = "13eaeb896f5985a1ab74ddea58707a73d875ba57";
    owner  = "daviddengcn";
    repo   = "go-colortext";
    sha256 = "0618xs9lc5xfp5zkkb5j47dr7i30ps3zj5fj0zpv8afqh2cc689x";
  };

  go-difflib = buildFromGitHub {
    date = "2016-01-10";
    rev = "792786c7400a136282c1664665ae0a8db921c6c2";
    owner  = "pmezard";
    repo   = "go-difflib";
    sha256 = "0c1cn55m4rypmscgf0rrb88pn58j3ysvc2d0432dp3c6fqg6cnzw";
  };

  go-dockerclient = buildFromGitHub {
    date = "2016-02-11";
    rev = "bda1048b6ed884fb71fd8da7828f4f80ed328652";
    owner = "fsouza";
    repo = "go-dockerclient";
    sha256 = "0lx8s57hr1ddykbkxkld0zzwr1yv7vglxhr8cdfmd9jdw5qjimgs";
  };

  go-etcd = buildFromGitHub {
    rev = "003851be7bb0694fe3cc457a49529a19388ee7cf";
    date = "2015-10-26";
    owner = "coreos";
    repo = "go-etcd";
    sha256 = "0n78m4lwsjiaqhjizcsp25paj2l2d4fdr7c4i671ldvpggq76lrl";
    propagatedBuildInputs = [ ugorji_go ];
  };

  go-flags = buildFromGitHub {
    date   = "2015-12-10";
    rev    = "aa34304f81c710f34c76e964a3d996ec1330711d";
    owner  = "jessevdk";
    repo   = "go-flags";
    sha256 = "0zr0qkxsplzj3llj4mmyrn7wlgs5rsmfv3pb3ahmnz9zvla3bnv4";
  };

  go-fuse = buildFromGitHub {
    rev = "324ea173d0a4d90e0e97c464a6ad33f80c9587a8";
    date = "2015-07-27";
    owner = "hanwen";
    repo = "go-fuse";
    sha256 = "0r5amgnpb4g7b6kpz42vnj01w515by4yhy64s5lqf3snzjygaycf";
  };

  go-git-ignore = buildFromGitHub {
    rev = "228fcfa2a06e870a3ef238d54c45ea847f492a37";
    date = "2016-01-15";
    owner = "sabhiram";
    repo = "go-git-ignore";
    sha256 = "0xyj2zsxjjbyd3ppxvs294c8y2ip181dxhvycaxxx6qysbm2nlzj";
  };

  go-github = buildFromGitHub {
    date = "2016-02-11";
    rev = "39d75606a4cbec14d6f9f9d4e295dad4e3711682";
    owner = "google";
    repo = "go-github";
    sha256 = "0cmpz942kd0l3d12diql1f9cnxl9y73ckr9qwppnvmzif78xcla7";
    buildInputs = [ oauth2 ];
    propagatedBuildInputs = [ go-querystring ];
  };

  go-gtk-agl = buildFromGitHub {
    rev = "6937b8d28cf70d583346220b966074cfd3a2e233";
    owner = "agl";
    repo = "go-gtk";
    sha256 = "0jnhsv7ypyhprpy0fndah22v2pbbavr3db6f9wxl1vf34qkns3p4";
    # Examples require many go libs, and gtksourceview seems ready only for
    # gtk2
    preConfigure = ''
      rm -R example gtksourceview
    '';
    nativeBuildInputs = [ pkgs.pkgconfig ];
    propagatedBuildInputs = [ pkgs.gtk3 ];
    buildInputs = [ pkgs.gtkspell3 ];
  };

  go-gypsy = buildFromGitHub {
    rev    = "42fc2c7ee9b8bd0ff636cd2d7a8c0a49491044c5";
    owner  = "kylelemons";
    repo   = "go-gypsy";
    sha256 = "04iy8rdk19n7i18bqipknrcb8lsy1vr4d1iqyxsxq6rmb7298iwj";
  };

  go-homedir = buildFromGitHub {
    date   = "2015-10-24";
    rev    = "d682a8f0cf139663a984ff12528da460ca963de9";
    owner  = "mitchellh";
    repo   = "go-homedir";
    sha256 = "0vsiby9fbkaz7q067wmc6s5pzgpq4gdfx66cj2a1lbdarf7j1kbs";
  };

  bitly_go-hostpool = buildFromGitHub {
    rev    = "d0e59c22a56e8dadfed24f74f452cea5a52722d2";
    date   = "2015-03-31";
    owner  = "bitly";
    repo   = "go-hostpool";
    sha256 = "14ph12krn5zlg00vh9g6g08lkfjxnpw46nzadrfb718yl1hgyk3g";
  };

  hailocab_go-hostpool = buildFromGitHub {
    rev = "e80d13ce29ede4452c43dea11e79b9bc8a15b478";
    date = "2016-01-25";
    owner  = "hailocab";
    repo   = "go-hostpool";
    sha256 = "05ld4wp3illkbgl043yf8jq9y1ld0zzvrcg8jdij129j50xgfxny";
  };

  go-humanize = buildFromGitHub {
    rev = "8929fe90cee4b2cb9deb468b51fb34eba64d1bf0";
    owner = "dustin";
    repo = "go-humanize";
    sha256 = "1g155kxjh6hd3ibx41nbpj6f7h5bh54zgl9dr53xzg2xlxljgjy0";
  };

  go-immutable-radix = buildFromGitHub {
    date = "2016-01-06";
    rev = "12e90058b2897552deea141eff51bb7a07a09e63";
    owner = "hashicorp";
    repo = "go-immutable-radix";
    sha256 = "08lq47bzyssfnhd8ybf6ixv4xir5f7jwh6qhnv94kji66yyp3dgh";
    propagatedBuildInputs = [ golang-lru ];
  };

  go-ini = buildFromGitHub {
    date   = "2013-09-23";
    rev    = "a98ad7ee00ec53921f08832bc06ecf7fd600e6a1";
    owner  = "vaughan0";
    repo   = "go-ini";
    sha256 = "1l1isi3czis009d9k5awsj4xdxgbxn4n9yqjc1ac7f724x6jacfa";
  };

  go-incremental = buildFromGitHub {
    rev    = "92fd0ce4a694213e8b3dfd2d39b16e51d26d0fbf";
    date   = "2015-02-20";
    owner  = "GeertJohan";
    repo   = "go.incremental";
    sha256 = "160cspmq73bk6cvisa6kq1dwrrp1yqpkrpq8dl69wcnaf91cbnml";
  };

  go-ipfs-api = buildFromGitHub {
    date = "2016-01-28";
    rev = "9dad3443f4182b505425c2c2d0ce720f728e5167";
    owner  = "ipfs";
    repo   = "go-ipfs-api";
    sha256 = "0bjkss7gn9hc7v187lwv73p587330f640qnvxkz5jgga91zgcivy";
    excludedPackages = "tests";
    propagatedBuildInputs = [ go-multipart-files tar-utils ];
  };

  go-isatty = buildFromGitHub {
    rev = "56b76bdf51f7708750eac80fa38b952bb9f32639";
    owner  = "mattn";
    repo   = "go-isatty";
    sha256 = "0l8lcp8gcqgy0g1cd89r8vk96nami6sp9cnkx60ms1dn6cqwf5n3";
    date = "2015-12-11";
  };

  go-jmespath = buildFromGitHub {
    rev = "0.2.2";
    owner = "jmespath";
    repo = "go-jmespath";
    sha256 = "0f4j0m44limnjd6q5fk152g6jq2a5cshcdms4p3a1br8pl9wp5fb";
  };

  go-liblzma = buildFromGitHub {
    rev    = "e74be71c3c60411922b5424e875d7692ea638b78";
    date   = "2016-01-01";
    owner  = "remyoudompheng";
    repo   = "go-liblzma";
    sha256 = "12lwjmdcv2l98097rhvjvd2yz8jl741hxcg29i1c18grwmwxa7nf";
    propagatedBuildInputs = [ pkgs.lzma ];
  };

  go-log = buildGoPackage rec {
    rev = "70d039bee4b0e389e5be560491d8291708506f59";
    name = "go-log-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/coreos/go-log";

    src = fetchFromGitHub {
      inherit rev;
      owner = "coreos";
      repo = "go-log";
      sha256 = "1s95xmmhcgw4ascf4zr8c4ij2n4s3mr881nxcpmc61g0gb722b13";
    };

    propagatedBuildInputs = [ osext go-systemd ];
  };

  go-lxc = buildFromGitHub {
    rev    = "a0fa4019e64b385dfa2fb8abcabcdd2f66871639";
    owner  = "lxc";
    repo   = "go-lxc";
    sha256 = "0fkkmn7ynmzpr7j0ha1qsmh3k86ncxcbajmcb90hs0k0iaaiaahz";
    goPackagePath = "gopkg.in/lxc/go-lxc.v2";
    nativeBuildInputs = [ pkgs.pkgconfig ];
    buildInputs = [ pkgs.lxc ];
  };

  go-lz4 = buildFromGitHub {
    date   = "2015-08-20";
    rev    = "74ddf82598bc4745b965729e9c6a463bedd33049";
    owner  = "bkaradzic";
    repo   = "go-lz4";
    sha256 = "1vdid8v0c2v2qhrg9rzn3l7ya1h34jirrxfnir7gv7w6s4ivdvc1";
  };

  go-memdb = buildFromGitHub {
    date = "2016-02-03";
    rev = "e16093a4c7dd00f7ce4c2452ded2c7e37d8df8be";
    owner = "hashicorp";
    repo = "go-memdb";
    sha256 = "0zyw2j386q4r1y85qa2wk29s8w8x2yvx51z90k4fkm29drs6ygsj";
    buildInputs = [ go-immutable-radix ];
  };

  rcrowley_go-metrics = buildFromGitHub {
    rev = "51425a2415d21afadfd55cd93432c0bc69e9598d";
    date = "2016-01-13";
    owner = "rcrowley";
    repo = "go-metrics";
    sha256 = "0lrmnac6wha1yxim9wd0lkks300rj9jrznfvl2xcyp2x427llhd8";
    propagatedBuildInputs = [ stathat ];
  };

  armon_go-metrics = buildFromGitHub {
    date = "2015-12-30";
    rev = "345426c77237ece5dab0e1605c3e4b35c3f54757";
    owner = "armon";
    repo = "go-metrics";
    sha256 = "13bp2ykqhnhzif7wzrwsg54c2b0czhgs9csbvzbvc93n72s59jh5";
    propagatedBuildInputs = [ prometheus_client_golang datadog-go ];
  };

  go-md2man = buildFromGitHub {
    rev    = "71acacd42f85e5e82f70a55327789582a5200a90";
    owner  = "cpuguy83";
    repo   = "go-md2man";
    sha256 = "0hmkrq4gdzb6mwllmh4p1y7vrz7hyr8xqagpk9nyr5dhygvnnq2v";
    propagatedBuildInputs = [ blackfriday ];
  };

  go-multiaddr = buildFromGitHub {
    rev = "41d11170520e5b0ea0af2489d7ac5fbdd452e603";
    owner  = "jbenet";
    repo   = "go-multiaddr";
    sha256 = "01bj2w2gwfa3yjhycc5p7vnxi46s3dwgyfidwp91x5bc2hk479r8";
    buildInputs = [ go-multihash ];
  };

  go-multiaddr-net = buildFromGitHub {
    rev = "4a8bd8f8baf45afcf2bb385bbc17e5208d5d4c71";
    owner  = "jbenet";
    repo   = "go-multiaddr-net";
    sha256 = "1xbxawlafk3m38qr0phwl11yx5fz2hglk7h8zdi4yszgdpphnlz8";
    date = "2015-10-11";
  };

  go-multierror = buildFromGitHub {
    date   = "2015-09-16";
    rev    = "d30f09973e19c1dfcd120b2d9c4f168e68d6b5d5";
    owner  = "hashicorp";
    repo   = "go-multierror";
    sha256 = "0dc02mvv11hvanh12nhw8jsislnxf6i4gkh6vcil0x23kj00z3iz";
    propagatedBuildInputs = [ errwrap ];
  };

  go-multihash = buildFromGitHub {
    rev = "e8d2374934f16a971d1e94a864514a21ac74bf7f";
    owner  = "jbenet";
    repo   = "go-multihash";
    sha256 = "1hlzgmjszn8mfvn848jbnpsvccm9g3m42saavgbh48qdryraqscp";
    propagatedBuildInputs = [ go-base58 crypto ];
  };

  go-multipart-files = buildFromGitHub {
    rev = "3be93d9f6b618f2b8564bfb1d22f1e744eabbae2";
    owner  = "whyrusleeping";
    repo   = "go-multipart-files";
    sha256 = "0lf58q5nrxp10v7mj4b0lz01jz8is1xysxwdwkhhs88qxha8vm2f";
    date = "2015-09-03";
  };

  go-nsq = buildFromGitHub {
    rev = "v1.0.4";
    owner = "nsqio";
    repo = "go-nsq";
    sha256 = "06hrkwk84w8rshkanvfgmgbiml7n06ybv192dvibhwgk2wz2dl46";
    propagatedBuildInputs = [ go-simplejson go-snappystream ];
    goPackageAliases = [ "github.com/bitly/go-nsq" ];
  };

  go-options = buildFromGitHub {
    rev    = "7c174072188d0cfbe6f01bb457626abb22bdff52";
    date   = "2014-12-20";
    owner  = "mreiferson";
    repo   = "go-options";
    sha256 = "0ksyi2cb4k6r2fxamljg42qbz5hdcb9kv5i7y6cx4ajjy0xznwgm";
  };

  go-porterstemmer = buildFromGitHub {
    rev    = "23a2c8e5cf1f380f27722c6d2ae8896431dc7d0e";
    date   = "2014-12-30";
    owner  = "blevesearch";
    repo   = "go-porterstemmer";
    sha256 = "0rcfbrad79xd114h3dhy5d3zs3b5bcgqwm3h5ih1lk69zr9wi91d";
  };

  go-querystring = buildFromGitHub {
    date   = "2015-10-28";
    rev    = "2a60fc2ba6c19de80291203597d752e9ba58e4c0";
    owner  = "google";
    repo   = "go-querystring";
    sha256 = "0raf6r3dd8rxxppzrbhp1y6k5csgfkfs7b0jylj65sbg0hbzxvbr";
  };

  go-radix = buildFromGitHub {
    rev = "4239b77079c7b5d1243b7b4736304ce8ddb6f0f2";
    owner  = "armon";
    repo   = "go-radix";
    sha256 = "0rn45qxi1jlapb0nwa05xbr3g9q9ni3hv6x1pfnh0xdjs08mxsj8";
    date = "2016-01-15";
  };

  junegunn.go-runewidth = buildGoPackage rec {
    rev = "travisish";
    name = "go-runewidth-${rev}";
    goPackagePath = "github.com/junegunn/go-runewidth";
    src = fetchFromGitHub {
      inherit rev;
      owner = "junegunn";
      repo = "go-runewidth";
      sha256 = "07d612val59sibqly5d6znfkp4h4gjd77783jxvmiq6h2fwb964k";
    };
  };

  go-shellwords = buildGoPackage rec {
    rev = "35d512af75e283aae4ca1fc3d44b159ed66189a4";
    name = "go-shellwords-${rev}";
    goPackagePath = "github.com/junegunn/go-shellwords";
    src = fetchFromGitHub {
      inherit rev;
      owner = "junegunn";
      repo = "go-shellwords";
      sha256 = "c792abe5fda48d0dfbdc32a84edb86d884a0ccbd9ed49ad48a30cda5ba028a22";
    };
  };

  go-reap = buildFromGitHub {
    rev = "2d85522212dcf5a84c6b357094f5c44710441912";
    owner  = "hashicorp";
    repo   = "go-reap";
    sha256 = "01pahld0vdssw6550bwhjbs0cm1g0hwd21lg1i57lk8i4pwp0fd9";
    date = "2016-01-13";
    buildInputs = [ sys ];
  };

  go-restful = buildFromGitHub {
    rev    = "892402ba11a2e2fd5e1295dd633481f27365f14d";
    owner  = "emicklei";
    repo   = "go-restful";
    sha256 = "0gr9f53vayc6501a1kaw4p3h9pgf376cgxsfnr3f2dvp0xacvw8x";
  };

  go-repo-root = buildFromGitHub {
    rev = "90041e5c7dc634651549f96814a452f4e0e680f9";
    date = "2014-09-11";
    owner = "cstrahan";
    repo = "go-repo-root";
    sha256 = "1rlzp8kjv0a3dnfhyqcggny0ad648j5csr2x0siq5prahlp48mg4";
    buildInputs = [ tools ];
  };

  go-rice = buildFromGitHub {
    rev    = "4f3c5af2322e393f305d9674845bc36cd1dea589";
    date   = "2016-01-04";
    owner  = "GeertJohan";
    repo   = "go.rice";
    sha256 = "01q2d5iwibwdl68gn8sg6dm7byc42hax3zmiqgmdw63ir1fsv4ag";
    propagatedBuildInputs = [ osext go-spew go-flags go-zipexe rsrc
      go-incremental ];
  };

  go-runit = buildFromGitHub {
    rev    = "a9148323a615e2e1c93b7a9893914a360b4945c8";
    owner  = "soundcloud";
    repo   = "go-runit";
    sha256 = "00f2rfhsaqj2wjanh5qp73phx7x12a5pwd7lc0rjfv68l6sgpg2v";
  };

  go-simplejson = buildFromGitHub {
    rev    = "18db6e68d8fd9cbf2e8ebe4c81a78b96fd9bf05a";
    date   = "2015-03-31";
    owner  = "bitly";
    repo   = "go-simplejson";
    sha256 = "0lj9cxyncchlw6p35j0yym5q5waiz0giw6ri41qdwm8y3dghwwiy";
  };

  go-snappystream = buildFromGitHub {
    rev = "028eae7ab5c4c9e2d1cb4c4ca1e53259bbe7e504";
    date = "2015-04-16";
    owner = "mreiferson";
    repo = "go-snappystream";
    sha256 = "0jdd5whp74nvg35d9hzydsi3shnb1vrnd7shi9qz4wxap7gcrid6";
  };

  go-spew = buildFromGitHub {
    rev    = "5215b55f46b2b919f50a1df0eaa5886afe4e3b3d";
    date   = "2015-11-05";
    owner  = "davecgh";
    repo   = "go-spew";
    sha256 = "15h9kl73rdbzlfmsdxp13jja5gs7sknvqkpq2qizq3qv3nr1x8dk";
  };

  go-sqlite3 = buildFromGitHub {
    rev    = "b4142c444a8941d0d92b0b7103a24df9cd815e42";
    date   = "2015-07-29";
    owner  = "mattn";
    repo   = "go-sqlite3";
    sha256 = "0xq2y4am8dz9w9aaq24s1npg1sn8pf2gn4nki73ylz2fpjwq9vla";
  };

  go-syslog = buildFromGitHub {
    date   = "2015-02-18";
    rev    = "42a2b573b664dbf281bd48c3cc12c086b17a39ba";
    owner  = "hashicorp";
    repo   = "go-syslog";
    sha256 = "1j53m2wjyczm9m55znfycdvm4c8vfniqgk93dvzwy8vpj5gm6sb3";
  };

  go-systemd = buildGoPackage rec {
    rev = "2688e91251d9d8e404e86dd8f096e23b2f086958";
    name = "go-systemd-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/coreos/go-systemd";

    src = fetchFromGitHub {
      inherit rev;
      owner = "coreos";
      repo = "go-systemd";
      sha256 = "0c1k3y5msc1xplhx0ksa7g08yqjaavns8s5zrfg4ig8az30gwlpa";
    };

    buildInputs = [ dbus ];
  };

  lxd-go-systemd = buildFromGitHub {
    rev = "a3dcd1d0480ee0ae9ec354f1632202bfba715e03";
    date = "2015-07-01";
    owner = "stgraber";
    repo = "lxd-go-systemd";
    sha256 = "006dhy3j8ld0kycm8hrjxvakd7xdn1b6z2dsjp1l4sqrxdmm188w";
    buildInputs = [ dbus ];
  };

  go-update-v0 = buildFromGitHub {
    rev = "d8b0b1d421aa1cbf392c05869f8abbc669bb7066";
    owner = "inconshreveable";
    repo = "go-update";
    sha256 = "0cvkik2w368fzimx3y29ncfgw7004qkbdf2n3jy5czvzn35q7dpa";
    goPackagePath = "gopkg.in/inconshreveable/go-update.v0";
    buildInputs = [ osext binarydist ];
  };

  go-uuid = buildFromGitHub {
    rev    = "6b8e5b55d20d01ad47ecfe98e5171688397c61e9";
    date   = "2015-07-22";
    owner  = "satori";
    repo   = "go.uuid";
    sha256 = "0injxzds41v8nc0brvyrrjl66fk3hycz6im38s5r9ccbwlp68p44";
  };

  hashicorp-go-uuid = buildFromGitHub {
    rev = "36289988d83ca270bc07c234c36f364b0dd9c9a7";
    date = "2016-01-19";
    owner  = "hashicorp";
    repo   = "go-uuid";
    sha256 = "12z9p02z6x7ihcm6lb75ck0sdr4v85x4rg9p534vv65y88j8myvb";
  };

  go-vhost = buildFromGitHub {
    rev    = "c4c28117502e4bf00960c8282b2d1c51c865fe2c";
    owner  = "inconshreveable";
    repo   = "go-vhost";
    sha256 = "1rway6sls6fl2s2jk20ajj36rrlzh9944ncc9pdd19kifix54z32";
  };

  go-zipexe = buildFromGitHub {
    rev    = "a5fe2436ffcb3236e175e5149162b41cd28bd27d";
    date   = "2015-03-29";
    owner  = "daaku";
    repo   = "go.zipexe";
    sha256 = "0vi5pskhifb6zw78w2j97qbhs09zmrlk4b48mybgk5b3sswp6510";
  };

  go-zookeeper = buildFromGitHub {
    rev    = "218e9c81c0dd8b3b18172b2bbfad92cc7d6db55f";
    date   = "2015-11-02";
    owner  = "samuel";
    repo   = "go-zookeeper";
    sha256 = "1v0m6wn83v4pbqz6hs7z1h5hbjk7k6npkpl7icvcxdcjd7rmyjp2";
  };

  lint = buildFromGitHub {
    rev = "7b7f4364ff76043e6c3610281525fabc0d90f0e4";
    date = "2015-06-23";
    owner = "golang";
    repo = "lint";
    sha256 = "1bj7zv534hyh87bp2vsbhp94qijc5nixb06li1dzfz9n0wcmlqw9";
    excludedPackages = "testdata";
    buildInputs = [ tools ];
  };

  goquery = buildGoPackage rec {
    rev = "f065786d418c9d22a33cad33decd59277af31471"; #tag v.0.3.2
    name = "goquery-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/PuerkitoBio/goquery";
    propagatedBuildInputs = [ cascadia net ];
    buildInputs = [ cascadia net ];
    doCheck = true;
    src = fetchFromGitHub {
      inherit rev;
      owner = "PuerkitoBio";
      repo = "goquery";
      sha256 = "0bskm3nja1v3pmg7g8nqjkmpwz5p72h1h81y076x1z17zrjaw585";
    };
  };

  groupcache = buildFromGitHub {
    date = "2016-02-08";
    rev = "42b67f4f143ffc99ddaf91f06aeff53f4998768a";
    owner  = "golang";
    repo   = "groupcache";
    sha256 = "19sb2cgvas9p471nyh1jp27c3slk7ff8gcbi8qf47qz48dy8v1xd";
    buildInputs = [ protobuf ];
  };

  grpc = buildFromGitHub {
    rev = "51d644aca6b8eca07b6bd2f5ea435998bf73fa92";
    date = "2016-02-09";
    owner = "grpc";
    repo = "grpc-go";
    sha256 = "18bl9b94bap0j2ly5n00nygcjyhkgjd8adjnjlnb93b6xyl7gi97";
    goPackagePath = "google.golang.org/grpc";
    goPackageAliases = [ "github.com/grpc/grpc-go" ];
    propagatedBuildInputs = [ http2 net protobuf oauth2 glog ];
    excludedPackages = "\\(test\\|benchmark\\)";
  };

  gtreap = buildFromGitHub {
    rev = "0abe01ef9be25c4aedc174758ec2d917314d6d70";
    date = "2015-08-07";
    owner = "steveyen";
    repo = "gtreap";
    sha256 = "03z5j8myrpmd0jk834l318xnyfm0n4rg15yq0d35y7j1aqx26gvk";
    goPackagePath = "github.com/steveyen/gtreap";
  };

  gucumber = buildFromGitHub {
    date = "2016-01-10";
    rev = "44a4d7eb3b14a88cf82b073dfb7e06277afdc549";
    owner = "lsegal";
    repo = "gucumber";
    sha256 = "18xdlh1aibf5xil2ndbph14h7sqzb8b63hky6ic7bw63a4j3bbvc";
    buildInputs = [ testify ];
    propagatedBuildInputs = [ ansicolor ];
  };

  gx = buildFromGitHub {
    rev = "bba4dac881b19a4903fe9bd8d7ead4e7fd2270aa";
    date = "2016-02-10";
    owner = "whyrusleeping";
    repo = "gx";
    sha256 = "1v0q7b2jip3xgwinly6lmcqwq351ynlk8lr0876m2ap97d5yk790";
    propagatedBuildInputs = [
      go-multiaddr
      go-multihash
      go-multiaddr-net
      semver
      go-git-ignore
      stump
      codegangsta-cli
      go-ipfs-api
    ];
    excludedPackages = [
      "tests"
    ];
  };

  gx-go = buildFromGitHub {
    rev = "e2c525cef68ffb91fde538ed2a591f85c0ae76af";
    date = "2016-02-06";
    owner = "whyrusleeping";
    repo = "gx-go";
    sha256 = "035rnpip5al3cva38216cxggz0ni0fr6ld4xjzxpmm13rjqk7d9a";
    buildInputs = [
      codegangsta-cli
      fs
      gx
      stump
    ];
  };

  hcl = buildFromGitHub {
    date = "2016-02-10";
    rev = "1c284ec98f4b398443cbabb0d9197f7f4cc0077c";
    owner  = "hashicorp";
    repo   = "hcl";
    sha256 = "0adlb6r00v4b9lzdsi27h2s4jcd6v3z8gbb7xzarqi04xh8kni1d";
  };

  hipchat-go = buildGoPackage rec {
    rev = "1dd13e154219c15e2611fe46adbb6bf65db419b7";
    name = "hipchat-go-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/tbruyelle/hipchat-go";

    src = fetchFromGitHub {
      inherit rev;
      owner = "tbruyelle";
      repo = "hipchat-go";
      sha256 = "060wg5yjlh28v03mvm80kwgxyny6cyj7zjpcdg032b8b1sz9z81s";
    };
  };

  hmacauth = buildGoPackage {
    name = "hmacauth";
    goPackagePath = "github.com/18F/hmacauth";
    src = fetchFromGitHub {
      rev = "9232a6386b737d7d1e5c1c6e817aa48d5d8ee7cd";
      owner = "18F";
      repo = "hmacauth";
      sha256 = "056mcqrf2bv0g9gn2ixv19srk613h4sasl99w9375mpvmadb3pz1";
    };
  };

  hound = buildGoPackage rec {
    rev  = "0a364935ba9db53e6f3f5563b02fcce242e0930f";
    name = "hound-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/etsy/hound";

    src = fetchFromGitHub {
      inherit rev;
      owner  = "etsy";
      repo   = "hound";
      sha256 = "0jhnjskpm15nfa1cvx0h214lx72zjvnkjwrbgwgqqyn9afrihc7q";
    };
    buildInputs = [ go-bindata.bin pkgs.nodejs pkgs.nodePackages.react-tools pkgs.python pkgs.rsync ];
    postInstall = ''
      pushd go
      python src/github.com/etsy/hound/tools/setup
      sed -i 's|bin/go-bindata||' Makefile
      sed -i 's|$<|#go-bindata|' Makefile
      make
    '';
  };

  hologram = buildGoPackage rec {
    rev  = "63014b81675e1228818bf36ef6ef0028bacad24b";
    name = "hologram-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/AdRoll/hologram";

    src = fetchFromGitHub {
      inherit rev;
      owner  = "AdRoll";
      repo   = "hologram";
      sha256 = "0k8g7dwrkxdvmzs4aa8zz39qa8r2danc4x40hrblcgjhfcwzxrzr";
    };
    buildInputs = [ crypto protobuf goamz rgbterm go-bindata go-homedir ldap g2s gox ];
  };

  http2 = buildFromGitHub rec {
    rev = "aa7658c0e9902e929a9ed0996ef949e59fc0f3ab";
    owner = "bradfitz";
    repo = "http2";
    sha256 = "1psb5ndg9khzsyzf7vdgz7xmj2q0q9r1r7lszm8axdypbxpz7nml";
    buildInputs = [ crypto ];
    date = "2016-01-16";
  };

  httprouter = buildFromGitHub {
    rev = "2c34ec888a7359c0750064e0a4c8df360806c255";
    owner  = "julienschmidt";
    repo   = "httprouter";
    sha256 = "0syjr9dxclzwqj5dicpp6niax3zqigdhgjk8qy8mq017fsn4pngb";
  };

  hugo = buildFromGitHub {
    rev    = "v0.15";
    owner  = "spf13";
    repo   = "hugo";
    sha256 = "1v0z9ar5kakhib3c3c43ddwd1ga4b8icirg6kk3cnaqfckd638l5";
    buildInputs = [
      mapstructure text websocket cobra osext fsnotify.v1 afero
      jwalterweatherman cast viper yaml-v2 ace purell mmark blackfriday amber
      cssmin nitro inflect fsync
    ];
  };

  i3cat = buildFromGitHub {
    rev    = "b9ba886a7c769994ccd8d4627978ef4b51fcf576";
    date   = "2015-03-21";
    owner  = "vincent-petithory";
    repo   = "i3cat";
    sha256 = "1xlm5c9ajdb71985nq7hcsaraq2z06przbl6r4ykvzi8w2lwgv72";
    buildInputs = [ structfield ];
  };

  inf = buildFromGitHub {
    date   = "2015-09-11";
    rev    = "3887ee99ecf07df5b447e9b00d9c0b2adaa9f3e4";
    owner  = "go-inf";
    repo   = "inf";
    sha256 = "0rf3vwyb8aqnac9x9d6ax7z5526c45a16yjm2pvkijr6qgqz8b82";
    goPackagePath = "gopkg.in/inf.v0";
    goPackageAliases = [ "github.com/go-inf/inf" ];
  };

  inflect = buildGoPackage {
    name = "inflect-2013-08-29";
    goPackagePath = "bitbucket.org/pkg/inflect";
    src = fetchFromBitbucket {
      rev    = "8961c3750a47b8c0b3e118d52513b97adf85a7e8";
      owner  = "pkg";
      repo   = "inflect";
      sha256 = "11qdyr5gdszy24ai1bh7sf0cgrb4q7g7fsd11kbpgj5hjiigxb9a";
    };
  };

  influxdb8-client = buildFromGitHub{
    rev = "v0.8.8";
    owner = "influxdb";
    repo = "influxdb";
    sha256 = "0xpigp76rlsxqj93apjzkbi98ha5g4678j584l6hg57p711gqsdv";
    subPackages = [ "client" ];
  };

  eckardt.influxdb-go = buildGoPackage rec {
    rev = "8b71952efc257237e077c5d0672e936713bad38f";
    name = "influxdb-go-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/eckardt/influxdb-go";
    src = fetchgit {
      inherit rev;
      url = "https://${goPackagePath}.git";
      sha256 = "5318c7e1131ba2330c90a1b67855209e41d3c77811b1d212a96525b42d391f6e";
    };
  };

  ini = buildFromGitHub {
    rev = "v1.9.0";
    owner  = "go-ini";
    repo   = "ini";
    sha256 = "19xi4s9gnzhga8yb4apsrqwg7qr8n3jpn8shr3n4g0b5wpd8bl64";
  };

  flagfile = buildFromGitHub {
    date   = "2015-02-13";
    rev    = "871ce569c29360f95d7596f90aa54d5ecef75738";
    owner  = "spacemonkeygo";
    repo   = "flagfile";
    sha256 = "1y6wf1s51c90qc1aki8qikkw1wqapzjzr690xrmnrngsfpdyvkrc";
  };

  iochan = buildFromGitHub {
    rev    = "b584a329b193e206025682ae6c10cdbe03b0cd77";
    owner  = "mitchellh";
    repo   = "iochan";
    sha256 = "1fcwdhfci41ibpng2j4c1bqfng578cwzb3c00yw1lnbwwhaq9r6b";
  };

  ipfs = buildFromGitHub {
    date   = "2016-02-12";
    rev    = "a871f371e9ac947081261f5a8373ca298524587b";
    owner  = "ipfs";
    repo   = "go-ipfs";
    sha256 = "0kydgdj3g6d7f6yy660j6plx0abzd76h9bwi1sj0g2f8z0fd78zj";
    extraSrcs = [
      {
        src = fetchGxPackage {
          multihash = "QmUBogf4nUefBjmYjn6jfsfPJRkmDGSeMhNj4usRKq69f4";
          sha256 = "0vg8b2f69719gy31y4xzc96n19fd7zrhqszfgiys3khiwvd9zjpn";
        };
        goPackagePath = "gx/afsdfdsfasd/blah";
      }
    ];
  };

  json2csv = buildFromGitHub {
    rev = "d82e60e6dc2a7d3bcf15314d1ecbebeffaacf0c6";
    owner  = "jehiah";
    repo   = "json2csv";
    sha256 = "1fw0qqaz2wj9d4rj2jkfj7rb25ra106p4znfib69p4d3qibfjcsn";
  };

  jwalterweatherman = buildFromGitHub {
    rev    = "c2aa07df593850a04644d77bb757d002e517a296";
    owner  = "spf13";
    repo   = "jwalterweatherman";
    sha256 = "0m8867afsvka5gp2idrmlarpjg7kxx7qacpwrz1wl8y3zxyn3945";
  };

  kagome = buildFromGitHub {
    rev = "1bbdbdd590e13a8c2f4508c67a079113cd7b9f51";
    date = "2016-01-19";
    owner = "ikawaha";
    repo = "kagome";
    sha256 = "1isnjdkn9hnrkp5g37p2k5bbsrx0ma32v3icwlmwwyc5mppa4blb";

    # I disable the parallel building, because otherwise each
    # spawned compile takes over 1.5GB of RAM.
    buildFlags = "-p 1";
    enableParallelBuilding = false;

    goPackagePath = "github.com/ikawaha/kagome";
  };

  ldap = buildFromGitHub {
    rev = "v2.2";
    owner  = "go-ldap";
    repo   = "ldap";
    sha256 = "1q8wm1q5nclwfgzr07i42bppgm3nv447hgndp0y22k4fy8db1dpj";
    goPackageAliases = [
      "github.com/nmcclain/ldap"
      "github.com/vanackere/ldap"
    ];
    propagatedBuildInputs = [ asn1-ber ];
  };

  levigo = buildGoPackage rec {
    rev = "1ddad808d437abb2b8a55a950ec2616caa88969b";
    name = "levigo-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/jmhodges/levigo";

    src = fetchFromGitHub {
      inherit rev;
      owner = "jmhodges";
      repo = "levigo";
      sha256 = "1lmafyk7nglhig3n471jq4hmnqf45afj5ldb2jx0253f5ii4r2yq";
    };

    buildInputs = [ pkgs.leveldb ];
  };

  liner = buildFromGitHub {
    rev    = "1bb0d1c1a25ed393d8feb09bab039b2b1b1fbced";
    owner  = "peterh";
    repo   = "liner";
    sha256 = "05ihxpmp6x3hw71xzvjdgxnyvyx2s4lf23xqnfjj16s4j4qidc48";
  };

  odeke-em.log = buildFromGitHub {
    rev    = "cad53c4565a0b0304577bd13f3862350bdc5f907";
    owner  = "odeke-em";
    repo   = "log";
    sha256 = "059c933qjikxlvaywzpzljqnab19svymbv6x32pc7khw156fh48w";
  };

  log15 = buildFromGitHub {
    rev    = "dc7890abeaadcb6a79a9a5ee30bc1897bbf97713";
    owner  = "inconshreveable";
    repo   = "log15";
    sha256 = "15wgicl078h931n90rksgbqmfixvbfxywk3m8qkaln34v69x4vgp";
    goPackagePath = "gopkg.in/inconshreveable/log15.v2";
    propagatedBuildInputs = [ go-colorable ];
  };

  log4go = buildGoPackage rec {
    rev = "cb4cc51cd03958183d3b637d0750497d88c2f7a8";
    name = "log4go-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/ccpaging/log4go";
    goPackageAliases = [
      "github.com/alecthomas/log4go"
      "code.google.com/p/log4go"
    ];

    src = fetchFromGitHub {
      inherit rev;
      owner = "ccpaging";
      repo = "log4go";
      sha256 = "0l9f86zzhla9hq35q4xhgs837283qrm4gxbp5lrwwls54ifiq7k2";
    };

    propagatedBuildInputs = [ go-colortext ];
  };

  logger = buildFromGitHub {
    rev = "c96f6a1a8c7b6bf2f4860c667867d90174799eb2";
    date = "2015-05-23";
    owner = "calmh";
    repo = "logger";
    sha256 = "1f67xbvvf210g5cqa84l12s00ynfbkjinhl8y6m88yrdb025v1vg";
  };

  logrus = buildFromGitHub rec {
    rev = "v0.9.0";
    owner = "Sirupsen";
    repo = "logrus";
    sha256 = "1m6vvd4pg4lwglhk54lv5mf6cc8h7bi0d9zb3gar4crz531r66y4";
  };

  logutils = buildFromGitHub {
    date   = "2015-06-09";
    rev    = "0dc08b1671f34c4250ce212759ebd880f743d883";
    owner  = "hashicorp";
    repo   = "logutils";
    sha256 = "0rynhjwvacv9ibl2k4fwz0xy71d583ac4p33gm20k9yldqnznc7r";
  };

  luhn = buildFromGitHub {
    rev = "v1.0.0";
    owner  = "calmh";
    repo   = "luhn";
    sha256 = "1hfj1lx7wdpifn16zqrl4xml6cj5gxbn6hfz1f46g2a6bdf0gcvs";
  };

  lxd = buildFromGitHub {
    rev    = "lxd-0.17";
    owner  = "lxc";
    repo   = "lxd";
    sha256 = "1yi3dr1bgdplc6nya10k5jsj3psbf3077vqad8x8cjza2z9i48fp";
    excludedPackages = "test"; # Don't build the binary called test which causes conflicts
    buildInputs = [
      gettext-go websocket crypto log15 go-lxc yaml-v2 tomb protobuf pongo2
      lxd-go-systemd go-uuid tablewriter golang-petname mux go-sqlite3 goproxy
      pkgs.python3
    ];
    postInstall = ''
      cp go/src/$goPackagePath/scripts/lxd-images $bin/bin
    '';
  };

  mathutil = buildFromGitHub {
    date = "2016-01-19";
    rev = "38a5fe05cd94d69433fd1c928417834c604f281d";
    owner = "cznic";
    repo = "mathutil";
    sha256 = "1w9ypzdmz2c94v5jpz6g80npl48kvvzlqcnccn1y6hgnisqinvbc";
    buildInputs = [ bigfft ];
  };

  manners = buildFromGitHub {
    rev = "0.4.0";
    owner = "braintree";
    repo = "manners";
    sha256 = "07985pbfhwlhbglr9zwh2wx8kkp0wzqr1lf0xbbxbhga4hn9q3ak";

    meta = with stdenv.lib; {
      description = "A polite Go HTTP server that shuts down gracefully";
      homepage = "https://github.com/braintree/manners";
      maintainers = with maintainers; [ matthiasbeyer ];
      license = licenses.mit;
    };
  };

  mapstructure = buildFromGitHub {
    date = "2016-02-11";
    rev = "d2dd0262208475919e1a362f675cfc0e7c10e905";
    owner  = "mitchellh";
    repo   = "mapstructure";
    sha256 = "1idj9h0g9z3s21y2hivaf1dknxhpd7yy0kn6wk3311hlr7s543j5";
  };

  mdns = buildFromGitHub {
    date = "2015-12-05";
    rev = "9d85cf22f9f8d53cb5c81c1b2749f438b2ee333f";
    owner = "hashicorp";
    repo = "mdns";
    sha256 = "0z8szgrd2y6ax8jvi0wbsr4vkh5hbf24346zri15fqkyai1rnjib";
    propagatedBuildInputs = [ net dns ];
  };

  memberlist = buildFromGitHub {
    date = "2015-12-18";
    rev = "9888dc523910e5d22c5be4f6e34520943df21809";
    owner = "hashicorp";
    repo = "memberlist";
    sha256 = "17cx8a3ixkgdrjkrslnpji5f3f7997qs3msl34icdvgmd6p76aj1";
    propagatedBuildInputs = [ ugorji_go armon_go-metrics ];
  };

  memberlist_v2 = buildGoPackage rec {
    rev = "165267096ca647f00cc0b59a8f1ede9a96cbfbb1";
    name = "memberlist-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/hashicorp/memberlist";

    src = fetchFromGitHub {
      inherit rev;
      owner = "hashicorp";
      repo = "memberlist";
      sha256 = "09lh79xqy7q0gy23x22lpfwihb5acr750vxl2fx0i4b88kq1vrzh";
    };

    propagatedBuildInputs = [ ugorji_go armon_go-metrics ];
  };

  mesos-dns = buildFromGitHub {
    rev = "v0.1.2";
    owner = "mesosphere";
    repo = "mesos-dns";
    sha256 = "0zs6lcgk43j7jp370qnii7n55cd9pa8gl56r8hy4nagfvlvrcm02";

    # Avoid including the benchmarking test helper in the output:
    subPackages = [ "." ];

    buildInputs = [ glog mesos-go dns go-restful ];
  };

  mesos-go = buildFromGitHub {
    rev = "d98afa618cc9a9251758916f49ce87f9051b69a4";
    owner = "mesos";
    repo = "mesos-go";
    sha256 = "01ab0jf3cfb1rdwwb21r38rcfr5vp86pkfk28mws8298mlzbpri7";
    propagatedBuildInputs = [ gogo.protobuf glog net testify go-zookeeper objx pborman_uuid ];
    excludedPackages = "test";
  };

  mesos-stats = buildGoPackage rec {
    rev = "0c6ea494c19bedc67ebb85ce3d187ec21050e920";
    name = "mesos-stats-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/antonlindstrom/mesos_stats";
    src = fetchFromGitHub {
      inherit rev;
      owner = "antonlindstrom";
      repo = "mesos_stats";
      sha256 = "18ggyjf4nyn77gkn16wg9krp4dsphgzdgcr3mdflv6mvbr482ar4";
    };
  };

  mgo = buildFromGitHub {
    rev = "r2015.12.06";
    owner = "go-mgo";
    repo = "mgo";
    sha256 = "1k7zny7ac25m2a2rbgdc9yimp1g2krmlkayqxx6qd7j8ind9w794";
    goPackagePath = "gopkg.in/mgo.v2";
    goPackageAliases = [ "github.com/go-mgo/mgo" ];
    buildInputs = [ pkgs.cyrus_sasl tomb ];
  };

  mmark = buildFromGitHub {
    rev    = "eacb2132c31a489033ebb068432892ba791a2f1b";
    owner  = "miekg";
    repo   = "mmark";
    sha256 = "0wsi6fb6f1qi1a8yv858bkgn8pmsspw2k6dx5fx38kvg8zsb4l1a";
    buildInputs = [ toml ];
  };

  mongo-tools = buildFromGitHub {
    rev    = "r3.3.0";
    owner  = "mongodb";
    repo   = "mongo-tools";
    sha256 = "04jnk57wj34ch0q03v1gacy4i3jpg0zxnqzaqlw9ikd4h2r5w7y8";
    buildInputs = [ crypto mgo go-flags gopass openssl tomb ];
    excludedPackages = "vendor";

    # Mongodb incorrectly names all of their binaries main
    # Let's work around this with our own installer
    preInstall = ''
      mkdir -p $bin/bin
      while read b; do
        rm -f go/bin/main
        go install $goPackagePath/$b/main
        cp go/bin/main $bin/bin/$b
      done < <(find go/src/$goPackagePath -name main | xargs dirname | xargs basename -a)
      rm -r go/bin
    '';
  };

  mousetrap = buildFromGitHub {
    rev    = "9dbb96d2c3a964935b0870b5abaea13c98b483aa";
    owner  = "inconshreveable";
    repo   = "mousetrap";
    sha256 = "1f9g8vm18qv1rcb745a4iahql9vfrz0jni9mnzriab2wy1pfdl5b";
  };

  msgpack = buildGoPackage rec {
    rev = "9dbd4ac30c0b67927f0fb5557fb8341047bd35f7";
    name = "msgpack-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "gopkg.in/vmihailenco/msgpack.v2";

    src = fetchFromGitHub {
      inherit rev;
      owner = "vmihailenco";
      repo = "msgpack";
      sha256 = "0nq9yb85hi3c35kwyl38ywv95vd8n7aywmj78wwylglld22nfmw2";
    };
  };

  mtpfs = buildFromGitHub {
    rev = "3ef47f91c38cf1da3e965e37debfc81738e9cd94";
    date = "2015-08-01";
    owner = "hanwen";
    repo = "go-mtpfs";
    sha256 = "1f7lcialkpkwk01f7yxw77qln291sqjkspb09mh0yacmrhl231g8";

    buildInputs = [ go-fuse usb ];
  };

  mux = buildFromGitHub {
    rev = "5a8a0400500543e28b2886a8c52d21a435815411";
    date = "2015-08-05";
    owner = "gorilla";
    repo = "mux";
    sha256 = "15w1bw14vx157r6v98fhy831ilnbzdsm5xzvs23j8hw6gnknzaw1";
    propagatedBuildInputs = [ context ];
  };

  muxado = buildFromGitHub {
    date   = "2014-03-12";
    rev    = "f693c7e88ba316d1a0ae3e205e22a01aa3ec2848";
    owner  = "inconshreveable";
    repo   = "muxado";
    sha256 = "1vgiwwxhgx9c899f6ikvrs0w6vfsnypzalcqyr0mqm2w816r9hhs";
  };

  mysql = buildFromGitHub {
    rev = "267b128680c46286b9ca13475c3cca5de8f79bd7";
    owner  = "go-sql-driver";
    repo   = "mysql";
    sha256 = "0a7jjry1jcd8zi7dnr21iyyxgkx3s9sg35dy4wqaqg9xh3hr6f51";
  };

  net-rpc-msgpackrpc = buildFromGitHub {
    date = "2015-11-15";
    rev = "a14192a58a694c123d8fe5481d4a4727d6ae82f3";
    owner = "hashicorp";
    repo = "net-rpc-msgpackrpc";
    sha256 = "0sqx6zw211fjphj1j6w7bc5191csh2jn1wkihycsd4mk5kbwvjxp";
    propagatedBuildInputs = [ ugorji_go go-multierror ];
  };

  ngrok = buildFromGitHub {
    rev = "1.7.1";
    owner = "inconshreveable";
    repo = "ngrok";
    sha256 = "1r4nc9knp0nxg4vglg7v7jbyd1nh1j2590l720ahll8a4fbsx5a4";
    goPackagePath = "ngrok";

    preConfigure = ''
      sed -e '/jteeuwen\/go-bindata/d' \
          -e '/export GOPATH/d' \
          -e 's/go get/#go get/' \
          -e 's|bin/go-bindata|go-bindata|' -i Makefile
      make assets BUILDTAGS=release
      export sourceRoot=$sourceRoot/src/ngrok
    '';

    buildInputs = [
      git log4go websocket go-vhost mousetrap termbox-go rcrowley_go-metrics
      yaml-v1 go-bindata.bin go-update-v0 binarydist osext
    ];

    buildFlags = [ "-tags release" ];
  };

  nitro = buildFromGitHub {
    rev    = "24d7ef30a12da0bdc5e2eb370a79c659ddccf0e8";
    owner  = "spf13";
    repo   = "nitro";
    sha256 = "143sbpx0jdgf8f8ayv51x6l4jg6cnv6nps6n60qxhx4vd90s6mib";
  };

  nsq = buildFromGitHub {
    rev = "v0.3.5";
    owner = "bitly";
    repo = "nsq";
    sha256 = "1r7jgplzn6bgwhd4vn8045n6cmm4iqbzssbjgj7j1c28zbficy2f";

    excludedPackages = "bench";

    buildInputs = [ go-nsq go-options semver perks toml bitly_go-hostpool timer_metrics ];
  };

  ntp = buildFromGitHub {
    rev    = "0a5264e2563429030eb922f258229ae3fee5b5dc";
    owner  = "beevik";
    repo   = "ntp";
    sha256 = "03fvgbjf2aprjj1s6wdc35wwa7k1w5phkixzvp5n1j21sf6w4h24";
  };

  oauth2_proxy = buildGoPackage {
    name = "oauth2_proxy";
    goPackagePath = "github.com/bitly/oauth2_proxy";
    src = fetchFromGitHub {
      rev = "10f47e325b782a60b8689653fa45360dee7fbf34";
      owner = "bitly";
      repo = "oauth2_proxy";
      sha256 = "13f6kaq15f6ial9gqzrsx7i94jhd5j70js2k93qwxcw1vkh1b6si";
    };
    buildInputs = [
      go-assert go-options go-simplejson toml fsnotify.v1 oauth2
      google-api-go-client hmacauth
    ];
  };

  objx = buildFromGitHub {
    date   = "2015-09-28";
    rev    = "1a9d0bb9f541897e62256577b352fdbc1fb4fd94";
    owner  = "stretchr";
    repo   = "objx";
    sha256 = "1n027ksls1rn1ja98kd0cd2kv1vwlzsl0d7xnh3yqf451vh0md50";
  };

  oglematchers = buildGoPackage rec {
    rev = "4fc24f97b5b74022c2a3f4ca7eed57ca29083d3e";
    name = "oglematchers-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/jacobsa/oglematchers";
    src = fetchgit {
      inherit rev;
      url = "https://${goPackagePath}.git";
      sha256 = "4075ede31601adf8c4e92739693aebffa3718c641dfca75b09cf6b4bd6c26cc0";
    };
    #goTestInputs = [ ogletest ];
    doCheck = false; # infinite recursion
  };

  oglemock = buildGoPackage rec {
    rev = "d054ecee522bdce4481690cdeb09d1b4c44da4e1";
    name = "oglemock-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/jacobsa/oglemock";
    src = fetchgit {
      inherit rev;
      url = "https://${goPackagePath}.git";
      sha256 = "685e7fc4308d118ae25467ba84c64754692a7772c77c197f38d8c1b63ea81da2";
    };
    buildInputs = [ oglematchers ];
    #goTestInputs = [ ogletest ];
    doCheck = false; # infinite recursion
  };

  ogletest = buildGoPackage rec {
    rev = "7de485607c3f215cf92c1f793b5d5a7de46ec3c7";
    name = "ogletest-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/jacobsa/ogletest";
    src = fetchgit {
      inherit rev;
      url = "https://${goPackagePath}.git";
      sha256 = "0cfc43646d59dcea5772320f968aef2f565fb5c46068d8def412b8f635365361";
    };
    buildInputs = [ oglemock oglematchers ];
    doCheck = false; # check this again
  };

  oh = buildFromGitHub {
    rev = "a99b5f1128247014fb2a83a775fa1813be14b67d";
    date = "2015-11-21";
    owner = "michaelmacinnis";
    repo = "oh";
    sha256 = "1srl3d1flqlh2k9q9pjss72rxw82msys108x22milfylmr75v03m";
    goPackageAliases = [ "github.com/michaelmacinnis/oh" ];
    buildInputs = [ adapted liner ];
  };

  openssl = buildFromGitHub {
    date = "2015-03-30";
    rev = "4c6dbafa5ec35b3ffc6a1b1e1fe29c3eba2053ec";
    owner = "10gen";
    repo = "openssl";
    sha256 = "1033c9vgv9lf8ks0qjy0ylsmx1hizqxa6izalma8vi30np6ka6zn";
    goPackageAliases = [ "github.com/spacemonkeygo/openssl" ];
    nativeBuildInputs = [ pkgs.pkgconfig ];
    buildInputs = [ pkgs.openssl ];
    propagatedBuildInputs = [ spacelog ];

    preBuild = ''
      find go/src/$goPackagePath -name \*.go | xargs sed -i 's,spacemonkeygo/openssl,10gen/openssl,g'
    '';
  };

  # reintroduced for gocrytpfs as I don't understand the 10gen/spacemonkey split
  openssl-spacemonkey = buildFromGitHub rec {
    rev = "71f9da2a482c2b7bc3507c3fabaf714d6bb8b75d";
    name = "openssl-${stdenv.lib.strings.substring 0 7 rev}";
    owner = "spacemonkeygo";
    repo = "openssl";
    sha256 = "1byxwiq4mcbsj0wgaxqmyndp6jjn5gm8fjlsxw9bg0f33a3kn5jk";
    nativeBuildInputs = [ pkgs.pkgconfig ];
    buildInputs = [ pkgs.openssl ];
    propagatedBuildInputs = [ spacelog ];
  };

  opsgenie-go-sdk = buildFromGitHub {
    rev = "c6e1235dfed2126eb9b562c4d776baf55ccd23e3";
    date = "2015-08-24";
    owner = "opsgenie";
    repo = "opsgenie-go-sdk";
    sha256 = "1prvnjiqmhnp9cggp9f6882yckix2laqik35fcj32117ry26p4jm";
    propagatedBuildInputs = [ seelog go-querystring goreq ];
    excludedPackages = "samples";
  };

  osext = buildFromGitHub {
    date = "2015-12-22";
    rev = "29ae4ffbc9a6fe9fb2bc5029050ce6996ea1d3bc";
    owner = "kardianos";
    repo = "osext";
    sha256 = "1mawalaz84i16njkz6f9fd5jxhcbxkbsjnav3cmqq2dncv2hyv8a";
    goPackageAliases = [
      "github.com/bugsnag/osext"
      "bitbucket.org/kardianos/osext"
    ];
  };

  pat = buildFromGitHub {
    rev    = "b8a35001b773c267eb260a691f4e5499a3531600";
    owner  = "bmizerany";
    repo   = "pat";
    sha256 = "11zxd45rvjm6cn3wzbi18wy9j4vr1r1hgg6gzlqnxffiizkycxmz";
  };

  pb = buildFromGitHub {
    rev    = "e648e12b78cedf14ebb2fc1855033f07b034cfbb";
    owner  = "cheggaaa";
    repo   = "pb";
    sha256 = "03k4cars7hcqqgdsd0minfls2p7gjpm8q6y8vknh1s68kvxd4xam";
  };

  perks = buildFromGitHub rec {
    date   = "2014-07-16";
    owner  = "bmizerany";
    repo   = "perks";
    rev    = "d9a9656a3a4b1c2864fdb44db2ef8619772d92aa";
    sha256 = "0f39b3zfm1zd6xcvlm6szgss026qs84n2j9y5bnb3zxzdkxb9w9n";
  };

  beorn7_perks = buildFromGitHub rec {
    date   = "2015-02-23";
    owner  = "beorn7";
    repo   = "perks";
    rev    = "b965b613227fddccbfffe13eae360ed3fa822f8d";
    sha256 = "1p8zsj4r0g61q922khfxpwxhdma2dx4xad1m5qx43mfn28kxngqk";
  };

  pflag = buildGoPackage rec {
    date = "20131112";
    rev = "94e98a55fb412fcbcfc302555cb990f5e1590627";
    name = "pflag-${date}-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/spf13/pflag";
    src = fetchgit {
      inherit rev;
      url = "https://${goPackagePath}.git";
      sha256 = "0z8nzdhj8nrim8fz11magdl0wxnisix9p2kcvn5kkb3bg8wmxhbg";
    };
    doCheck = false; # bad import path in tests
  };

  pflag-spf13 = buildFromGitHub rec {
    rev    = "08b1a584251b5b62f458943640fc8ebd4d50aaa5";
    owner  = "spf13";
    repo   = "pflag";
    sha256 = "139d08cq06jia0arc6cikdnhnaqms07xfay87pzq5ym86fv0agiq";
  };

  pond = let
      isx86_64 = stdenv.lib.any (n: n == stdenv.system) stdenv.lib.platforms.x86_64;
      gui = true; # Might be implemented with nixpkgs config.
  in buildFromGitHub {
    rev = "bce6e0dc61803c23699c749e29a83f81da3c41b2";
    owner = "agl";
    repo = "pond";
    sha256 = "1dmgbg4ak3jkbgmxh0lr4hga1nl623mh7pvsgby1rxl4ivbzwkh4";

    buildInputs = [ net crypto protobuf ed25519 pkgs.trousers ]
      ++ stdenv.lib.optional isx86_64 pkgs.dclxvi
      ++ stdenv.lib.optionals gui [ go-gtk-agl pkgs.wrapGAppsHook ];
    buildFlags = stdenv.lib.optionalString (!gui) "-tags nogui";
    excludedPackages = "\\(appengine\\|bn256cgo\\)";
    postPatch = stdenv.lib.optionalString isx86_64 ''
      grep -r 'bn256' | awk -F: '{print $1}' | xargs sed -i \
        -e "s,golang.org/x/crypto/bn256,github.com/agl/pond/bn256cgo,g" \
        -e "s,bn256\.,bn256cgo.,g"
    '';
  };

  pongo2 = buildFromGitHub {
    rev    = "5e81b817a0c48c1c57cdf1a9056cf76bdee02ca9";
    date   = "2014-10-27";
    owner  = "flosch";
    repo   = "pongo2";
    sha256 = "0fd7d79644zmcirsb1gvhmh0l5vb5nyxmkzkvqpmzzcg6yfczph8";
    goPackagePath = "gopkg.in/flosch/pongo2.v3";
  };

  pool = buildGoPackage rec {
    rev = "v2.0.0";
    name = "pq-${rev}";
    goPackagePath = "gopkg.in/fatih/pool.v2";

    src = fetchFromGitHub {
      inherit rev;
      owner = "fatih";
      repo = "pool";
      sha256 = "1jlrakgnpvhi2ny87yrsj1gyrcncfzdhypa9i2mlvvzqlj4r0dn0";
    };
  };

  pq = buildFromGitHub {
    rev = "69552e54d2a9d4c6a2438926a774930f7bc398ec";
    owner  = "lib";
    repo   = "pq";
    sha256 = "04x1341x2cbw2ikxj3rgc48l6i41dp21xywks0ns5c4pq7v6mpgr";
  };

  pretty = buildGoPackage rec {
    rev = "bc9499caa0f45ee5edb2f0209fbd61fbf3d9018f";
    name = "pretty-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/kr/pretty";
    src = fetchFromGitHub {
      inherit rev;
      owner = "kr";
      repo = "pretty";
      sha256 = "1m61y592qsnwsqn76v54mm6h2pcvh4wlzbzscc1ag645x0j33vvl";
    };
    propagatedBuildInputs = [ kr.text ];
  };

  prometheus_alertmanager = buildGoPackage rec {
    name = "prometheus-alertmanager-${rev}";
    rev = "0.0.4";
    goPackagePath = "github.com/prometheus/alertmanager";

    src = fetchFromGitHub {
      owner = "prometheus";
      repo = "alertmanager";
      inherit rev;
      sha256 = "0g656rzal7m284mihqdrw23vhs7yr65ax19nvi70jl51wdallv15";
    };

    buildInputs = [
      fsnotify.v0
      httprouter
      prometheus_client_golang
      prometheus_log
      pushover
    ];

    buildFlagsArray = ''
      -ldflags=
          -X main.buildVersion=${rev}
          -X main.buildBranch=master
          -X main.buildUser=nix@nixpkgs
          -X main.buildDate=20150101-00:00:00
          -X main.goVersion=${stdenv.lib.getVersion go}
    '';

    meta = with stdenv.lib; {
      description = "Alert dispatcher for the Prometheus monitoring system";
      homepage = https://github.com/prometheus/alertmanager;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_client_golang = buildFromGitHub {
    rev = "15006a7ed88e73201c4e6142a2e66b54ae5fdf00";
    owner = "prometheus";
    repo = "client_golang";
    sha256 = "1cqk4d9acx7n9j73xlrv8rvakf39g1b17x01gw0c6nd924ajzsdl";
    propagatedBuildInputs = [
      goautoneg
      net
      protobuf
      prometheus_client_model
      prometheus_common
      prometheus_procfs
      beorn7_perks
    ];
  };

  prometheus_cli = buildFromGitHub {
    rev = "0.3.0";
    owner = "prometheus";
    repo = "prometheus_cli";
    sha256 = "1qxqrcbd0d4mrjrgqz882jh7069nn5gz1b84rq7d7z1f1dqhczxn";

    buildInputs = [
      prometheus_client_model
      prometheus_client_golang
    ];

    meta = with stdenv.lib; {
      description = "Command line tool for querying the Prometheus HTTP API";
      homepage = https://github.com/prometheus/prometheus_cli;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_client_model = buildFromGitHub {
    rev    = "fa8ad6fec33561be4280a8f0514318c79d7f6cb6";
    date   = "2015-02-12";
    owner  = "prometheus";
    repo   = "client_model";
    sha256 = "11a7v1fjzhhwsl128znjcf5v7v6129xjgkdpym2lial4lac1dhm9";
    buildInputs = [ protobuf ];
  };

  prometheus_collectd-exporter = buildFromGitHub {
    rev = "0.1.0";
    owner = "prometheus";
    repo = "collectd_exporter";
    sha256 = "165zsdn0lffb6fvxz75szmm152a6wmia5skb96k1mv59qbmn9fi1";
    buildInputs = [ prometheus_client_golang ];
    meta = with stdenv.lib; {
      description = "Relay server for exporting metrics from collectd to Prometheus";
      homepage = https://github.com/prometheus/alertmanager;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_common = buildFromGitHub {
    date = "2016-02-11";
    rev = "23070236b1ebff452f494ae831569545c2b61d26";
    owner = "prometheus";
    repo = "common";
    sha256 = "111vqp3lqsdli7z5rnkrpcfv6yri0qjikyl70whwxzcvkqp9k42s";
    buildInputs = [ net prometheus_client_model httprouter logrus protobuf ];
    propagatedBuildInputs = [ golang_protobuf_extensions ];
  };

  prometheus_haproxy-exporter = buildFromGitHub {
    rev = "0.4.0";
    owner = "prometheus";
    repo = "haproxy_exporter";
    sha256 = "0cwls1d4hmzjkwc50mjkxjb4sa4q6yq581wlc5sg9mdvl6g91zxr";
    buildInputs = [ prometheus_client_golang ];
    meta = with stdenv.lib; {
      description = "HAProxy Exporter for the Prometheus monitoring system";
      homepage = https://github.com/prometheus/haproxy_exporter;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_log = buildFromGitHub {
    rev    = "439e5db48fbb50ebbaf2c816030473a62f505f55";
    date   = "2015-05-29";
    owner  = "prometheus";
    repo   = "log";
    sha256 = "1fl23gsw2hn3c1y91qckr661sybqcw2gqnd1gllxn3hp6p2w6hxv";
    propagatedBuildInputs = [ logrus ];
  };

  prometheus_mesos-exporter = buildFromGitHub {
    rev = "0.1.0";
    owner = "prometheus";
    repo = "mesos_exporter";
    sha256 = "059az73j717gd960g4jigrxnvqrjh9jw1c324xpwaafa0bf10llm";
    buildInputs = [ mesos-stats prometheus_client_golang glog ];
    meta = with stdenv.lib; {
      description = "Export Mesos metrics to Prometheus";
      homepage = https://github.com/prometheus/mesos_exporter;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_mysqld-exporter = buildFromGitHub {
    rev = "0.1.0";
    owner = "prometheus";
    repo = "mysqld_exporter";
    sha256 = "10xnyxyb6saz8pq3ijp424hxy59cvm1b5c9zcbw7ddzzkh1f6jd9";
    buildInputs = [ mysql prometheus_client_golang ];
    meta = with stdenv.lib; {
      description = "Prometheus exporter for MySQL server metrics";
      homepage = https://github.com/prometheus/mysqld_exporter;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_nginx-exporter = buildFromGitHub {
    rev = "2cf16441591f6b6e58a8c0439dcaf344057aea2b";
    date = "2015-06-01";
    owner = "discordianfish";
    repo = "nginx_exporter";
    sha256 = "0p9j0bbr2lr734980x2p8d67lcify21glwc5k3i3j4ri4vadpxvc";
    buildInputs = [ prometheus_client_golang prometheus_log ];
    meta = with stdenv.lib; {
      description = "Metrics relay from nginx stats to Prometheus";
      homepage = https://github.com/discordianfish/nginx_exporter;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_node-exporter = buildFromGitHub {
    rev = "0.10.0";
    owner = "prometheus";
    repo = "node_exporter";
    sha256 = "0dmczav52v9vi0kxl8gd2s7x7c94g0vzazhyvlq1h3729is2nf0p";

    buildInputs = [
      go-runit
      ntp
      prometheus_client_golang
      prometheus_client_model
      prometheus_log
      protobuf
    ];

    meta = with stdenv.lib; {
      description = "Prometheus exporter for machine metrics";
      homepage = https://github.com/prometheus/node_exporter;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_procfs = buildFromGitHub {
    rev    = "406e5b7bfd8201a36e2bb5f7bdae0b03380c2ce8";
    date   = "2015-10-29";
    owner  = "prometheus";
    repo   = "procfs";
    sha256 = "0yla9hz15pg63394ygs9iiwzsqyv29labl8p424hijwsc9z9nka8";
  };

  prometheus_prom2json = buildFromGitHub {
    rev = "0.1.0";
    owner = "prometheus";
    repo = "prom2json";
    sha256 = "0wwh3mz7z81fwh8n78sshvj46akcgjhxapjgfic5afc4nv926zdl";

    buildInputs = [
      golang_protobuf_extensions
      prometheus_client_golang
      protobuf
    ];

    meta = with stdenv.lib; {
      description = "Tool to scrape a Prometheus client and dump the result as JSON";
      homepage = https://github.com/prometheus/prom2json;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_prometheus = buildGoPackage rec {
    name = "prometheus-${version}";
    version = "0.15.1";
    goPackagePath = "github.com/prometheus/prometheus";
    rev = "64349aade284846cb194be184b1b180fca629a7c";

    src = fetchFromGitHub {
      inherit rev;
      owner = "prometheus";
      repo = "prometheus";
      sha256 = "0gljpwnlip1fnmhbc96hji2rc56xncy97qccm7v1z5j1nhc5fam2";
    };

    buildInputs = [
      consul
      dns
      fsnotify.v1
      go-zookeeper
      goleveldb
      httprouter
      logrus
      net
      prometheus_client_golang
      prometheus_log
      yaml-v2
    ];

    preInstall = ''
      mkdir -p "$bin/share/doc/prometheus" "$bin/etc/prometheus"
      cp -a $src/documentation/* $bin/share/doc/prometheus
      cp -a $src/console_libraries $src/consoles $bin/etc/prometheus
    '';

    # Metadata that gets embedded into the binary
    buildFlagsArray = let t = "${goPackagePath}/version"; in
    ''
      -ldflags=
          -X ${t}.Version=${version}
          -X ${t}.Revision=${builtins.substring 0 6 rev}
          -X ${t}.Branch=master
          -X ${t}.BuildUser=nix@nixpkgs
          -X ${t}.BuildDate=20150101-00:00:00
          -X ${t}.GoVersion=${stdenv.lib.getVersion go}
    '';

    meta = with stdenv.lib; {
      description = "Service monitoring system and time series database";
      homepage = http://prometheus_io;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_pushgateway = buildFromGitHub rec {
    rev = "0.1.1";
    owner = "prometheus";
    repo = "pushgateway";
    sha256 = "17q5z9msip46wh3vxcsq9lvvhbxg75akjjcr2b29zrky8bp2m230";

    buildInputs = [
      protobuf
      httprouter
      golang_protobuf_extensions
      prometheus_client_golang
    ];

    nativeBuildInputs = [ go-bindata.bin ];
    preBuild = ''
    (
      cd "go/src/$goPackagePath"
      go-bindata ./resources/
    )
    '';

    buildFlagsArray = ''
      -ldflags=
          -X main.buildVersion=${rev}
          -X main.buildRev=${rev}
          -X main.buildBranch=master
          -X main.buildUser=nix@nixpkgs
          -X main.buildDate=20150101-00:00:00
          -X main.goVersion=${stdenv.lib.getVersion go}
    '';

    meta = with stdenv.lib; {
      description = "Allows ephemeral and batch jobs to expose metrics to Prometheus";
      homepage = https://github.com/prometheus/pushgateway;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  prometheus_statsd-bridge = buildFromGitHub {
    rev = "0.1.0";
    owner = "prometheus";
    repo = "statsd_bridge";
    sha256 = "1fndpmd1k0a3ar6f7zpisijzc60f2dng5399nld1i1cbmd8jybjr";
    buildInputs = [ fsnotify.v0 prometheus_client_golang ];
    meta = with stdenv.lib; {
      description = "Receives StatsD-style metrics and exports them to Prometheus";
      homepage = https://github.com/prometheus/statsd_bridge;
      license = licenses.asl20;
      maintainers = with maintainers; [ benley ];
      platforms = platforms.unix;
    };
  };

  properties = buildFromGitHub {
    rev    = "v1.5.6";
    owner  = "magiconair";
    repo   = "properties";
    sha256 = "043jhba7qbbinsij3yc475s1i42sxaqsb82mivh9gncpvnmnf6cl";
  };

  gogo.protobuf = buildFromGitHub {
    rev = "932b70afa8b0bf4a8e167fdf0c3367cebba45903";
    owner = "gogo";
    repo = "protobuf";
    sha256 = "1djhv9ckqhyjnnqajjv8ivcwpmjdnml30l6zhgbjcjwdyz3nyzhx";
    excludedPackages = "test";
    goPackageAliases = [
      "code.google.com/p/gogoprotobuf"
    ];
  };

  pty = buildFromGitHub {
    rev    = "67e2db24c831afa6c64fc17b4a143390674365ef";
    owner  = "kr";
    repo   = "pty";
    sha256 = "1l3z3wbb112ar9br44m8g838z0pq2gfxcp5s3ka0xvm1hjvanw2d";
  };

  purell = buildFromGitHub {
    rev    = "d69616f51cdfcd7514d6a380847a152dfc2a749d";
    owner  = "PuerkitoBio";
    repo   = "purell";
    sha256 = "0nma5i25j0y223ns7482lx4klcfhfwdr8v6r9kzrs0pwlq64ghs0";
    propagatedBuildInputs = [ urlesc ];
  };

  pushover = buildFromGitHub {
    rev    = "a8420a1935479cc266bda685cee558e86dad4b9f";
    owner  = "thorduri";
    repo   = "pushover";
    sha256 = "0j4k43ppka20hmixlwhhz5mhv92p6wxbkvdabs4cf7k8jpk5argq";
  };

  qart = buildFromGitHub {
    date   = "2014-04-19";
    rev    = "ccb109cf25f0cd24474da73b9fee4e7a3e8a8ce0";
    owner  = "vitrun";
    repo   = "qart";
    sha256 = "0bhp768b8ha6f25dmhwn9q8m2lkbn4qnjf8n7pizk25jn5zjdvc8";
  };

  ql = buildFromGitHub {
    date = "2016-02-03";
    rev = "9cddc341060180c73b0a57b0b0592884b0e05c51";
    owner  = "cznic";
    repo   = "ql";
    sha256 = "0za2dvwfas6l1g4i9xcv75f17ymxl5an71djiyck08zxg979lk8p";
    propagatedBuildInputs = [ go4 b exp strutil ];
  };

  raft = buildFromGitHub {
    date = "2016-01-21";
    rev = "057b893fd996696719e98b6c44649ea14968c811";
    owner  = "hashicorp";
    repo   = "raft";
    sha256 = "1b4x1b8d6mc7qz3r0im71wrphnjd618clnady899cylwsynjsb54";
    propagatedBuildInputs = [ armon_go-metrics ugorji_go ];
  };

  raft-boltdb = buildFromGitHub {
    date = "2015-02-01";
    rev = "d1e82c1ec3f15ee991f7cc7ffd5b67ff6f5bbaee";
    owner  = "hashicorp";
    repo   = "raft-boltdb";
    sha256 = "0p609w6x0h6bapx4b0d91dxnp2kj7dv0534q4blyxp79shv2a8ia";
    propagatedBuildInputs = [ bolt ugorji_go raft ];
  };

  ratelimit = buildFromGitHub {
    rev    = "77ed1c8a01217656d2080ad51981f6e99adaa177";
    date   = "2015-11-25";
    owner  = "juju";
    repo   = "ratelimit";
    sha256 = "1r7xdl3bpdzny4d05fpm229864ipghqwv5lplv5im5b4vhv9ryp7";
  };

  relaysrv = buildFromGitHub rec {
    rev = "v0.12.1";
    owner  = "syncthing";
    repo   = "relaysrv";
    sha256 = "0lnq3pi8v5rwfvx4k93a7aiq44b1rx5dydp29si10w02592m9nbr";
    buildInputs = [ syncthing-lib du ratelimit net ];
    excludedPackages = "testutil";
  };

  reflectwalk = buildFromGitHub {
    date   = "2015-05-27";
    rev    = "eecf4c70c626c7cfbb95c90195bc34d386c74ac6";
    owner  = "mitchellh";
    repo   = "reflectwalk";
    sha256 = "1nm2ig7gwlmf04w7dbqd8d7p64z2030fnnfbgnd56nmd7dz8gpxq";
  };

  restic = buildFromGitHub {
    rev    = "4d7e802c44369b40177cd52938bc5b0930bd2be1";
    date   = "2016-01-17";
    owner  = "restic";
    repo   = "restic";
    sha256 = "0lf40539dy2xa5l1xy1kyn1vk3w0fmapa1h65ciksrdhn89ilrxv";
    # Using its delivered dependencies. Easier.
    preBuild = "export GOPATH=$GOPATH:$NIX_BUILD_TOP/go/src/$goPackagePath/Godeps/_workspace";
  };

  rgbterm = buildFromGitHub {
    rev    = "c07e2f009ed2311e9c35bca12ec00b38ccd48283";
    owner  = "aybabtme";
    repo   = "rgbterm";
    sha256 = "1qph7drds44jzx1whqlrh1hs58k0wv0v58zyq2a81hmm72gsgzam";
  };

  ripper = buildFromGitHub {
    rev    = "bd1a682568fcb8a480b977bb5851452fc04f9ccb";
    owner  = "odeke-em";
    repo   = "ripper";
    sha256 = "010jsclnmkaywdlyfqdmq372q7kh3qbz2zra0c4wn91qnkmkrnw1";
  };

  rsrc = buildFromGitHub {
    rev    = "ba14da1f827188454a4591717fff29999010887f";
    date   = "2015-11-03";
    owner  = "akavel";
    repo   = "rsrc";
    sha256 = "0g9fj10xnxcv034c8hpcgbhswv6as0d8l176c5nfgh1lh6klmmzc";
  };

  sandblast = buildGoPackage rec {
    rev = "694d24817b9b7b8bacb6d458b7989b30d7fe3555";
    name = "sandblast-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/aarzilli/sandblast";

    src = fetchFromGitHub {
      inherit rev;
      owner  = "aarzilli";
      repo   = "sandblast";
      sha256 = "1pj0bic3x89v44nr8ycqxwnafkiz3cr5kya4wfdfj5ldbs5xnq9l";
    };

    buildInputs = [ net text ];
  };

  # This is the upstream package name, underscores and all. I don't like it
  # but it seems wrong to change their name when packaging it.
  sanitized_anchor_name = buildFromGitHub {
    rev    = "10ef21a441db47d8b13ebcc5fd2310f636973c77";
    owner  = "shurcooL";
    repo   = "sanitized_anchor_name";
    sha256 = "1cnbzcf47cn796rcjpph1s64qrabhkv5dn9sbynsy7m9zdwr5f01";
  };

  scada-client = buildFromGitHub {
    date = "2015-08-28";
    rev = "84989fd23ad4cc0e7ad44d6a871fd793eb9beb0a";
    owner  = "hashicorp";
    repo   = "scada-client";
    sha256 = "13rzscxn866kzrfjpdaxyqfg8p12rxyd62nzw7z6gzsl4lg3q8m1";
    buildInputs = [ armon_go-metrics net-rpc-msgpackrpc yamux ];
  };

  seelog = buildFromGitHub {
    rev = "c510775bb50d98213cfafca75a4bc5e3fddc8d8f";
    date = "2015-05-26";
    owner = "cihub";
    repo = "seelog";
    sha256 = "1f0rwgqlffv1a7b05736a4gf4l9dn80wsfyqcnz6qd2skhwnzv29";
  };

  segment = buildFromGitHub {
    rev    = "db70c57796cc8c310613541dfade3dce627d09c7";
    date   = "2016-01-05";
    owner  = "blevesearch";
    repo   = "segment";
    sha256 = "09xfdlcc6bsrr5grxp6fgnw9p4cf6jc0wwa9049fd1l0zmhj2m1g";
  };

  semver = buildFromGitHub {
    rev = "v3.1.0";
    owner = "blang";
    repo = "semver";
    sha256 = "1s80qlij6j6wrh0fhm0l11hbf3qjra67nca5bl7izyfjj4621fcd";
  };

  serf = buildFromGitHub {
    rev = "v0.7.0";
    owner  = "hashicorp";
    repo   = "serf";
    sha256 = "1zj2s29qjcaai2w03ak3rxidcmgi3mfp94f5nrmkblm44mc6667r";

    buildInputs = [
      net circbuf armon_go-metrics ugorji_go go-syslog logutils mdns memberlist
      dns mitchellh-cli mapstructure columnize
    ];
  };

  sets = buildGoPackage rec {
    rev = "6c54cb57ea406ff6354256a4847e37298194478f";
    name = "sets-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/feyeleanor/sets";
    src = fetchFromGitHub {
      inherit rev;
      owner  = "feyeleanor";
      repo   = "sets";
      sha256 = "1l3hyl8kmwb9k6qi8x4w54g2cmydap0g3cqvs47bhvm47rg1j1zc";
    };
    propagatedBuildInputs = [ slices ];
  };

  skydns = buildFromGitHub {
    rev = "2.5.2b";
    owner = "skynetservices";
    repo = "skydns";
    sha256 = "01vac6bd71wky5jbd5k4a0x665bjn1cpmw7p655jrdcn5757c2lv";

    buildInputs = [
      go-etcd rcrowley_go-metrics dns go-systemd prometheus_client_golang
    ];
  };

  slices = buildGoPackage rec {
    rev = "bb44bb2e4817fe71ba7082d351fd582e7d40e3ea";
    name = "slices-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/feyeleanor/slices";
    src = fetchFromGitHub {
      inherit rev;
      owner  = "feyeleanor";
      repo   = "slices";
      sha256 = "1miqhzqgww41d8xbvmxfzx9rsfxgw742nqz96mhjkxpadrxg870v";
    };
    propagatedBuildInputs = [ raw ];
  };

  sortutil = buildFromGitHub {
    date = "2015-06-17";
    rev = "4c7342852e65c2088c981288f2c5610d10b9f7f4";
    owner = "cznic";
    repo = "sortutil";
    sha256 = "1i46kdwnh8p54sp0jkybd3ayc599hdy37kvwqrxlg746flz5inyl";
  };

  spacelog = buildFromGitHub {
    date = "2015-03-20";
    rev = "ae95ccc1eb0c8ce2496c43177430efd61930f7e4";
    owner = "spacemonkeygo";
    repo = "spacelog";
    sha256 = "1i1awivsix0ch0vg6rwvx0536ziyw6phcx45b1rmrclp6b6dyacy";
    buildInputs = [ flagfile ];
  };

  speakeasy = buildFromGitHub {
    date = "2015-09-02";
    rev = "36e9cfdd690967f4f690c6edcc9ffacd006014a0";
    owner = "bgentry";
    repo = "speakeasy";
    sha256 = "1gv69wvy17ggaydr3xdnnc0amys70wcmjhjj1xz2bj0kxi7yf8yf";
  };

  stathat = buildFromGitHub {
    date = "2016-01-26";
    rev = "cf69b0bcb80478755dc0ea1120b36000e35dcbbb";
    owner = "stathat";
    repo = "go";
    sha256 = "15pzhn5mxlbcamldkqh6z160ijrg1h9r5qlsrfi3cqdxhhr3c19s";
  };

  statos = buildFromGitHub {
    rev    = "f27d6ab69b62abd9d9fe80d355e23a3e45d347d6";
    owner  = "odeke-em";
    repo   = "statos";
    sha256 = "17cpks8bi9i7p8j38x0wy60jb9g39wbzszcmhx4hlq6yzxr04jvs";
  };

  statik = buildGoPackage rec {
    rev = "274df120e9065bdd08eb1120e0375e3dc1ae8465";
    name = "statik-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/rakyll/statik";

    excludedPackages = "example";

    src = fetchFromGitHub {
      inherit rev;
      owner = "rakyll";
      repo = "statik";
      sha256 = "0llk7bxmk66wdiy42h32vj1jfk8zg351xq21hwhrq7gkfljghffp";
    };
  };

  structfield = buildFromGitHub {
    rev    = "01a738558a47fbf16712994d1737fb31c77e7d11";
    date   = "2014-08-01";
    owner  = "vincent-petithory";
    repo   = "structfield";
    sha256 = "1kyx71z13mf6hc8ly0j0b9zblgvj5lzzvgnc3fqh61wgxrsw24dw";
  };

  structs = buildFromGitHub {
    date = "2016-01-23";
    rev = "a924a2250d1033753512e95dce41dca3fd793ad9";
    owner  = "fatih";
    repo   = "structs";
    sha256 = "0mhaqmsij9szy8wvn8lmq4644a1gmr0666yyxlw10kif1kyi9m80";
  };

  stump = buildFromGitHub {
    date = "2015-11-05";
    rev = "bdc01b1f13fc5bed17ffbf4e0ed7ea17fd220ee6";
    owner = "whyrusleeping";
    repo = "stump";
    sha256 = "010pgp6bd6dnl2cqg9nmxif30dgpaz07frhfk0hwl58yxv3a3vjh";
  };

  strutil = buildFromGitHub {
    date = "2015-04-30";
    rev = "1eb03e3cc9d345307a45ec82bd3016cde4bd4464";
    owner = "cznic";
    repo = "strutil";
    sha256 = "0n4ib4ixpxh4fah145s2ikbzyqxbax8gj44081agg8jkzs74cnvm";
  };

  suture = buildFromGitHub rec {
    version = "1.0.1";
    rev    = "v${version}";
    owner  = "thejerf";
    repo   = "suture";
    sha256 = "094ksr2nlxhvxr58nbnzzk0prjskb21r86jmxqjr3rwg4rkwn6d4";
  };

  syncthing = buildFromGitHub rec {
    version = "0.12.16";
    rev = "v0.12.18";
    owner = "syncthing";
    repo = "syncthing";
    sha256 = "00a6m4w41f5md8459sqrl81zkcxbl7m5np6k2lxnydkq3lw0bibv";
    buildFlags = [ "-tags noupgrade,release" ];
    buildInputs = [
      go-lz4 du luhn xdr snappy ratelimit osext
      goleveldb suture qart crypto net text rcrowley_go-metrics
    ];
    postPatch = ''
      # Mostly a cosmetic change
      sed -i 's,unknown-dev,${version},g' cmd/syncthing/main.go
    '';
  };

  syncthing-lib = buildFromGitHub {
    inherit (syncthing) rev owner repo sha256;
    subPackages = [
      "lib/sync"
      "lib/logger"
      "lib/protocol"
      "lib/osutil"
      "lib/tlsutil"
      "lib/dialer"
      "lib/relay/client"
      "lib/relay/protocol"
    ];
    propagatedBuildInputs = [ go-lz4 luhn xdr text suture du net ];
  };

  tablewriter = buildFromGitHub {
    rev    = "bc39950e081b457853031334b3c8b95cdfe428ba";
    date   = "2015-06-03";
    owner  = "olekukonko";
    repo   = "tablewriter";
    sha256 = "0n4gqjc2dqmnbpqgi9i8vrwdk4mkgyssc7l2n4r5bqx0n3nxpbps";
  };

  tar-utils = buildFromGitHub {
    rev = "e8a5890cfc9d59a203361237581468780d945b6e";
    date = "2015-08-09";
    owner  = "whyrusleeping";
    repo   = "tar-utils";
    sha256 = "1dkw7p3hm614m2z49pcpnma5i25cfrg7kn1ir5jandjz8davzy5d";
  };

  termbox-go = buildGoPackage rec {
    rev = "9aecf65084a5754f12d27508fa2e6ed56851953b";
    name = "termbox-go-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/nsf/termbox-go";
    src = fetchFromGitHub {
      inherit rev;
      owner = "nsf";
      repo = "termbox-go";
      sha256 = "16sak07bgvmax4zxfrd4jia1dgygk733xa8vk8cdx28z98awbfsh";
    };

    subPackages = [ "./" ]; # prevent building _demos
  };

  testify = buildFromGitHub {
    rev = "v1.1.3";
    owner = "stretchr";
    repo = "testify";
    sha256 = "1l3z0ggdcjspfmm6k9glmh52a9x50806k6yldxql73p4bpynsd9g";
    propagatedBuildInputs = [ objx go-difflib go-spew ];
  };

  kr.text = buildGoPackage rec {
    rev = "6807e777504f54ad073ecef66747de158294b639";
    name = "kr.text-${stdenv.lib.strings.substring 0 7 rev}";
    goPackagePath = "github.com/kr/text";
    src = fetchFromGitHub {
      inherit rev;
      owner = "kr";
      repo = "text";
      sha256 = "1wkszsg08zar3wgspl9sc8bdsngiwdqmg3ws4y0bh02sjx5a4698";
    };
    propagatedBuildInputs = [ pty ];
  };

  timer_metrics = buildFromGitHub {
    rev = "afad1794bb13e2a094720aeb27c088aa64564895";
    date = "2015-02-02";
    owner = "bitly";
    repo = "timer_metrics";
    sha256 = "1b717vkwj63qb5kan4b92kx4rg6253l5mdb3lxpxrspy56a6rl0c";
  };

  tomb = buildFromGitHub {
    date = "2014-06-26";
    rev = "14b3d72120e8d10ea6e6b7f87f7175734b1faab8";
    owner = "go-tomb";
    repo = "tomb";
    sha256 = "1nza31jvkpka5431c4bdbirvjdy36b1b55sbzljqhqih25jrcjx5";
    goPackagePath = "gopkg.in/tomb.v2";
    goPackageAliases = [ "github.com/go-tomb/tomb" ];
  };

  toml = buildFromGitHub {
    rev    = "056c9bc7be7190eaa7715723883caffa5f8fa3e4";
    date   = "2015-05-01";
    owner  = "BurntSushi";
    repo   = "toml";
    sha256 = "0gkgkw04ndr5y7hrdy0r4v2drs5srwfcw2bs1gyas066hwl84xyw";
  };

  uilive = buildFromGitHub {
    rev = "1b9b73fa2b2cc24489b1aba4d29a82b12cd0a71f";
    owner = "gosuri";
    repo = "uilive";
    sha256 = "0669f21hd5cw74irrfakdpvxn608cd5xy6s2nyp5kgcy2ijrq4ab";
  };

  uiprogress = buildFromGitHub {
    buildInputs = [ uilive ];
    rev = "fd1c82df78a6c1f5ddbd3b6ec46407ea0acda1ad";
    owner = "gosuri";
    repo = "uiprogress";
    sha256 = "1s61vp2h6n1d8y1zqr2ca613ch5n18rx28waz6a8im94sgzzawp7";
  };

  urlesc = buildFromGitHub {
    rev    = "5fa9ff0392746aeae1c4b37fcc42c65afa7a9587";
    owner  = "opennota";
    repo   = "urlesc";
    sha256 = "0dppkmfs0hb5vcqli191x9yss5vvlx29qxjcywhdfirc89rn0sni";
  };

  usb = buildFromGitHub rec {
    rev = "69aee4530ac705cec7c5344418d982aaf15cf0b1";
    date = "2014-12-17";
    owner = "hanwen";
    repo = "usb";
    sha256 = "01k0c2g395j65vm1w37mmrfkg6nm900khjrrizzpmx8f8yf20dky";

    nativeBuildInputs = [ pkgs.pkgconfig ];
    buildInputs = [ pkgs.libusb1 ];
  };

  pborman_uuid = buildFromGitHub {
    rev = "cccd189d45f7ac3368a0d127efb7f4d08ae0b655";
    date = "2015-08-24";
    owner = "pborman";
    repo = "uuid";
    sha256 = "0hswk9ihv3js5blp9pk2bpig64zkmyp5p1zhmgydfhb0dr2w8iad";
  };

  hashicorp_uuid = buildFromGitHub {
    rev = "2951e8b9707a040acdb49145ed9f36a088f3532e";
    date = "2015-10-12";
    owner = "hashicorp";
    repo = "uuid";
    sha256 = "054bjcrq8q1jz9v3jm1pjjchjlxyh6j89cqzxa8jawdghf8cr8xp";
  };

  vault = buildFromGitHub rec {
    rev = "v0.5.0";
    owner = "hashicorp";
    repo = "vault";
    sha256 = "0ah6jmg19aiizh51cgrkxd7x0an18hpia4rq8dmxn14xa3cs42y0";

    buildInputs = [
      armon_go-metrics go-radix govalidator aws-sdk-go speakeasy etcd-client
      duo_api_golang structs ini ldap mysql gocql snappy go-github
      go-querystring hailocab_go-hostpool consul-api errwrap go-cleanhttp
      go-multierror go-syslog golang-lru hcl logutils serf hashicorp_uuid
      go-jmespath osext pq mitchellh-cli copystructure go-homedir mapstructure
      reflectwalk columnize go-zookeeper ugorji_go crypto net oauth2 sys
      asn1-ber inf yaml yaml-v2 hashicorp-go-uuid
    ];
  };

  vcs = buildFromGitHub {
    rev    = "1.0.0";
    owner  = "Masterminds";
    repo   = "vcs";
    sha256 = "1qav4lf4ln5gs81714876q2cy9gfaxblbvawg3hxznbwakd9zmd8";
  };

  viper = buildFromGitHub {
    rev    = "e37b56e207dda4d79b9defe0548e960658ee8b6b";
    owner  = "spf13";
    repo   = "viper";
    sha256 = "0q0hkla23hgvc3ab6qdlrfwxa8lnhy2s2mh2c8zrh632gp8d6prl";
    propagatedBuildInputs = [
      mapstructure yaml-v2 jwalterweatherman crypt fsnotify.v1 cast properties
      pretty toml pflag-spf13
    ];
  };

  vulcand = buildGoPackage rec {
    rev = "v0.8.0-beta.3";
    name = "vulcand-${rev}";
    goPackagePath = "github.com/mailgun/vulcand";
    preBuild = "export GOPATH=$GOPATH:$NIX_BUILD_TOP/go/src/${goPackagePath}/Godeps/_workspace";
    src = fetchFromGitHub {
      inherit rev;
      owner = "mailgun";
      repo = "vulcand";
      sha256 = "08mal9prwlsav63r972q344zpwqfql6qw6v4ixbn1h3h32kk3ic6";
    };
    subPackages = [ "./" ];
  };

  websocket = buildFromGitHub {
    rev    = "6eb6ad425a89d9da7a5549bc6da8f79ba5c17844";
    owner  = "gorilla";
    repo   = "websocket";
    sha256 = "0gljdfxqc94yb1kpqqrm5p94ph9dsxrzcixhdj6m92cwwa7z7p99";
  };

  xmpp-client = buildFromGitHub {
    rev      = "525bd26cf5f56ec5aee99464714fd1d019c119ff";
    date     = "2016-01-10";
    owner    = "agl";
    repo     = "xmpp-client";
    sha256   = "0a1r08zs723ikcskmn6ylkdi3frcd0i0lkx30i9q39ilf734v253";
    buildInputs = [ crypto net ];

    meta = with stdenv.lib; {
      description = "An XMPP client with OTR support";
      homepage = https://github.com/agl/xmpp-client;
      license = licenses.bsd3;
      maintainers = with maintainers; [ codsl ];
    };
  };

  yaml = buildFromGitHub {
    rev = "73d445a93680fa1a78ae23a5839bad48f32ba1ee";
    date = "2015-09-08";
    owner = "ghodss";
    repo = "yaml";
    sha256 = "0pg53ky4sy3sp9j4n7vgf1p3gw4nbckwqfldcmmi9rf13kjh0mr7";
    buildInputs = [ yaml-v2 ];
  };

  yaml-v1 = buildGoPackage rec {
    name = "yaml-v1-${version}";
    version = "git-2015-05-01";
    goPackagePath = "gopkg.in/yaml.v1";
    src = fetchFromGitHub {
      rev = "b0c168ac0cf9493da1f9bb76c34b26ffef940b4a";
      owner = "go-yaml";
      repo = "yaml";
      sha256 = "0jbdy41pplf2d1j24qwr8gc5qsig6ai5ch8rwgvg72kq9q0901cy";
    };
  };

  yaml-v2 = buildFromGitHub {
    rev = "f7716cbe52baa25d2e9b0d0da546fcf909fc16b4";
    date = "2015-12-01";
    owner = "go-yaml";
    repo = "yaml";
    sha256 = "1v569hk9n995vvddh99xc9n1nhakl39hi88bqyxamgc4gxdmnfcw";
    goPackagePath = "gopkg.in/yaml.v2";
  };

  yamux = buildFromGitHub {
    date   = "2015-11-29";
    rev    = "df949784da9ed028ee76df44652e42d37a09d7e4";
    owner  = "hashicorp";
    repo   = "yamux";
    sha256 = "0mavyqm3wvxpbiyap79vh3j4yksfy4g7p3vwyr7ha5kcav1918x4";
  };

  xdr = buildFromGitHub {
    rev    = "e467b5aeb65ca8516fb3925c84991bf1d7cc935e";
    date   = "2015-11-24";
    owner  = "calmh";
    repo   = "xdr";
    sha256 = "1bi4b2xkjzcr0vq1wxz14i9943k71sj092dam0gdmr9yvdrg0nra";
  };

  xon = buildFromGitHub {
    rev    = "d580be739d723da4f6378083128f93017b8ab295";
    owner  = "odeke-em";
    repo   = "xon";
    sha256 = "07a7zj01d4a23xqp01m48jp2v5mw49islf4nbq2rj13sd5w4s6sc";
  };

  zappy = buildFromGitHub {
    date = "2014-08-20";
    rev = "47331054e4f96186e3ff772877c0443909368a45";
    owner = "cznic";
    repo = "zappy";
    sha256 = "1p4v7gjpvz800ykz7i92i333xbahplbir21i2vrksb8zfw14db14";
  };

  ninefans = buildFromGitHub {
    rev    = "65b8cf069318223b1e722b4b36e729e5e9bb9eab";
    date   = "2015-10-24";
    owner  = "9fans";
    repo   = "go";
    sha256 = "0kzyxhs2xf0339nlnbm9gc365b2svyyjxnr86rphx5m072r32ims";
    goPackagePath = "9fans.net/go";
    goPackageAliases = [
      "github.com/9fans/go"
    ];
    excludedPackages = "\\(plan9/client/cat\\|acme/Watch\\)";
    buildInputs = [ net ];
  };

  godef = buildFromGitHub {
    rev    = "ea14e800fd7d16918be88dae9f0195f7bd688586";
    date   = "2015-10-24";
    owner  = "rogpeppe";
    repo   = "godef";
    sha256 = "1wkvsz8nqwyp36wbm8vcw4449sfs46894nskrfj9qbsrjijvamyc";
    excludedPackages = "\\(go/printer/testdata\\)";
    buildInputs = [ ninefans ];
    subPackages = [ "./" ];
  };

  godep = buildFromGitHub {
    rev    = "5598a9815350896a2cdf9f4f1d0a3003ab9677fb";
    date   = "2015-10-15";
    owner  = "tools";
    repo   = "godep";
    sha256 = "0zc1ah5cvaqa3zw0ska89a40x445vwl1ixz8v42xi3zicx16ibwz";
  };

  color = buildFromGitHub {
    rev      = "9aae6aaa22315390f03959adca2c4d395b02fcef";
    owner    = "fatih";
    repo     = "color";
    sha256   = "1vjcgx4xc0h4870qzz4mrh1l0f07wr79jm8pnbp6a2yd41rm8wjp";
    propagatedBuildInputs = [ net go-isatty ];
    buildInputs = [ ansicolor go-colorable ];
  };

  pup = buildFromGitHub {
    rev      = "9693b292601dd24dab3c04bc628f9ae3fa72f831";
    owner    = "EricChiang";
    repo     = "pup";
    sha256   = "04j3fy1vk6xap8ad7k3c05h9b5mg2n1vy9vcyg9rs02cb13d3sy0";
    propagatedBuildInputs = [ net ];
    buildInputs = [ go-colorable color ];
    postPatch = ''
      grep -sr github.com/ericchiang/pup/Godeps/_workspace/src/ |
        cut -f 1 -d : |
        sort -u |
        xargs -d '\n' sed -i -e s,github.com/ericchiang/pup/Godeps/_workspace/src/,,g
    '';
  };

  textsecure = buildFromGitHub rec {
    rev = "505e129c42fc4c5cb2d105520cef7c04fa3a6b64";
    owner = "janimo";
    repo = "textsecure";
    sha256 = "0sdcqd89dlic0bllb6mjliz4x54rxnm1r3xqd5qdp936n7xs3mc6";
    propagatedBuildInputs = [ crypto protobuf ed25519 yaml-v2 logrus ];
  };

  interlock = buildFromGitHub rec {
    version = "2016.01.14";
    rev = "v${version}";
    owner = "inversepath";
    repo = "interlock";
    sha256 = "0wabx6vqdxh2aprsm2rd9mh71q7c2xm6xk9a6r1bn53r9dh5wrsb";
    buildInputs = [ crypto textsecure ];
    nativeBuildInputs = [ pkgs.sudo ];
    buildFlags = [ "-tags textsecure" ];
    subPackages = [ "./cmd/interlock" ];
    postPatch = ''
      grep -lr '/s\?bin/' | xargs sed -i \
        -e 's|/bin/mount|${pkgs.utillinux}/bin/mount|' \
        -e 's|/bin/umount|${pkgs.utillinux}/bin/umount|' \
        -e 's|/bin/cp|${pkgs.coreutils}/bin/cp|' \
        -e 's|/bin/mv|${pkgs.coreutils}/bin/mv|' \
        -e 's|/bin/chown|${pkgs.coreutils}/bin/chown|' \
        -e 's|/bin/date|${pkgs.coreutils}/bin/date|' \
        -e 's|/sbin/poweroff|${pkgs.systemd}/sbin/poweroff|' \
        -e 's|/usr/bin/sudo|/var/setuid-wrappers/sudo|' \
        -e 's|/sbin/cryptsetup|${pkgs.cryptsetup}/bin/cryptsetup|'
    '';
  };
}; in self
