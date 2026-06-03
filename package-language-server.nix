{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
  unzip,
  nodejs_22,
}:
let
  currentVersion = lib.importJSON ./version.json;
  version = currentVersion.language-server-version;
  selectedArgs = {
    src = fetchurl {
      url = "https://github.com/github/copilot-language-server-release/releases/download/${version}/copilot-language-server-js-${version}.zip";
      hash = currentVersion."language-server-hash-linux";
    };
  };
in
stdenv.mkDerivation {
  pname = "copilot-language-server";
  inherit version;
  inherit (selectedArgs) src;

  nativeBuildInputs = [
    installShellFiles
    unzip
  ];

  unpackPhase = ''
    runHook preUnpack
    unzip -q $src
    runHook postUnpack
  '';

  sourceRoot = ".";
  dontBuild = true;
  dontConfigure = true;
  dontPatchELF = true;
  noDumpEnvVars = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib
    if [ ! -f language-server.js ]; then
      echo "Error: expected payload 'language-server.js' was not found in source tree"
      exit 1
    fi

    mkdir -p "$out/lib/copilot-language-server"
    cp -r . "$out/lib/copilot-language-server"

    {
      printf '%s\n' "#!${stdenv.shell}"
      printf '%s\n' "exec ${nodejs_22}/bin/node \"$out/lib/copilot-language-server/language-server.js\" \"\$@\""
    } > $out/bin/copilot-language-server
    chmod 755 "$out/bin/copilot-language-server"

    runHook postInstall
  '';

  meta = {
    description = "GitHub Copilot Language Server";
    homepage = "https://github.com/github/copilot-language-server-release";
    license = lib.licenses.unfreeRedistributable;
    platforms = lib.platforms.linux;
    mainProgram = "copilot-language-server";
  };
}
