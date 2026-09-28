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

## First Launch Permissions

Chuu reuses the Mos introduction window to collect Accessibility and Input Monitoring
before starting HID reads, scrolling or shortcuts. Notifications appear in the same
window but remain optional; granting notification access does not change the saved
low-battery reminder preference. Permission status refreshes when returning from
System Settings. The app menu and status-item menu both expose **Permissions**.

The application icon can be dragged into a System Settings permission list if Chuu
is missing. After replacing an ad-hoc build, stale permission entries may need to be
removed and the current app added again. This flow never requests Full Disk Access;
App Group signing failures are handled separately by the battery-cache fallback.

Use the question-mark button in **Permissions** for recovery instructions even when
the rows show authorization as enabled. Remove only the stale Chuu entries from
Input Monitoring and Accessibility, add the currently installed app, enable them,
and restart Chuu. An HID access-denied alert also links to Permissions; the same
failure is not presented again on every battery poll.

## Widget Sharing

The app and widget read/write the same App Group snapshot only in a build signed
by the matching team. Ad-hoc GitHub test packages intentionally use a private app
cache instead. Thus a working battery reading inside the app does not establish
that widget sharing is available. This is not a G7 adapter or Input Monitoring issue.

The widget distinguishes an unsupported build, an inaccessible shared container,
a missing snapshot, an unreadable snapshot, and a successfully read empty device
list. Only the last case displays **No mouse connected**. General settings exposes
sharing failures with an on-demand explanation. Use a correctly signed app and
widget pair to enable sharing; do not grant Full Disk Access or manually copy
private cache files into protected containers.

For UI-only checks, launch a Debug build with `-ChuuPreviewPermissions`, optionally
adding `-ChuuPreviewAppearance light` or `dark`. This process-local preview shows
missing permissions without resetting TCC, opening HID devices or changing settings.

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

The original Chuu Icon Composer document is in `Resources/Chuu.icon`. Starting with 0.1.4, the private personal-use repository tracks `G502Top`, `G502Side`, `G502RenderTop`, `G502RenderSide` and `G7`. Unknown devices use the original `GenericMouse` illustration. Packaging verifies the compiled artwork and requires the GitHub repository to remain private. See `NOTICES.md` before changing visibility; the vendor renders are not covered by the source-code license.

This private repository provides source and [automated unnotarized test packages](ci-releases.md), not a notarized distribution or a stable release. Keep normal development signing for local installation and app-hosted tests; the CI packaging script uses an isolated ad-hoc build instead.

See [in-app updates](updates.md) for the current development behavior and the proposed Sparkle/GitHub release workflow.
