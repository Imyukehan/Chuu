# Build Chuu

## Requirements

- macOS 14 or later to run. Liquid Glass controls require macOS 26+.
- The current project was built with Xcode 27.1 / its macOS SDK. The toolbar uses an API gated on macOS 27; building with an older SDK is not verified.
- XcodeGen (`brew install xcodegen`).
- An Apple Development signing identity for the app and embedded WidgetKit extension.

## Signing Your Own Build

The checked-in project contains the maintainer's public team and bundle identifiers, not private signing keys. A clone does not include a signing identity.

Before building on another developer account:

1. Change `DEVELOPMENT_TEAM` in `project.yml` to your team.
2. Choose your own app, widget and test bundle identifiers in `project.yml` if needed.
3. Replace the App Group string in both `Configuration/*.entitlements` and `Shared/MouseSnapshot.swift` with the same group registered for your team. Enable that group for both targets in Signing & Capabilities.
4. Run `xcodegen generate --spec project.yml`, then open `Chuu.xcodeproj` and let Xcode resolve signing for both targets.

Changing identifiers creates separate preferences, permissions and widget storage. Existing Chuu users should keep their identifiers when rebuilding an update.
The old Xcode projects and test plans have been removed; they remain in Git history. Upstream release tooling is historical and is not Chuu's build entry point. Targets are `Chuu`, `ChuuWidget` and `ChuuTests`, and the normal scheme is `Chuu`.

## Local Workflow

```sh
./script/build_and_run.sh --build
./script/build_and_run.sh --install
```

`--install` builds Release, verifies the signature, installs in `~/Applications/Chuu.app`, and opens it. One previous version is retained under `~/Library/Application Support/moe.khan.MouseControl/InstallBackup/`; an older rollback copy is moved to Trash. Installation does not erase preferences or hardware-profile backups.

The no-argument script builds and runs Debug. Avoid leaving both the Debug build and installed app running. The script stops this fork's process before launching, but never terminates the original Mos automatically.

## Tests

Stop the running Chuu app before tests. Keep normal development signing; do not use `CODE_SIGNING_ALLOWED=NO` with an app-hosted test run.

```sh
xcodebuild -project Chuu.xcodeproj -scheme Chuu \
  -destination 'platform=macOS' -derivedDataPath build/Chuu \
  test -only-testing:ChuuTests/ChuuProfileTests \
  -only-testing:ChuuTests/ChuuNavigationTests \
  -only-testing:ChuuTests/ChuuWindowTests \
  -only-testing:ChuuTests/ChuuBrandingTests \
  -only-testing:ChuuTests/ButtonBindingTests
scripts/qa/lint-logi-boundary.sh
```

For the full default suite, omit the `-only-testing` arguments. The `Chuu` scheme explicitly disables real-device tests. Only with the device owner's consent, use the separate `ChuuHardwareTests` scheme, which enables `LOGI_REAL_DEVICE=1`. Never run that scheme as an unattended default check.

The normal tests use fixtures, not writes to attached mice. See [architecture](architecture.md) and [mouse adapter development](mouse-adapters.md). Existing bundle IDs, executable, App Group and widget kind are intentionally retained for installed-user compatibility.

## Artwork

The original Chuu Icon Composer document is in `Resources/Chuu.icon`. Vendor-owned `G502Top`, `G502Side` and `G7` image sets are optional local resources and excluded from Git. Without them the app renders the system mouse symbol; button settings remain available. The README screenshot shows the maintainer's local image sets, not additional hardware support.

This repository publishes source, not a notarized distribution or a stable release.
