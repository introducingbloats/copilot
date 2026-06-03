{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
  patchelf,
  glibc,
  unzip,
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
      binaryName = "copilot-language-server";
      mainProgram = "copilot-language-server";
      description = "GitHub Copilot Language Server";
      homepage = "https://github.com/github/copilot-language-server-release";
      makeDownloadUrl = version: platform:
        "https://github.com/github/copilot-language-server-release/releases/download/${version}/copilot-language-server-${platform}-${version}.zip";
      archiveType = "zip";
      unpackCommand = "unzip -q $src";
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
in
stdenv.mkDerivation {
  pname = cfg.pname;
  inherit version;
  inherit (defaultArgs) src;

  nativeBuildInputs = [
    installShellFiles
    patchelf
  ] ++ lib.optionals (cfg.archiveType == "zip") [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    ${cfg.unpackCommand}
    runHook postUnpack
  '';

  sourceRoot = ".";

  dontBuild = true;
  dontConfigure = true;
  noDumpEnvVars = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib
    if [ ! -f ${cfg.binaryName} ]; then
      echo "Error: expected binary '${cfg.binaryName}' was not found in source tree"
      exit 1
    fi

    # Patch the generic Linux release to use Nix's dynamic linker and runtime libraries.
    patchelf \
      --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" \
      --set-rpath "${runtimeLibraryPath}" \
      ${cfg.binaryName}

    install -m 755 ${cfg.binaryName} "$out/lib/${cfg.binaryName}"

    # Nix already manages updates, so prefer the packaged payload over mutable
    # auto-updated copies under ~/.copilot/pkg/universal.
    {
      printf '%s\n' "#!${stdenv.shell}"
      ${
        lib.optionalString (variant == "cli") ''
          printf '%s\n' 'export COPILOT_AUTO_UPDATE="''${COPILOT_AUTO_UPDATE:-false}"'
        ''
      }
      printf '%s\n' "exec \"$out/lib/${cfg.binaryName}\" \"\$@\""
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
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = lib.platforms.linux;
    mainProgram = cfg.mainProgram;
  };
}
