#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
dist_dir="$project_dir/dist"

copy_matching() {
  local source_dir="$1"
  local target_dir="$2"
  shift 2
  /bin/mkdir -p "$target_dir"
  local pattern file
  for pattern in "$@"; do
    for file in "$source_dir"/$~pattern(N); do
      /bin/cp -f "$file" "$target_dir/"
    done
  done
}

copy_matching "$project_dir/Linux/dist" "$dist_dir/linux/x64" \
  '*linux-x86_64.AppImage' '*linux-x86_64.AppImage.sha256' \
  '*linux-amd64.deb' '*linux-amd64.deb.sha256'

copy_matching "$project_dir/Linux/dist" "$dist_dir/linux/arm64" \
  '*linux-arm64.AppImage' '*linux-arm64.AppImage.sha256' \
  '*linux-arm64.deb' '*linux-arm64.deb.sha256'

copy_matching "$project_dir/Windows/dist" "$dist_dir/windows/x64" \
  '*windows-x64-setup.exe' '*windows-x64-setup.exe.sha256' '*windows-x64-setup.exe.blockmap' \
  '*windows-x64-portable.exe' '*windows-x64-portable.exe.sha256'

copy_matching "$project_dir/Windows/dist" "$dist_dir/windows/arm64" \
  '*windows-arm64-setup.exe' '*windows-arm64-setup.exe.sha256' '*windows-arm64-setup.exe.blockmap' \
  '*windows-arm64-portable.exe' '*windows-arm64-portable.exe.sha256'

print "Organized release folders under $dist_dir"
