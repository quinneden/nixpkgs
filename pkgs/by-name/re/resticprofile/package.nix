{
  lib,
  buildGo123Module,
  fetchFromGitHub,
  installShellFiles,
  restic,
  bash,
  testers,
  resticprofile,
}:

buildGo123Module rec {
  pname = "resticprofile";
  version = "0.29.1";

  src = fetchFromGitHub {
    owner = "creativeprojects";
    repo = "resticprofile";
    tag = "v${version}";
    hash = "sha256-6s58rI+YMu6sCV8UsG9GOdF46Br3cMWIUqciVd2d4dY=";
  };

  postPatch = ''
    substituteInPlace schedule_jobs.go \
        --replace-fail "os.Executable()" "\"$out/bin/resticprofile\", nil"

    substituteInPlace shell/command.go \
        --replace-fail '"bash"' '"${lib.getExe bash}"'

    substituteInPlace filesearch/filesearch.go \
        --replace-fail 'paths := getSearchBinaryLocations()' 'return "${lib.getExe restic}", nil; paths := getSearchBinaryLocations()'

  '';

  vendorHash = "sha256-N39zPGos5EYRXGylsHFSjJ4EcQ9jahBOGV8xn7fF7gc=";

  ldflags = [
    "-X main.version=${version}"
    "-X main.commit=${src.rev}"
    "-X main.date=unknown"
    "-X main.builtBy=nixpkgs"
  ];

  nativeBuildInputs = [ installShellFiles ];

  preCheck = ''
    rm battery_test.go # tries to get battery data
    rm update_test.go # tries to use network
    rm lock/lock_test.go # needs ping
    rm preventsleep/caffeinate_test.go # tries to communicate with dbus
    rm priority/ioprio_test.go # tries to set nice(2) IO priority
    rm restic/downloader_test.go # tries to use network
    rm schedule/schedule_test.go # tries to use systemctl
    rm config/path_test.go # expects normal environment
    rm util/tempdir_test.go # expects normal environment
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 $GOPATH/bin/resticprofile -t $out/bin

    installShellCompletion --cmd resticprofile \
        --bash <($out/bin/resticprofile generate --bash-completion) \
        --zsh <($out/bin/resticprofile generate --zsh-completion)

    runHook postInstall
  '';

  passthru = {
    tests.version = testers.testVersion {
      package = resticprofile;
      command = "resticprofile version";
    };
  };

  meta = {
    changelog = "https://github.com/creativeprojects/resticprofile/releases/tag/v${version}";
    description = "Configuration profiles manager for restic backup";
    homepage = "https://creativeprojects.github.io/resticprofile/";
    license = with lib.licenses; [
      gpl3Only
      lgpl3 # bash shell completion
    ];
    mainProgram = "resticprofile";
    maintainers = with lib.maintainers; [ tomasajt ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
