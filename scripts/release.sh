#!/bin/bash
# Builds Presently, signs it with Developer ID, notarizes and staples it, and uploads the zip
# as a draft GitHub release (publish it on GitHub after checking).
#
# Usage: scripts/release.sh 1.0.0
#
# One-time setup:
#   - "Developer ID Application" certificate of the team in the keychain
#     (Xcode → Settings → Accounts → Manage Certificates)
#   - notary credentials in the keychain:
#     xcrun notarytool store-credentials presently-notary --apple-id <id> --team-id 7XW8432Z53
#   - gh logged in, repository with a GitHub remote, HEAD pushed
set -euo pipefail

VERSION=${1:?usage: scripts/release.sh <version>, e.g. 1.0.0}
TEAM_ID=7XW8432Z53
NOTARY_PROFILE=${NOTARY_PROFILE:-presently-notary}
TAG="v$VERSION"
OUT=build/release
APP="$OUT/export/Presently.app"
ZIP="$OUT/Presently-$VERSION.zip"

cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }

step "Checking preconditions"
[[ $VERSION =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "version must look like 1.0 or 1.0.0"
[[ -z $(git status --porcelain) ]] || die "working tree not clean"
# No `cmd | grep -q` under pipefail: grep exits on the first match and cmd dies of SIGPIPE.
grep -q "Developer ID Application: .*($TEAM_ID)" <<< "$(security find-identity -v -p codesigning)" \
    || die "no \"Developer ID Application\" certificate for team $TEAM_ID in the keychain"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notary profile \"$NOTARY_PROFILE\" missing (xcrun notarytool store-credentials)"
gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
gh release view "$TAG" >/dev/null 2>&1 && die "release $TAG already exists"
git fetch --quiet
[[ -n $(git branch -r --contains HEAD) ]] || die "HEAD is not pushed"

# Build number: commit count, so it grows with every release.
BUILD=$(git rev-list --count HEAD)

step "Archiving $VERSION ($BUILD)"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild archive -quiet -project Presently.xcodeproj -scheme Presently -configuration Release \
    -destination "generic/platform=macOS" -archivePath "$OUT/Presently.xcarchive" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD"

step "Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -quiet -allowProvisioningUpdates -archivePath "$OUT/Presently.xcarchive" \
    -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist"
codesign --verify --strict --deep "$APP"
grep -q "Authority=Developer ID Application" <<< "$(codesign -dvv "$APP" 2>&1)" || die "app is not signed with Developer ID"

step "Notarizing (takes a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
    --output-format json > "$OUT/notary.json"
STATUS=$(plutil -extract status raw "$OUT/notary.json")
if [[ $STATUS != Accepted ]]; then
    ID=$(plutil -extract id raw "$OUT/notary.json")
    xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" || true
    die "notarization: $STATUS"
fi
xcrun stapler staple -q "$APP"
spctl --assess --type execute "$APP" || die "Gatekeeper rejects the app"

step "Packing $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Creating draft release $TAG"
gh release create "$TAG" "$ZIP" --draft --target "$(git rev-parse HEAD)" \
    --title "Presently $VERSION" --generate-notes
echo "Draft created — check it and publish it on GitHub."
