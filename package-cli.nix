{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
  patchelf,
  glibc,
}:
let
  pname = "github-copilot-cli-bin";
  currentVersion = lib.importJSON ./version.json;
  version = currentVersion.version;
  runtimeLibraryPath = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    glibc
  ];
  selectedArgs =
    if stdenv.hostPlatform.system == "x86_64-linux" then
      {
        src = fetchurl {
          url = "https://github.com/github/copilot-cli/releases/download/v${version}/copilot-linux-x64.tar.gz";
          hash = currentVersion."hash-linux-x64";
        };
      }
    else if stdenv.hostPlatform.system == "aarch64-linux" then
      {
        src = fetchurl {
          url = "https://github.com/github/copilot-cli/releases/download/v${version}/copilot-linux-arm64.tar.gz";
          hash = currentVersion."hash-linux-arm64";
        };
      }
    else
      throw "${pname}: Unsupported platform: ${stdenv.hostPlatform.system}";
in
stdenv.mkDerivation {
  pname = pname;
  inherit version;
  inherit (selectedArgs) src;

  nativeBuildInputs = [
    installShellFiles
    patchelf
  ];

  unpackPhase = ''
    runHook preUnpack
    tar -xzf $src
    runHook postUnpack
  '';

  dontBuild = true;
  dontConfigure = true;
  dontPatchELF = false;
  noDumpEnvVars = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib
    if [ ! -f copilot ]; then
      echo "Error: expected payload 'copilot' was not found in source tree"
      exit 1
    fi

    patchelf \
      --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" \
      --set-rpath "${runtimeLibraryPath}" \
      copilot
    install -m 755 copilot "$out/lib/copilot"

    {
      printf '%s\n' "#!${stdenv.shell}"
      printf '%s\n' 'export COPILOT_AUTO_UPDATE="''${COPILOT_AUTO_UPDATE:-false}"'
      printf '%s\n' "exec \"$out/lib/copilot\" \"\$@\""
    } > $out/bin/copilot
    chmod 755 "$out/bin/copilot"

    if $out/bin/copilot completion bash > copilot.bash 2>/dev/null; then
      installShellCompletion --bash --name copilot.bash copilot.bash
    fi
    if $out/bin/copilot completion zsh > _copilot 2>/dev/null; then
      installShellCompletion --zsh --name _copilot _copilot
    fi
    if $out/bin/copilot completion fish > copilot.fish 2>/dev/null; then
      installShellCompletion --fish --name copilot.fish copilot.fish
    fi

    runHook postInstall
  '';

  meta = {
    description = "GitHub Copilot CLI";
    homepage = "https://github.com/github/copilot-cli";
    license = lib.licenses.unfreeRedistributable;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = lib.platforms.linux;
    mainProgram = "copilot";
  };
}
