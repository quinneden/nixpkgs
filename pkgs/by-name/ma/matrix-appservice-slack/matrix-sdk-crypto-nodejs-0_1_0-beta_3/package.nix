{
  lib,
  stdenv,
  fetchFromGitHub,
  cargo,
  rustPlatform,
  rustc,
  napi-rs-cli,
  nodejs,
  libiconv,
}:

stdenv.mkDerivation rec {
  pname = "matrix-sdk-crypto-nodejs";
  version = "0.1.0-beta.3";

  src = fetchFromGitHub {
    owner = "matrix-org";
    repo = "matrix-rust-sdk";
    tag = "${pname}-v${version}";
    hash = "sha256-0p+1cMn9PU+Jk2JW7G+sdzxhMaI3gEAk5w2nm05oBSU=";
  };

  patches = [
    # This is needed because two versions of indexed_db_futures are present (which will fail to vendor, see https://github.com/rust-lang/cargo/issues/10310).
    # (matrix-sdk-crypto-nodejs doesn't use this dependency, we only need to remove it to vendor the dependencies successfully.)
    ./remove-duplicate-dependency.patch
  ];

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit
      pname
      version
      src
      patches
      ;
    hash = "sha256-utpqRh5FIVgEX0dbYIS3GL/np6g6Itz8t27ov5CBrG8=";
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    napi-rs-cli
    nodejs
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  buildPhase = ''
    runHook preBuild

    cd bindings/${pname}
    npm run release-build --offline

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    local -r outPath="$out/lib/node_modules/@matrix-org/${pname}"
    mkdir -p "$outPath"
    cp package.json index.js index.d.ts matrix-sdk-crypto.*.node "$outPath"

    runHook postInstall
  '';

  meta = {
    description = "No-network-IO implementation of a state machine that handles E2EE for Matrix clients";
    homepage = "https://github.com/matrix-org/matrix-rust-sdk/tree/${src.rev}/bindings/matrix-sdk-crypto-nodejs";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [
      winter
      dandellion
    ];
    inherit (nodejs.meta) platforms;
  };
}
