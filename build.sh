#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="${PULSEBAR_BUILD_DIR:-$project_dir/.build-local}"
app_path="${1:-$project_dir/dist/PulseBar.app}"
mkdir -p "$build_dir" "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/swift-cache"
swift build --package-path "$project_dir" --scratch-path "$build_dir" --cache-path "$build_dir/package-cache" --config-path "$build_dir/config" --security-path "$build_dir/security" -c release
bin_path="$(swift build --package-path "$project_dir" --scratch-path "$build_dir" --show-bin-path -c release)"
cp "$bin_path/PulseBar" "$app_path/Contents/MacOS/PulseBar"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PulseBar</string>
<key>CFBundleIdentifier</key><string>local.pulsebar.app</string>
<key>CFBundleName</key><string>PulseBar</string>
<key>CFBundleDisplayName</key><string>PulseBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>4.4</string>
<key>CFBundleVersion</key><string>16</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocationWhenInUseUsageDescription</key><string>macOS requires location access to display nearby Wi-Fi network names.</string>
<key>NSLocationUsageDescription</key><string>Display Wi-Fi network names when you request a scan.</string>
<key>NSAppleEventsUsageDescription</key><string>Read and control Music or Spotify when you use the Media panel.</string>
<key>NSHumanReadableCopyright</key><string>PulseBar contributors. Includes MIT-licensed code from Stats and palette values from Omarchy.</string>
</dict></plist>
PLIST
mkdir -p "$app_path/Contents/Resources/Fonts"
cp "$project_dir/Assets/Fonts/"* "$app_path/Contents/Resources/Fonts/"
if [[ ! -f "$build_dir/icon.png" ]]; then
    swift -module-cache-path "$build_dir/icon-cache" "$project_dir/make-icon.swift" "$build_dir/icon.png"
fi
iconset="$build_dir/AppIcon.iconset"
mkdir -p "$iconset"
for dimension in 16 32 128 256 512; do
    sips -z "$dimension" "$dimension" "$build_dir/icon.png" --out "$iconset/icon_${dimension}x${dimension}.png" >/dev/null
    double=$((dimension * 2))
    sips -z "$double" "$double" "$build_dir/icon.png" --out "$iconset/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
cp "$project_dir/THIRD-PARTY-NOTICES.md" "$project_dir/LICENSE" "$app_path/Contents/Resources/"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
printf 'Built %s\n' "$app_path"
