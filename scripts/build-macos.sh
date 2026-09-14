#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Build this app on your Mac. It requires macOS 13+ and Xcode Command Line Tools." >&2
    exit 1
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/KB96 Control.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/KB96Control" "$app_dir/Contents/MacOS/KB96Control"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign "${KB96_SIGNING_IDENTITY:--}" "$app_dir"
echo "Built: $app_dir"
echo "Move the app to /Applications before granting permissions, then open it."
