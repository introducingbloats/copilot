{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
  patchelf,
  glibc,
  unzip,
  nodejs_22,
  variant ? "cli",
}:
let
  currentVersion = lib.importJSON ./version.json;
  variants = {
    cli = {
      pname = "github-copilot-cli-bin";
      versionKey = "version";
      hashPrefix = "";
      binaryName = "copilot";
      mainProgram = "copilot";
      description = "GitHub Copilot CLI";
      homepage = "https://github.com/github/copilot-cli";
      makeDownloadUrl = version: platform:
        "https://github.com/github/copilot-cli/releases/download/v${version}/copilot-${platform}.tar.gz";
      archiveType = "tar.gz";
      unpackCommand = "tar -xzf $src";
      completions = true;
    };
    "language-server" = {
      pname = "copilot-language-server";
      versionKey = "language-server-version";
      hashPrefix = "language-server-";
      binaryName = "dist/language-server.js";
      mainProgram = "copilot-language-server";
      description = "GitHub Copilot Language Server";
      homepage = "https://github.com/github/copilot-language-server-release";
      makeDownloadUrl = version: _platform:
        "https://registry.npmjs.org/@github%2Fcopilot-language-server/-/copilot-language-server-${version}.tgz";
      archiveType = "tgz";
      unpackCommand = "tar -xzf $src";
      sourceRoot = "package";
      completions = false;
    };
  };
  cfg = variants.${variant} or (throw "Unsupported github-copilot variant: ${variant}");
  version = currentVersion.${cfg.versionKey};
  defaultArgs =
    {
      "x86_64-linux" = {
        src = fetchurl {
          url = cfg.makeDownloadUrl version "linux-x64";
          hash = currentVersion."${cfg.hashPrefix}hash-linux-x64";
        };
      };
      "aarch64-linux" = {
        src = fetchurl {
          url = cfg.makeDownloadUrl version "linux-arm64";
          hash = currentVersion."${cfg.hashPrefix}hash-linux-arm64";
        };
      };
    }
    .${stdenv.hostPlatform.system}
      or (throw "${cfg.pname}: Unsupported platform: ${stdenv.hostPlatform.system}");
  runtimeLibraryPath = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    glibc
  ];
  isCli = variant == "cli";
in
stdenv.mkDerivation {
  pname = cfg.pname;
  inherit version;
  inherit (defaultArgs) src;

  nativeBuildInputs =
    [ installShellFiles ]
    ++ lib.optionals isCli [ patchelf ]
    ++ lib.optionals (cfg.archiveType == "zip") [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    ${cfg.unpackCommand}
    runHook postUnpack
  '';

  sourceRoot = cfg.sourceRoot or ".";

  dontBuild = true;
  dontConfigure = true;
  dontPatchELF = !isCli;
  noDumpEnvVars = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib
    if [ ! -f ${cfg.binaryName} ]; then
      echo "Error: expected payload '${cfg.binaryName}' was not found in source tree"
      exit 1
    fi

    ${lib.optionalString isCli ''
      # Patch the generic Linux release to use Nix's dynamic linker and runtime libraries.
      patchelf \
        --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" \
        --set-rpath "${runtimeLibraryPath}" \
        ${cfg.binaryName}

      install -m 755 ${cfg.binaryName} "$out/lib/${cfg.mainProgram}"
    ''}

    ${lib.optionalString (!isCli) ''
      mkdir -p "$out/lib/${cfg.mainProgram}"
      cp -r . "$out/lib/${cfg.mainProgram}"
    ''}

    {
      printf '%s\n' "#!${stdenv.shell}"
      ${lib.optionalString isCli ''
        printf '%s\n' 'export COPILOT_AUTO_UPDATE="''${COPILOT_AUTO_UPDATE:-false}"'
        printf '%s\n' "exec \"$out/lib/${cfg.mainProgram}\" \"\$@\""
      ''}
      ${lib.optionalString (!isCli) ''
        printf '%s\n' "exec ${nodejs_22}/bin/node \"$out/lib/${cfg.mainProgram}/${cfg.binaryName}\" \"\$@\""
      ''}
    } > $out/bin/${cfg.mainProgram}
    chmod 755 "$out/bin/${cfg.mainProgram}"

    ${
      lib.optionalString cfg.completions ''
        # Generate and install shell completions
        if $out/bin/${cfg.mainProgram} completion bash > ${cfg.mainProgram}.bash 2>/dev/null; then
          installShellCompletion --bash --name ${cfg.mainProgram}.bash ${cfg.mainProgram}.bash
        fi
        if $out/bin/${cfg.mainProgram} completion zsh > _${cfg.mainProgram} 2>/dev/null; then
          installShellCompletion --zsh --name _${cfg.mainProgram} _${cfg.mainProgram}
        fi
        if $out/bin/${cfg.mainProgram} completion fish > ${cfg.mainProgram}.fish 2>/dev/null; then
          installShellCompletion --fish --name ${cfg.mainProgram}.fish ${cfg.mainProgram}.fish
        fi
      ''
    }

    runHook postInstall
  '';

  meta = {
    description = cfg.description;
    homepage = cfg.homepage;
    license = lib.licenses.unfreeRedistributable;
    sourceProvenance = lib.optionals isCli (with lib.sourceTypes; [ binaryNativeCode ]);
    platforms = lib.platforms.linux;
    mainProgram = cfg.mainProgram;
  };
}
