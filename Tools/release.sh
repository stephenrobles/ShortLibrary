#!/bin/zsh
# Archives ShortLibrary for macOS, exports it with Developer ID (the app is sandboxed and uses
# iCloud, so the export goes through Xcode's provisioning rather than a bare codesign), optionally
# notarizes it, packages a DMG, and optionally copies the DMG into the beardfm.app site.
#
# Usage:  Tools/release.sh [--notarize] [--upload]
#   --notarize   uses the notarytool keychain profile in $NOTARY_PROFILE (default "ipodpromax-notary").
#                Create one with: xcrun notarytool store-credentials <name> --apple-id you@example.com --team-id J9228F689B
#   --upload     (requires --notarize) signs the DMG for Sparkle with the EdDSA key in the keychain
#                (account "shortlibrary"), copies it into the beardfm.app site as downloads/ShortLibrary-<version>.dmg
#                and downloads/ShortLibrary.dmg, and adds it to shortlibrary/appcast.xml (with
#                release-notes/<version>.html if present). Deploy the site afterwards with `npm run deploy`.
#
# Provisioning: the app is sandboxed and uses iCloud, so Developer ID export needs a provisioning profile.
# xcodebuild creates it through the App Store Connect API key in $ASC_KEY_PATH / $ASC_KEY_ID / $ASC_ISSUER_ID
# (defaults below point at the key shared with the other apps).
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
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_Z5YD293RLM.p8}"
ASC_KEY_ID="${ASC_KEY_ID:-Z5YD293RLM}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de84-dcf8-47e3-e053-5b8c7c11a4d1}"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
# Apple doesn't let automatic signing create Developer ID profiles. Create one in the developer portal
# (Profiles › Developer ID › App ID fm.beard.ShortLibrary) and pass its name, or install it in
# ~/Library/Developer/Xcode/UserData/Provisioning Profiles and the default name below matches it.
DEVID_PROFILE="${DEVID_PROFILE:-ShortLibrary Developer ID}"

BUILD="$ROOT/build/release"
DIST="$ROOT/dist"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"

echo "▶ Archiving Release…"
xcodebuild -project "ShortLibrary.xcodeproj" -scheme "ShortLibrary" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$BUILD/ShortLibrary.xcarchive" \
  -derivedDataPath "$BUILD/DerivedData" "${AUTH[@]}" archive 2>&1 | grep -E "error:|ARCHIVE" || true
[[ -d "$BUILD/ShortLibrary.xcarchive" ]] || { echo "Archive failed."; exit 1; }

echo "▶ Exporting with Developer ID…"
cat > "$BUILD/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>J9228F689B</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>provisioningProfiles</key><dict><key>fm.beard.ShortLibrary</key><string>$DEVID_PROFILE</string></dict>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$BUILD/ShortLibrary.xcarchive" -exportOptionsPlist "$BUILD/export.plist" \
  -exportPath "$BUILD/export" "${AUTH[@]}" 2>&1 | grep -E "error:|EXPORT" || true
APP="$BUILD/export/ShortLibrary.app"
[[ -d "$APP" ]] || { echo "Export failed: app not found"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILDNUM=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "▶ Version $VERSION ($BUILDNUM)"
codesign --verify --deep --strict --verbose=2 "$APP"

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
  SPARKLE_BIN=$(find "$BUILD/DerivedData/SourcePackages/artifacts" -type d -name bin -path "*parkle*" | head -1)
  [[ -x "$SPARKLE_BIN/sign_update" ]] || { echo "Sparkle's sign_update tool wasn't found."; exit 1; }
  echo "▶ Signing update for Sparkle…"
  SIGNATURE=$("$SPARKLE_BIN/sign_update" --account shortlibrary "$DMG")
  MIN_MACOS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")
  UPDATE_NAME="ShortLibrary-$VERSION.dmg"
  echo "▶ Copying into beardfm.app…"
  mkdir -p "$SITE/site/static/downloads" "$SITE/site/static/shortlibrary"
  cp "$DMG" "$SITE/site/static/downloads/$UPDATE_NAME"
  cp "$DMG" "$SITE/site/static/downloads/ShortLibrary.dmg"
  echo "▶ Publishing Sparkle update…"
  NOTES=()
  [[ -f "$ROOT/release-notes/$VERSION.html" ]] && NOTES=("$ROOT/release-notes/$VERSION.html")
  "$ROOT/Tools/update-appcast.py" "$SITE/site/static/shortlibrary/appcast.xml" "$VERSION" "$BUILDNUM" "$MIN_MACOS" \
    "https://beardfm.app/downloads/$UPDATE_NAME" "$SIGNATURE" "${NOTES[@]}"
  echo "▶ Update $VERSION ($BUILDNUM) is staged in the site. Deploy with: (cd $SITE && npm run deploy)"
fi

ls -la "$DMG"
echo "✔ Done: $DMG"
