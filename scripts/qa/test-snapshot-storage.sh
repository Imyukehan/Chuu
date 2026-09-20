#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
DEVELOPER="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/chuu-snapshot-tests.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
xcrun swiftc -D CHUU_STANDALONE_SNAPSHOT_TESTS \
  -I "$DEVELOPER/usr/lib" -L "$DEVELOPER/usr/lib" \
  -F "$DEVELOPER/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEVELOPER/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEVELOPER/usr/lib" \
  Shared/MouseSnapshot.swift ChuuTests/MouseSnapshotStoreTests.swift \
  scripts/qa/verify-snapshot-storage.swift -o "$STAGE/snapshot-tests"
"$STAGE/snapshot-tests"
