#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="1.13.14"
machine="${TARGET_ARCH:-$(uname -m)}"

case "$machine" in
  x86_64|amd64)
    upstream_arch="amd64"
    expected="f48703461a15476951ac4967cdad339d986f4b8096b4eb3ff0829a500502d697"
    ;;
  arm64|aarch64)
    upstream_arch="arm64"
    expected="4742df6a4314e8ecc41736849fca6d73b8f9e91b6e8b06ee794ff17ba180579e"
    ;;
  *)
    echo "Unsupported architecture: $machine" >&2
    exit 1
    ;;
esac

archive="sing-box-${version}-linux-${upstream_arch}.tar.gz"
url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${archive}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/realitylink-linux.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

if ! curl --fail --location --proto '=https' --tlsv1.2 \
  --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 20 --max-time 300 \
  "$url" -o "$temporary_dir/$archive"; then
  command -v wget >/dev/null 2>&1 || { echo "Download failed and wget is unavailable" >&2; exit 1; }
  wget --https-only --timeout=300 --tries=5 "$url" -O "$temporary_dir/$archive"
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$temporary_dir/$archive" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$temporary_dir/$archive" | awk '{print $1}')"
fi
if [[ "$actual" != "$expected" ]]; then
  echo "Checksum mismatch for $archive" >&2
  exit 1
fi

tar -xzf "$temporary_dir/$archive" -C "$temporary_dir"
mkdir -p "$project_dir/vendor"
install -m 0755 "$temporary_dir/sing-box-${version}-linux-${upstream_arch}/sing-box" "$project_dir/vendor/sing-box"
echo "Installed verified sing-box $version ($upstream_arch)"
