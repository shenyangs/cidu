#!/bin/bash
# Developer release only. Uses an existing notarytool Keychain profile; never stores credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CIDU_SIGN_IDENTITY:?Set a Developer ID Application identity}"
: "${CIDU_NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
if [[ "${1:-}" != "--skip-build" ]]; then bash scripts/build.sh; fi
app="$PWD/build/词渡.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
out="$PWD/dist/Cidu-$version-notarization"
mkdir -p "$out"
codesign --verify --deep --strict "$app"
signature_details=$(codesign -dv --verbose=2 "$app" 2>&1)
/usr/bin/grep -q 'runtime' <<< "$signature_details"
notarize() {
    local artifact="$1" tag="$2" request_id status
    xcrun notarytool submit "$artifact" --keychain-profile "$CIDU_NOTARY_PROFILE" --output-format json > "$out/$tag-submit.json"
    request_id=$(/usr/bin/plutil -extract id raw -o - "$out/$tag-submit.json")
    for ((attempt=0; attempt<90; attempt++)); do
        xcrun notarytool info "$request_id" --keychain-profile "$CIDU_NOTARY_PROFILE" --output-format json > "$out/$tag-info.json"
        status=$(/usr/bin/plutil -extract status raw -o - "$out/$tag-info.json")
        if [[ "$status" == "Accepted" ]]; then echo "$tag: Accepted ($request_id)"; return; fi
        if [[ "$status" != "In Progress" ]]; then
            xcrun notarytool log "$request_id" --keychain-profile "$CIDU_NOTARY_PROFILE" "$out/$tag-log.json" || true
            echo "$tag: $status; see $out/$tag-log.json" >&2; return 1
        fi
        sleep 10
    done
    echo "$tag: still processing; request $request_id" >&2; return 1
}
zip="$PWD/dist/Cidu-$version-macOS-arm64.zip"
[[ ! -e "$zip" ]] || mv "$zip" "$out/previous-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
notarize "$zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
# Rebuild the ZIP so offline users receive the stapled app.
rm "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
stage=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/词渡.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/安装说明.txt" <<'TEXT'
将「词渡」拖到 Applications，再从“应用程序”打开。
选择来源和目标，点“开始迁移”。首次自动读取百度词库时，按应用内提示允许辅助功能权限，返回后自动继续。
自动迁移目前验证于 Apple Silicon Mac、百度 6.1.12.10、豆包 1.0.2；其他环境请按应用兼容检查处理。
词库与备份保存在本机。迁移记录中可以验证结果或恢复迁移前的备份。
TEXT
dmg="$PWD/dist/Cidu-$version-macOS-arm64.dmg"
[[ ! -e "$dmg" ]] || mv "$dmg" "$out/previous-macOS-arm64.dmg"
hdiutil create -volname "词渡 $version" -srcfolder "$stage" -format UDZO "$dmg"
codesign --force --sign "$CIDU_SIGN_IDENTITY" --timestamp "$dmg"
notarize "$dmg" dmg
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
shasum -a 256 "$zip" "$dmg" > "$PWD/dist/Cidu-$version-SHA256.txt"
echo "$dmg"
