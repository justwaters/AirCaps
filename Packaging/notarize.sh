#!/bin/sh
# Notarizes a Developer ID-signed app through Xcode's signed-in Apple ID (no
# app-specific password needed) and replaces it with the stapled result.
#   Packaging/notarize.sh AirCaps.app
# Wraps the app in a minimal .xcarchive, has `xcodebuild -exportArchive` upload
# it to Apple's notary service, polls until it is accepted, then exports the
# notarized, stapled app over the original.
set -eu

APP="$1"
TEAM="${TEAM_ID:-ZM89DBVX2V}"
IDENTITY="${SIGN_IDENTITY:?SIGN_IDENTITY must be a Developer ID Application identity}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PLIST="$APP/Contents/Info.plist"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$PLIST")
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
NAME=$(basename "$APP" .app)

ARCHIVE="$WORK/$NAME.xcarchive"
mkdir -p "$ARCHIVE/Products/Applications"
ditto "$APP" "$ARCHIVE/Products/Applications/$NAME.app"
cat > "$ARCHIVE/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>ArchiveVersion</key><integer>2</integer>
 <key>Name</key><string>$NAME</string>
 <key>SchemeName</key><string>$NAME</string>
 <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
 <key>ApplicationProperties</key><dict>
  <key>ApplicationPath</key><string>Applications/$NAME.app</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>SigningIdentity</key><string>$IDENTITY</string>
  <key>Team</key><string>$TEAM</string>
 </dict>
</dict></plist>
PLIST_EOF
cat > "$WORK/ExportOptions.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>method</key><string>developer-id</string>
 <key>teamID</key><string>$TEAM</string>
 <key>destination</key><string>upload</string>
 <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST_EOF

echo "Uploading $NAME $VERSION for notarization..."
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "$WORK/upload" -allowProvisioningUpdates

echo "Waiting for Apple to notarize..."
tries=0
until xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$WORK/notarized" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 40 ]; then echo "Timed out waiting for notarization" >&2; exit 1; fi
    sleep 30
done

xcrun stapler validate "$WORK/notarized/$NAME.app"
rm -rf "$APP"
ditto "$WORK/notarized/$NAME.app" "$APP"
echo "Notarized and stapled: $APP"
