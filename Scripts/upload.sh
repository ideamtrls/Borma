#!/bin/bash
# Builds Borma, uploads it to App Store Connect, sends it to the public
# TestFlight group, and submits it for Beta App Review.
#
# Reads its settings from .env (see .env.example). The API key file goes at
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

: "${BORMA_TEAM:?Set BORMA_TEAM to your Apple team ID}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID to your App Store Connect API key ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID to your App Store Connect API issuer ID}"
: "${BORMA_TESTFLIGHT_GROUP:?Set BORMA_TESTFLIGHT_GROUP to the name of your public TestFlight group}"

key="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [ ! -f "$key" ]; then
    echo "No API key at $key" >&2
    exit 1
fi

bundle_id="$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *//p' project.yml)"
# The commit count only goes up, and tells distribute.swift which build to wait for.
build_number="$(git rev-list --count HEAD)"

distribute() {
    ASC_KEY_PATH="$key" xcrun swift Scripts/distribute.swift "$@"
}

# Catches a bad key or group name before the slow part.
distribute "$bundle_id"

out=build/release
rm -rf "$out"
mkdir -p "$out"

options="$out/ExportOptions.plist"
cat > "$options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${BORMA_TEAM}</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
EOF

# Runs a long step quietly, showing the end of its log only if it fails.
run() {
    local name="$1"
    shift
    echo "==> $name"
    if ! "$@" > "$out/$name.log" 2>&1; then
        tail -20 "$out/$name.log" >&2
        echo "$name failed. Full log: $out/$name.log" >&2
        exit 1
    fi
}

run generate xcodegen generate

archive="$out/Borma.xcarchive"
# Its own derived data, so this can't replace a build you're running from build/.
run archive xcodebuild archive \
    -project Borma.xcodeproj \
    -scheme Borma \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$out/DerivedData" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -archivePath "$archive" \
    CURRENT_PROJECT_VERSION="$build_number"

info="$archive/Products/Applications/Borma.app/Contents/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$info")"
build="$(plutil -extract CFBundleVersion raw "$info")"
echo "Archived $version ($build)"

run upload xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$options" \
    -exportPath "$out/export" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$key" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "Uploaded $version ($build)."

if ! distribute "$bundle_id" "$version" "$build"; then
    echo "The upload worked, but the build didn't reach the group. To retry that part:" >&2
    echo "  ASC_KEY_PATH=\"$key\" xcrun swift Scripts/distribute.swift $bundle_id $version $build" >&2
    exit 1
fi
