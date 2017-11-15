{ stdenv
, buildPythonPackage
, fetchFromGitHub
, isPy2
, isPy3
, lib
, python
, pythonOlder

, apscheduler
, beautifulsoup
, cherrypy
, colorclass
, deluge
, feedparser
, flask
, flask-compress
, flask-cors
, flask-login
, flask-restful
, flask-restplus
, future
, guessit
, html5lib
, jinja2
, jsonschema
, pathlib
, pathpy
, pkgs
#, progressbar
, pynzb
, pyparsing
, pyrss2gen
, python-dateutil
, pyyaml
, requests
, rpyc
, sqlalchemy
, terminaltables
, transmissionrpc
, zxcvbn-python
}:

let
  inherit (lib)
    optionals
    optionalString;

  version = "2.10.109";
in
buildPythonPackage rec {
  name = "flexget-${version}";

  src = fetchFromGitHub {
    version = 3;
    owner = "flexget";
    repo = "flexget";
    rev = version;
    sha256 = "ca2a0169b84322ca7b732bf40d56a9f0afe5093181867b930026c82209a279f2";
  };

  propagatedBuildInputs = [
    apscheduler
    beautifulsoup
    cherrypy
    colorclass
    feedparser
    flask
    flask-compress
    flask-cors
    flask-login
    flask-restful
    flask-restplus
    future
    guessit
    html5lib
    jinja2
    jsonschema
    pathpy
    pynzb
    pyparsing
    pyrss2gen
    python-dateutil
    pyyaml
    requests
    rpyc
    sqlalchemy
    terminaltables
    transmissionrpc
    zxcvbn-python
  ] ++ optionals isPy2 [
    deluge
  ] ++ optionals (pythonOlder "3.4") [
    pathlib
  ];

  postPatch = /* Allow using newer dependencies */ ''
    sed -i requirements.txt \
      -e 's/,.*<.*//' \
      -e 's/<.*//' \
      -e 's/!=.*//' \
      -e 's/==.*//'
  '' + /* Fix discover plugin not respecting limit */ ''
    sed -i flexget/plugins/input/discover.py \
      -e '/>\s500/,+2d'
  '' + optionalString isPy3 /* Fix python2 only requirements */ ''
    sed -i setup.cfg \
      -e '/python-tag/d'
    sed -i requirements.txt \
      -e '/pathlib/d'
  '';

  meta = with lib; {
    description = "Automation tool for content like torrents, nzbs, podcasts";
    homepage = http://flexget.com/;
    license = licenses.mit;
    maintainers = with maintainers; [
      codyopel
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
