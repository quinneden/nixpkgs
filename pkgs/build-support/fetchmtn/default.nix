# You can specify some extra mirrors and a cache DB via options
{
  lib,
  stdenvNoCC,
  monotone,
  defaultDBMirrors ? [ ],
  cacheDB ? "./mtn-checkout.db",
}:

lib.fetchers.withNormalizedHash { } (
  # dbs is a list of strings, each is an url for sync
  # selector is mtn selector, like h:org.example.branch
  {
    name ? "mtn-checkout",
    dbs ? [ ],
    outputHash,
    outputHashAlgo,
    selector ? "h:" + branch,
    branch,
  }:

  stdenvNoCC.mkDerivation {
    builder = ./builder.sh;
    nativeBuildInputs = [ monotone ];

    inherit outputHash outputHashAlgo;
    outputHashMode = "recursive";

    dbs = defaultDBMirrors ++ dbs;
    inherit
      branch
      cacheDB
      name
      selector
      ;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  }
)
