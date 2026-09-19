#!/usr/bin/env bash
set -euo pipefail

SOURCE=$(cd "${1:?source checkout required}" && pwd)
TAG=${2:?version tag required}
mkdir -p "${3:?output directory required}"
OUTPUT=$(cd "$3" && pwd)
TOOLS=$(cd "$(dirname "$0")" && pwd)
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version tag' >&2; exit 1; }
[[ -z "$(git -C "$SOURCE" status --porcelain)" ]] || { echo 'Source checkout must be clean' >&2; exit 1; }
if [[ -n "$(git -C "$SOURCE" ls-files --others --ignored --exclude-standard -- Chuu/Assets.xcassets)" ]]; then
  echo 'Local-only artwork found. Package a clean checkout, not the local development workspace.' >&2
  exit 1
fi
COMMIT=$(git -C "$SOURCE" rev-parse HEAD)
[[ "$(git -C "$SOURCE" rev-parse "refs/tags/$TAG^{commit}")" == "$COMMIT" ]] || {
  echo 'Source checkout does not match the version tag' >&2
  exit 1
}

cd "$SOURCE"
mkdir -p build
xcodegen generate --spec project.yml
# Ad-hoc signing is only for this isolated package, never the installed app or app-hosted tests.
xcodebuild -project Chuu.xcodeproj -scheme Chuu -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/TestRelease \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGNING_ALLOWED=YES PROVISIONING_PROFILE_SPECIFIER= \
  ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build 2>&1 | tee build/ci-build.log

APP="$SOURCE/build/TestRelease/Build/Products/Release/Chuu.app"
codesign --verify --deep --strict "$APP"
for binary in "$APP/Contents/MacOS/MouseControl" "$APP/Contents/PlugIns/ChuuWidget.appex/Contents/MacOS/ChuuWidget"; do
  architectures=$(xcrun lipo -archs "$binary")
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
    echo "Missing universal architecture in $binary: $architectures" >&2
    exit 1
  }
done
python3 "$TOOLS/test_release_metadata.py" "$APP" "$TAG" "$COMMIT" "$OUTPUT"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/chuu-test-package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
NAME="Chuu-${TAG#v}-unnotarized-universal"
mkdir -p "$STAGE/$NAME"
ditto "$APP" "$STAGE/$NAME/Chuu.app"
cp LICENSE NOTICES.md "$STAGE/$NAME/"
cp "$OUTPUT/release-notes.md" "$STAGE/$NAME/README.md"
cp "$OUTPUT/build-info.json" "$STAGE/$NAME/"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE/$NAME" "$OUTPUT/$NAME.zip"
unzip -tq "$OUTPUT/$NAME.zip"
if zipinfo -1 "$OUTPUT/$NAME.zip" | grep -E '(^|/)\._'; then
  echo 'Unexpected AppleDouble entries in package' >&2
  exit 1
fi
# Verify the extracted archive, not only the original build directory.
mkdir "$STAGE/extracted"
unzip -q "$OUTPUT/$NAME.zip" -d "$STAGE/extracted"
codesign --verify --deep --strict "$STAGE/extracted/$NAME/Chuu.app"
cd "$OUTPUT"
shasum -a 256 "$NAME.zip" build-info.json release-notes.md > SHA256SUMS
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'tag=%s\ncommit=%s\n' "$TAG" "$COMMIT" >> "$GITHUB_OUTPUT"
fi
printf 'Verified test package: %s/%s.zip\n' "$OUTPUT" "$NAME"
