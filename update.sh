#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq coreutils gnused
# Bump sources.json to the newest claude-desktop in Anthropic's apt repo.
# The repo publishes amd64 + arm64 only; both are updated together.
set -euo pipefail

repo="https://downloads.claude.ai/claude-desktop/apt/stable"
cd "$(dirname "$(readlink -f "$0")")"

# Print "<version> <filename> <sha256>" of the newest package for an arch.
latest() {
  curl -fsSL "$repo/dists/stable/main/binary-$1/Packages" | awk '
    /^Version: /  { v = $2 }
    /^Filename: / { f = $2 }
    /^SHA256: /   { s = $2 }
    /^$/          { if (v) print v, f, s; v = f = s = "" }
    END           { if (v) print v, f, s }
  ' | sort -V -k1,1 | tail -n 1
}

read -r v_amd64 f_amd64 s_amd64 < <(latest amd64)
read -r v_arm64 f_arm64 s_arm64 < <(latest arm64)

if [ "$v_amd64" != "$v_arm64" ]; then
  echo "warning: amd64 ($v_amd64) and arm64 ($v_arm64) versions differ" >&2
fi

jq -n \
  --arg version "$v_amd64" \
  --arg amd64_url "$repo/$f_amd64" --arg amd64_sha "$s_amd64" \
  --arg arm64_url "$repo/$f_arm64" --arg arm64_sha "$s_arm64" \
  '{
    version: $version,
    "x86_64-linux":  { url: $amd64_url, sha256: $amd64_sha },
    "aarch64-linux": { url: $arm64_url, sha256: $arm64_sha }
  }' > sources.json

echo "claude-desktop -> $v_amd64"
