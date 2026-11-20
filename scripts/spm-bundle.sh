#!/bin/bash
# Builds Ghostwriter.app with SwiftPM and the Command Line Tools only (no Xcode, no XcodeGen).
# Usage: scripts/spm-bundle.sh [bundle-id]
# Signs with $GW_SIGN_IDENTITY when codesign can use it, ad hoc otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."
BUNDLE_ID="${1:-com.mshl.ghostwriter}"
NAME=Ghostwriter
OUT=build-spm
APP=$OUT/$NAME.app

swift build -c release
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/$NAME"
for framework in "$BIN"/*.framework; do ditto "$framework" "$APP/Contents/Frameworks/$(basename "$framework")"; done
# Bundle.module looks at the .app root, which codesign cannot seal, then falls back to the absolute .build path.
# The bundles are copied here so the app is sealable; a relocatable build still needs Bundle.module replaced.
for bundle in "$BIN"/*.bundle; do ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"; done

# actool ships with Xcode only, so the asset catalog's images go in as plain files.
find Ghostwriter/Assets.xcassets -name '*.svg' -exec cp {} "$APP/Contents/Resources/" \;

ICONSET=$OUT/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
SRC=Ghostwriter/AppIcon.icon/Assets/mascot.png
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

VERSION=$(git describe --tags --always | sed 's/^v//')
PLIST=$APP/Contents/Info.plist
sed -e "s/\$(EXECUTABLE_NAME)/$NAME/" -e "s/\$(PRODUCT_NAME)/$NAME/" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" -e "s/\$(MARKETING_VERSION)/$VERSION/" \
  -e "s/\$(CURRENT_PROJECT_VERSION)/$(git rev-list --count HEAD)/" -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/26.0/" \
  Ghostwriter/Info.plist > "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
# A local build must never be "updated" back to the upstream release.
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" -c "Delete :SUPublicEDKey" -c "Set :SUEnableAutomaticChecks false" "$PLIST"

chmod -R u+w "$APP"
xattr -cr "$APP"
IDENTITY="${GW_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$IDENTITY" "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP ($BUNDLE_ID, $VERSION)"
