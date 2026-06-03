{
  lib,
  writeShellApplication,
  jq,
  coreutils,
  curl,
  nix,
}:
writeShellApplication {
  name = "github-copilot-cli-bin-update";
  runtimeInputs = [
    jq
    coreutils
    curl
    nix
  ];
  text = ''
    set -euo pipefail

    fetch_release() {
      local repo=$1
      curl -sL "https://api.github.com/repos/$repo/releases/latest"
    }

    hash_url() {
      local url=$1
      local tmp
      tmp="$(mktemp)"
      trap 'rm -f "$tmp"' RETURN
      curl -fLs "$url" -o "$tmp"
      nix hash file --type sha256 "$tmp"
    }

    update_cli() {
      echo "Fetching latest release from github.com/github/copilot-cli"
      RELEASE=$(fetch_release "github/copilot-cli")
      VERSION=$(echo "$RELEASE" | jq -r '.tag_name' | sed 's/^v//')
      echo "Latest version: $VERSION"

      CURRENT_VERSION=$(jq -r '.version' version.json)
      echo "Flake version: $CURRENT_VERSION"

      echo "Fetching x86_64-linux tarball and calculating hash"
      X64_URL="https://github.com/github/copilot-cli/releases/download/v$VERSION/copilot-linux-x64.tar.gz"
      X64_HASH=$(hash_url "$X64_URL")
      echo "x86_64-linux hash: $X64_HASH"

      echo "Fetching aarch64-linux tarball and calculating hash"
      ARM64_URL="https://github.com/github/copilot-cli/releases/download/v$VERSION/copilot-linux-arm64.tar.gz"
      ARM64_HASH=$(hash_url "$ARM64_URL")
      echo "aarch64-linux hash: $ARM64_HASH"

      CURRENT_X64_HASH=$(jq -r '."hash-linux-x64"' version.json)
      CURRENT_ARM64_HASH=$(jq -r '."hash-linux-arm64"' version.json)

      if [ "$VERSION" = "$CURRENT_VERSION" ] && [ "$X64_HASH" = "$CURRENT_X64_HASH" ] && [ "$ARM64_HASH" = "$CURRENT_ARM64_HASH" ]; then
        echo "Version and hashes match current version.json, skipping update"
        return
      fi

      jq --arg version "$VERSION" \
         --arg hash_linux_x64 "$X64_HASH" \
         --arg hash_linux_arm64 "$ARM64_HASH" \
         '.version = $version |
          ."hash-linux-x64" = $hash_linux_x64 |
          ."hash-linux-arm64" = $hash_linux_arm64' \
         version.json > version.json.tmp
      mv version.json.tmp version.json
      echo "done updating version.json with new copilot-cli version and hashes"
    }

    update_language_server() {
      echo "Fetching latest release from github.com/github/copilot-language-server-release"
      RELEASE=$(fetch_release "github/copilot-language-server-release")
      VERSION=$(echo "$RELEASE" | jq -r '.tag_name' | sed 's/^v//')
      echo "Latest version: $VERSION"

      CURRENT_VERSION=$(jq -r '."language-server-version"' version.json)
      echo "Flake version: $CURRENT_VERSION"

      TARBALL="https://github.com/github/copilot-language-server-release/releases/download/$VERSION/copilot-language-server-js-$VERSION.zip"

      echo "Fetching js zip and calculating hash"
      HASH_LINUX=$(hash_url "$TARBALL")
      echo "linux hash: $HASH_LINUX"

      CURRENT_HASH=$(jq -r '."language-server-hash-linux"' version.json)

      if [ "$VERSION" = "$CURRENT_VERSION" ] && [ "$HASH_LINUX" = "$CURRENT_HASH" ]; then
        echo "copilot-language-server version and hashes match version.json, skipping update"
        return
      fi

      jq --arg version "$VERSION" \
         --arg hash_linux "$HASH_LINUX" \
         '."language-server-version" = $version |
          ."language-server-hash-linux" = $hash_linux' \
         version.json > version.json.tmp
      mv version.json.tmp version.json
      echo "done updating version.json with new copilot-language-server version and hashes"
    }

    if [ "$#" -eq 0 ]; then
      update_cli
      update_language_server
    else
      for arg in "$@"; do
        case "$arg" in
          cli|github-copilot-cli-bin) update_cli ;;
          language-server|copilot-language-server) update_language_server ;;
          *) echo "Unknown component: $arg"; exit 1 ;;
        esac
      done
    fi

    echo "Successfully updated version.json"
  '';
}
