#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
macos_dir="$project_dir/macOS"
configuration="${CONFIGURATION:-release}"
app_dir="${APP_BUNDLE_PATH:-$project_dir/dist/RealityLink.app}"
contents_dir="$app_dir/Contents"
code_sign_identity="${CODE_SIGN_IDENTITY:--}"
sing_box_binary="${SING_BOX_BINARY:-}"
arch_flags=()

if [[ -n "${BUILD_ARCHS:-}" ]]; then
  for build_arch in ${(z)BUILD_ARCHS}; do
    arch_flags+=(--arch "$build_arch")
  done
fi

cd "$macos_dir"
swift build -c "$configuration" "${arch_flags[@]}"

binary_dir="$(swift build -c "$configuration" "${arch_flags[@]}" --show-bin-path)"
rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/RealityLink" "$contents_dir/MacOS/RealityLink"
cp "$macos_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$macos_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$project_dir/LICENSE" "$contents_dir/Resources/LICENSE"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/THIRD_PARTY_NOTICES.md"

if [[ -n "$sing_box_binary" && -x "$sing_box_binary" ]]; then
  cp "$sing_box_binary" "$contents_dir/Resources/sing-box"
elif [[ -x /opt/homebrew/bin/sing-box ]]; then
  cp /opt/homebrew/bin/sing-box "$contents_dir/Resources/sing-box"
elif [[ -x /usr/local/bin/sing-box ]]; then
  cp /usr/local/bin/sing-box "$contents_dir/Resources/sing-box"
fi

if [[ ! -x "$contents_dir/Resources/sing-box" ]]; then
  print -u2 "error: sing-box not found; set SING_BOX_BINARY to an executable"
  exit 1
fi

# Do not leak local Finder provenance or quarantine metadata into release archives.
/bin/chmod -R u+w "$app_dir"
/usr/bin/xattr -cr "$app_dir"
codesign --force --options runtime --deep --sign "$code_sign_identity" "$app_dir"
print "Built $app_dir"
