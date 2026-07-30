#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
sing_box_version="1.13.14"
arm64_sha256="73e8967b0fc08e17bce4263ca56ebc394822401a16497a1c4e02316c888202ab"
amd64_sha256="5245d645e847f90bb708da74bc020ae078c28489690756419685c04f56b4e3bb"
release_dir="${RELEASE_DIR:-$project_dir/dist/macos}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/realitylink-release.XXXXXX")"

cleanup() {
  /bin/rm -rf "$temporary_dir"
  /bin/rm -rf \
    "$release_dir/arm64/RealityLink.app" \
    "$release_dir/x64/RealityLink.app" \
    "$release_dir/universal/RealityLink.app"
}
trap cleanup EXIT

download_core() {
  local upstream_arch="$1"
  local expected_hash="$2"
  local archive="sing-box-${sing_box_version}-darwin-${upstream_arch}.tar.gz"
  local url="https://github.com/SagerNet/sing-box/releases/download/v${sing_box_version}/${archive}"

  /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 \
    --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 20 --max-time 300 \
    "$url" --output "$temporary_dir/$archive"
  actual_hash="$(/usr/bin/shasum -a 256 "$temporary_dir/$archive" | /usr/bin/awk '{print $1}')"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    print -u2 "error: checksum mismatch for $archive"
    exit 1
  fi
  /usr/bin/tar -xzf "$temporary_dir/$archive" -C "$temporary_dir"
  print "$temporary_dir/sing-box-${sing_box_version}-darwin-${upstream_arch}/sing-box"
}

arm64_core="$(download_core arm64 "$arm64_sha256")"
amd64_core="$(download_core amd64 "$amd64_sha256")"
universal_core="$temporary_dir/sing-box-universal"
/usr/bin/lipo -create "$arm64_core" "$amd64_core" -output "$universal_core"
/bin/chmod 0755 "$universal_core"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/macOS/Resources/Info.plist")"
if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" != "v$version" ]]; then
  print -u2 "error: tag $GITHUB_REF_NAME does not match app version v$version"
  exit 1
fi
/bin/mkdir -p "$release_dir"

build_variant() {
  local label="$1"
  local build_archs="$2"
  local core_binary="$3"
  local variant_dir="$release_dir/$label"
  local app_path="$variant_dir/RealityLink.app"
  local archive_path="$variant_dir/RealityLink-${version}-macOS-${label}.zip"

  /bin/mkdir -p "$variant_dir"
  APP_BUNDLE_PATH="$app_path" \
  SING_BOX_BINARY="$core_binary" \
  BUILD_ARCHS="$build_archs" \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
    "$project_dir/Scripts/build-app.sh"

  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
  (
    cd "$variant_dir"
    /usr/bin/shasum -a 256 "${archive_path:t}" > "${archive_path:t}.sha256"
  )
  /bin/rm -rf "$app_path"
  print "Release archive: $archive_path"
}

build_variant arm64 arm64 "$arm64_core"
build_variant x64 x86_64 "$amd64_core"
build_variant universal "arm64 x86_64" "$universal_core"
