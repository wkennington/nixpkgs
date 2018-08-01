{ stdenv
, fetchurl

, hiredis
, jemalloc
, linenoise
, luajit
}:

let
  version = "4.0.10";

  jemalloc' = jemalloc.override {
    functionPrefix = "je_";
  };
in
stdenv.mkDerivation rec {
  name = "redis-${version}";

  src = fetchurl {
    url = "http://download.redis.io/releases/${name}.tar.gz";
    multihash = "QmWahw3oWVegYyg2KN6xtHBKxFQg94gNgJovZQRyrF1wEJ";
    hashOutput = false;
    sha256 = "1db67435a704f8d18aec9b9637b373c34aa233d65b6e174bdac4c1b161f38ca4";
  };

  buildInputs = [
    hiredis
    jemalloc'
    linenoise
    luajit
  ];

  NIX_CFLAGS_COMPILE = [
    "-I${hiredis}/include/hiredis"
    "-I${luajit}/include/lua"
  ];

  postPatch = ''
    rm -r deps

    grep -q 'DEPENDENCY_TARGETS' src/Makefile
    grep -q 'DEBUG=' src/Makefile
    sed \
      -e '/DEPENDENCY_TARGETS/d' \
      -e '/DEBUG=/d' \
      -e "s#../deps/jemalloc/lib/libjemalloc.a#-ljemalloc#g" \
      -e "s#../deps/hiredis/libhiredis.a#-lhiredis#g" \
      -e "s#../deps/linenoise/linenoise.o#${linenoise}/lib/liblinenoise.a#g" \
      -e "s#../deps/lua/src/liblua.a#-llua#g" \
      -i src/Makefile
  '' /* + Lua 5.3 compat ''
    grep -q 'lua_strlen' src/scripting.c
    sed -i 's,lua_strlen,lua_rawlen,g' src/scripting.c

    grep -q 'lua_open' src/scripting.c
    sed -i 's,lua_open,luaL_newstate,g' src/scripting.c

    grep -q 'luaL_checkint' src/scripting.c
    sed -i 's,luaL_checkint,(int)luaL_checkinteger,g' src/scripting.c
  '' */;

  preBuild = ''
    makeFlagsArray+=(
      "MALLOC=jemalloc"
      "PREFIX=$out"
      "V=1"
    )
  '';

  passthru = {
    srcVerification = fetchurl {
      failEarly = true;
      sha256Url = "https://raw.githubusercontent.com/antirez/redis-hashes/master/README";
      inherit (src) urls outputHash outputHashAlgo;
    };
  };

  meta = with stdenv.lib; {
    description = "An open source, advanced key-value store";
    homepage = http://redis.io;
    license = licenses.bsd3;
    maintainers = with maintainers; [
      wkennington
    ];
    platforms = with platforms;
      x86_64-linux;
  };
}
