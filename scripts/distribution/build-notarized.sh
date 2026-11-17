#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $# == 0 || ( $# == 1 && "$1" == --preflight ) ]] || { echo "Usage: bash $0 [--preflight]" >&2; exit 2; }

REPO=Imyukehan/Chuu
TEAM=7XZ82S4RRS
PROFILE="${CHUU_NOTARY_PROFILE:-chuu-notary}"
SIGN_UPDATE="$PWD/build/Chuu/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[[ "$(gh repo view "$REPO" --json nameWithOwner --jq .nameWithOwner)" == "$REPO" ]] || {
  echo "Unexpected release repository. Stop." >&2; exit 1;
}
IDENTITIES="$(security find-identity -v -p codesigning)"
if ! printf '%s\n' "$IDENTITIES" | rg "Developer ID Application: .*\\($TEAM\\)" >/dev/null; then
  echo "Missing Developer ID Application identity for team $TEAM. Create it in Xcode or the Apple developer portal." >&2
  exit 1
fi
[[ -x "$SIGN_UPDATE" ]] || { echo "Build Chuu once to resolve Sparkle signing tools." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null
if [[ "${1:-}" == --preflight ]]; then echo "Release repository, Developer ID identity and notarization credentials verified."; exit 0; fi

xcodegen generate --spec project.yml
SETTINGS=$(xcodebuild -project Chuu.xcodeproj -scheme Chuu -configuration Release -showBuildSettings -json)
read -r VERSION BUILD < <(printf '%s' "$SETTINGS" | python3 -c '
import json, sys
settings = next(row["buildSettings"] for row in json.load(sys.stdin) if row["target"] == "Chuu")
print(settings["MARKETING_VERSION"], settings["CURRENT_PROJECT_VERSION"])
')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]{8}\.[0-9]+$ ]] || {
  echo "Invalid or inconsistent version/build. Bump project.yml before packaging." >&2; exit 1;
}
OUT="$PWD/build/distribution/$VERSION-$BUILD"
[[ ! -e "$OUT" ]] || { echo "Output already exists; use a fresh build number: $OUT" >&2; exit 1; }
mkdir -p "$OUT"
xcodebuild archive -project Chuu.xcodeproj -scheme Chuu -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/Chuu \
  -archivePath "$OUT/Chuu.xcarchive" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath "$OUT/Chuu.xcarchive" \
  -exportOptionsPlist Configuration/DeveloperID-ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates
APP="$OUT/export/Chuu.app"
codesign --verify --deep --strict "$APP"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
[[ "$SIGNATURE" == *"TeamIdentifier=$TEAM"* && "$SIGNATURE" == *'Authority=Developer ID Application:'* ]] || {
  echo "Export did not use the expected Developer ID identity." >&2; exit 1;
}
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$OUT/notarization.zip"
xcrun notarytool submit "$OUT/notarization.zip" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT/notarization.json"
[[ "$(plutil -extract status raw "$OUT/notarization.json")" == Accepted ]]
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
ZIP="$OUT/Chuu-$VERSION-$BUILD-arm64.zip"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
if zipinfo -1 "$ZIP" | rg '(^|/)(\._[^/]*|__MACOSX)(/|$)'; then echo "Unexpected AppleDouble entries." >&2; exit 1; fi
"$SIGN_UPDATE" --account moe.khan.MouseControl "$ZIP" > "$OUT/archive-signature.txt"
git rev-parse HEAD > "$OUT/source-commit.txt"
git status --short > "$OUT/source-status.txt"
python3 -c 'import hashlib,pathlib,sys; p=pathlib.Path(sys.argv[1]); print(hashlib.sha256(p.read_bytes()).hexdigest()+"  "+p.name)' "$ZIP" > "$OUT/SHA256SUMS"
printf '\nNotarized archive: %s\nNo GitHub release was created or published.\n' "$ZIP"
