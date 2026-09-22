{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  cargo,
  pkg-config,
  glibc,
  openssl,
  libcap_ng,
  libepoxy,
  libdrm,
  pipewire,
  virglrenderer,
  libkrunfw,
  nix-update-script,
  rustc,
  fetchurl,
  fixDarwinDylibNames,
  libkrun,
  lld,
  meson,
  moltenvk,
  ninja,
  pkgsCross,
  python3,
  vulkan-headers,
  withBlk ? false,
  withNet ? false,
  # GPU enabled by default for efi variant
  withGpu ? variant == "efi",
  withSound ? false,
  withInput ? false,
  withTimesync ? false,
  variant ? null,
}:

assert lib.elem variant [
  null
  "efi"
  "sev"
  "tdx"
];

let
  inherit (stdenv.hostPlatform) isDarwin isLinux;

  version = "1.19.4";

  src = fetchFromGitHub {
    owner = "libkrun";
    repo = "libkrun";
    tag = "v${version}";
    hash = "sha256-X/VGKOfbLN/3rj1Af7HEprfJB99Mh3UwfikXtS1dkXI=";
  };

  libkrunfw' = (libkrunfw.override { inherit variant; });

  virglrenderer' =
    if isDarwin then
      stdenv.mkDerivation (finalAttrs: {
        pname = "virglrenderer";
        version = "0.10.4d-krunkit";

        src = fetchurl {
          url = "https://gitlab.freedesktop.org/slp/virglrenderer/-/archive/${finalAttrs.version}/virglrenderer-${finalAttrs.version}.tar.bz2";
          hash = "sha256-M/buj97QUeY6CYeW0VICD5F6FBPi9ATPGHpNA48xL3o=";
        };

        separateDebugInfo = true;

        buildInputs = [
          libepoxy
          moltenvk
          vulkan-headers
        ];

        nativeBuildInputs = [
          meson
          ninja
          pkg-config
          (python3.withPackages (ps: [ ps.pyyaml ]))
        ];

        mesonFlags = [
          (lib.mesonBool "render-server" false)
          (lib.mesonBool "venus" true)
          (lib.mesonEnable "drm" false)
        ];

        meta = {
          description = "Virtual 3D GPU library that allows a qemu guest to use the host GPU for accelerated 3D rendering";
          mainProgram = "virgl_test_server";
          homepage = "https://gitlab.freedesktop.org/slp/virglrenderer";
          license = lib.licenses.mit;
          platforms = lib.platforms.unix;
          maintainers = [ lib.maintainers.quinneden ];
        };
      })
    else
      virglrenderer;

  initBinaryCross = pkgsCross.aarch64-multiplatform.pkgsStatic.stdenv.mkDerivation {
    pname = "libkrun-init";
    inherit version src;

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      cd src/init_blob/init
      $CC -O2 -static -Wall -o init init.c dhcp.c
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -D init $out/init
      runHook postInstall
    '';
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "libkrun" + lib.optionalString (variant != null) "-${variant}";
  inherit version src;

  outputs = [
    "out"
    "dev"
  ];

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) src;
    hash = "sha256-ZNSpsxCzCUKkjsDt7Sd5HcfqiQ13kaZSo7w/Vy6HXtY=";
  };

  # Conditional attributes in `env` have to be set with `optionalAttrs` instead of `optionalString`
  # because `KRUN_INIT_BINARY_PATH` has to either point to a path or be unset, not set to an empty
  # string as it would be with `KRUN_INIT_BINARY_PATH = lib.optionalString isDarwin "..."` when
  # building on Linux.
  env = {
    OPENSSL_NO_VENDOR = true;
  }
  // lib.optionalAttrs isDarwin { KRUN_INIT_BINARY_PATH = "${initBinaryCross}/init"; }
  // lib.optionalAttrs isLinux {
    # Make sure libkrunfw can be found by dlopen()
    RUSTFLAGS = toString (
      map (flag: "-C link-arg=" + flag) [
        "-Wl,--push-state,--no-as-needed"
        ("-lkrunfw" + lib.optionalString (variant != null) "-${variant}")
        "-Wl,--pop-state"
      ]
    );
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    rustPlatform.bindgenHook
    cargo
    pkg-config
    rustc
  ]
  ++ lib.optionals isDarwin [
    fixDarwinDylibNames
    lld
  ];

  buildInputs =
    lib.optionals isLinux (
      [
        libcap_ng
        glibc
        glibc.static
      ]
      ++ lib.optional (variant == "sev" || variant == "tdx") openssl
      ++ lib.optional withGpu libdrm
      ++ lib.optional withSound pipewire
    )
    ++ lib.optional (variant != "efi") libkrunfw'
    ++ lib.optionals withGpu [
      libepoxy
      virglrenderer'
    ];

  makeFlags = [
    "PREFIX=${placeholder "out"}"
  ]
  ++ lib.optional withBlk "BLK=1"
  ++ lib.optional withNet "NET=1"
  ++ lib.optional withGpu "GPU=1"
  ++ lib.optional withSound "SND=1"
  ++ lib.optional withInput "INPUT=1"
  ++ lib.optional withTimesync "TIMESYNC=1"
  ++ lib.optional (variant == "sev") "SEV=1"
  ++ lib.optional (variant == "tdx") "TDX=1"
  ++ lib.optional (variant == "efi") "EFI=1";

  postPatch = lib.optionalString isDarwin ''
    substituteInPlace Makefile \
      --replace-fail '$(LIBRARY_RELEASE_$(OS)): $(SYSROOT_TARGET) $(INIT_BINARY_BSD)' \
                     '$(LIBRARY_RELEASE_$(OS)):' \
      --replace-fail 'mv target/release/libkrun.dylib target/release/$(KRUN_BASE_$(OS))' \
                     'mv target/release/libkrun.dylib target/release/$(KRUN_BASE_$(OS)) || true'
  '';

  postInstall =
    lib.optionalString isLinux ''
      mkdir -p $dev/lib/pkgconfig
      mv $out/lib64/pkgconfig $dev/lib/
      mv $out/include $dev/
    ''
    + lib.optionalString (variant == "efi") ''
      ln -s libkrun-efi.dylib $out/lib/libkrun.dylib
    '';

  passthru = {
    tests =
      let
        mkTest =
          f: v:
          libkrun.override {
            inherit variant;
            ${f} = v;
          };

        featuresToTest = [
          "withInput"
          "withTimesync"
        ]
        ++ lib.optional isLinux "withSound"
        ++ lib.optionals (variant != "efi") [
          "withBlk"
          "withGpu"
          "withNet"
        ];
      in
      (lib.genAttrs featuresToTest (f: mkTest f true))
      // lib.optionalAttrs (variant == "efi") { withoutGpu = mkTest "withGpu" false; };

    updateScript = nix-update-script { attrPath = "libkrun"; };
  };

  meta = {
    description = "Dynamic library providing Virtualization-based process isolation capabilities";
    homepage = "https://github.com/libkrun/libkrun";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [
      nickcao
      RossComputerGuy
      nrabulinski
      quinneden
    ];
    platforms = if variant == "efi" then [ "aarch64-darwin" ] else libkrunfw'.meta.platforms;
  };
})
