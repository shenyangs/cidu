#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/词渡.app"
version="$(cat VERSION)"
build_number="$(cat BUILD_NUMBER)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build_number" =~ ^[0-9]+$ ]] || { echo "Invalid release version" >&2; exit 1; }
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
source scripts/storage.sh
swiftc -O -parse-as-library Sources/Core.swift Sources/Formats.swift Sources/Compatibility.swift Sources/MacFormats.swift Sources/WeType.swift Sources/Migration.swift Sources/BaiduAutomation.swift Sources/PermissionGuide.swift Sources/Preflight.swift Sources/LiveMigration.swift Sources/AgentGuide.swift Sources/MigrationView.swift Sources/App.swift "${storage_flags[@]}" -o "$app/Contents/MacOS/Cidu" -framework SwiftUI -framework AppKit -framework Carbon -target arm64-apple-macosx13.0
swiftc -O -parse-as-library -D CIDU_CLI Sources/Core.swift Sources/Formats.swift Sources/Compatibility.swift Sources/MacFormats.swift Sources/WeType.swift Sources/Migration.swift Sources/BaiduAutomation.swift Sources/PermissionGuide.swift Sources/Preflight.swift Sources/LiveMigration.swift Sources/CLI.swift "${storage_flags[@]}" -o "$app/Contents/MacOS/cidu-cli" -framework SwiftUI -framework AppKit -framework Carbon -target arm64-apple-macosx13.0
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Cidu</string>
<key>CFBundleIdentifier</key><string>org.cidu.preview</string>
<key>CFBundleName</key><string>词渡</string>
<key>CFBundleDisplayName</key><string>词渡</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$app/Contents/Resources/Licenses"
cp vendor/leveldb-1.23/LICENSE "$app/Contents/Resources/Licenses/LevelDB.txt"
cp vendor/snappy-1.2.1/COPYING "$app/Contents/Resources/Licenses/Snappy.txt"
cp LICENSE LICENSE.ime-lexicon THIRD_PARTY.md "$app/Contents/Resources/Licenses/"
clang++ -std=c++17 -fobjc-arc -target arm64-apple-macosx13.0 Sources/Native/EngineProbe.mm -o "$app/Contents/MacOS/EngineProbe" -framework Foundation -Wl,-rpath,"/Library/Input Methods/DoubaoIme.app/Contents/Frameworks"
sign_flags=(--force --sign "${CIDU_SIGN_IDENTITY:--}" --options runtime)
if [[ "${CIDU_SIGN_IDENTITY:--}" != "-" ]]; then sign_flags+=(--timestamp); fi
codesign "${sign_flags[@]}" --identifier org.cidu.preview.engineprobe --entitlements Sources/Native/EngineProbe.entitlements "$app/Contents/MacOS/EngineProbe"
mkdir -p "$app/Contents/Resources/cidu-migrate"
cp skills/cidu-migrate/SKILL.md "$app/Contents/Resources/cidu-migrate/"
codesign "${sign_flags[@]}" --identifier org.cidu.preview.cli "$app/Contents/MacOS/cidu-cli"
codesign "${sign_flags[@]}" "$app"
echo "$app"
