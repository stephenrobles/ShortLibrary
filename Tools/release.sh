#!/bin/zsh
# Archives ShortLibrary for macOS, exports it with Developer ID (the app is sandboxed and uses
# iCloud, so the export goes through Xcode's provisioning rather than a bare codesign), optionally
# notarizes it, packages a DMG, and optionally copies the DMG into the beardfm.app site.
#
# Usage:  Tools/release.sh [--notarize] [--upload]
#   --notarize   uses the notarytool keychain profile in $NOTARY_PROFILE (default "ipodpromax-notary").
#                Create one with: xcrun notarytool store-credentials <name> --apple-id you@example.com --team-id J9228F689B
#   --upload     (requires --notarize) copies the DMG into the beardfm.app site as
#                downloads/ShortLibrary-<version>.dmg and downloads/ShortLibrary.dmg. Deploy the site afterwards.
#
# Output: dist/ShortLibrary <version>.dmg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SITE="${BEARDFM_SITE:-$HOME/Movies/Apps/beardfm.app}"
NOTARIZE=0
UPLOAD=0
for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    --upload) UPLOAD=1 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done
[[ $UPLOAD -eq 1 && $NOTARIZE -eq 0 ]] && { echo "--upload requires --notarize so users never get an unnotarized build."; exit 1; }
NOTARY_PROFILE="${NOTARY_PROFILE:-ipodpromax-notary}"

BUILD="$ROOT/build/release"
DIST="$ROOT/dist"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"

echo "▶ Archiving Release…"
xcodebuild -project "ShortLibrary.xcodeproj" -scheme "ShortLibrary" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$BUILD/ShortLibrary.xcarchive" \
  -derivedDataPath "$BUILD/DerivedData" -allowProvisioningUpdates archive 2>&1 | grep -E "error:|ARCHIVE" || true
[[ -d "$BUILD/ShortLibrary.xcarchive" ]] || { echo "Archive failed."; exit 1; }

echo "▶ Exporting with Developer ID…"
cat > "$BUILD/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>J9228F689B</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$BUILD/ShortLibrary.xcarchive" -exportOptionsPlist "$BUILD/export.plist" \
  -exportPath "$BUILD/export" -allowProvisioningUpdates 2>&1 | grep -E "error:|EXPORT" || true
APP="$BUILD/export/ShortLibrary.app"
[[ -d "$APP" ]] || { echo "Export failed: app not found"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILDNUM=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "▶ Version $VERSION ($BUILDNUM)"
codesign --verify --strict --verbose=2 "$APP"

DEVID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
[[ -n "$DEVID" ]] || { echo "No Developer ID Application certificate found in the keychain."; exit 1; }

if [[ $NOTARIZE -eq 1 ]]; then
  echo "▶ Notarizing app…"
  ZIP="$BUILD/app.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi

echo "▶ Packaging DMG…"
STAGE="$BUILD/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/ShortLibrary $VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "ShortLibrary" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG" > /dev/null
codesign --force --timestamp --sign "$DEVID" "$DMG"
if [[ $NOTARIZE -eq 1 ]]; then
  echo "▶ Notarizing DMG…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

if [[ $UPLOAD -eq 1 ]]; then
  [[ -d "$SITE/site/static" ]] || { echo "beardfm.app site not found at $SITE (set BEARDFM_SITE)."; exit 1; }
  mkdir -p "$SITE/site/static/downloads"
  cp "$DMG" "$SITE/site/static/downloads/ShortLibrary-$VERSION.dmg"
  cp "$DMG" "$SITE/site/static/downloads/ShortLibrary.dmg"
  echo "▶ Copied into beardfm.app as downloads/ShortLibrary-$VERSION.dmg. Deploy the site with: (cd $SITE && npm run deploy)"
fi

ls -la "$DMG"
echo "✔ Done: $DMG"
