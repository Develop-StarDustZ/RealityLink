#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")/../dist"

for artifact in RealityLink-*.AppImage RealityLink-*.deb; do
  [[ -f "$artifact" ]] || continue
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$artifact" >"$artifact.sha256"
  else
    shasum -a 256 "$artifact" >"$artifact.sha256"
  fi
done
