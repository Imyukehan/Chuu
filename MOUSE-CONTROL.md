# Chuu

Personal, noncommercial fork of [Mos](https://github.com/Caldis/Mos), by Caldis.
The upstream CC BY-NC 4.0 license and attribution remain in place.

## Build

The fork uses `project.yml` and the generated `MouseControl.xcodeproj`.
The original `Mos.xcodeproj` is retained for upstream comparison, not the fork's build entry point.
Xcode, XcodeGen and the local Apple Development signing identity are required.

```sh
./script/build_and_run.sh --build
./script/build_and_run.sh --verify
./script/build_and_run.sh --install
```

While the original Mos is running, this fork pauses its global event processor; battery reads and the widget remain available.
Quit the original Mos to let this fork take over scrolling and shortcuts. The original app is never terminated automatically.
`--install` builds Release and installs into `~/Applications/Chuu.app`, keeping one previous bundle under `~/Library/Application Support/moe.khan.MouseControl/InstallBackup/`. Older rollback copies move to Trash. Bundle IDs, executable name, preferences, URL scheme and App Group remain unchanged.
The fork uses its own bundle identifier and UserDefaults, and does not import or overwrite the original Mos preferences.
The new app and widget require macOS 14 or later. The upstream project's deployment settings are untouched.

## First Scope

- Large native translucent window, actual product images and button hotspots.
- G502 X PLUS / LIGHTSPEED C547 receiver, slot 1: battery, active onboard profile, button assignments, persistent RGB toggle.
- MCHOSE G7 / 2255 receiver: battery only.
- MOS scrolling, shortcut recording and per-application settings are retained as native embedded panes.
- One menu bar entry. Small and medium WidgetKit battery widgets.

Button names follow MOS/macOS numbering: HID Mouse 6 appears as Mouse 5. Left click cannot be overwritten.
Hardware writes require an explicit Apply action or RGB toggle. Each write checks the current profile, saves a backup,
preserves unrelated fields, writes the checksum, reads back the entire sector and preserves the active DPI index.
Only the active profile is changed. Profile formats and devices not validated here are not writable.

Backups: `~/Library/Application Support/moe.khan.MouseControl/Backups/`.
RGB-on restores only the lighting block from the newest valid, non-off backup for the same device/profile.
Without a matching backup, it uses the G502 X PLUS effect records captured before the original lights-off experiment
(modes 0F/0F/10/10, brightness 100, animation selector 03). Button and DPI fields are never restored from a lighting backup.
The app polls on a serial background queue every 30 seconds (3-second timer tolerance), including while menus track,
and pauses while the Mac sleeps. Wake and reopening the main window request an immediate read.
Receiver presence is distinct from a responding mouse; unresponsive devices do not display invented percentages.
The widget reads an atomic snapshot from the shared App Group. Changes in battery, connection or charging request a
timeline reload; the widget also requests a reload after 15 minutes. WidgetKit schedules the actual refreshes;
stale readings are marked with their last-update time. The host app must remain running for new readings.

## Product Imagery

Images are vendor-owned, used for this local personal prototype. They are not relicensed under the code license.
Standalone vendor images are excluded from the public repository. The app uses a generic mouse symbol when they are absent.

- Logitech (white): https://resource.logitechg.com/content/dam/gaming/en/products/g502x-plus/gallery/g502x-plus-gallery-2-white.png
- Logitech (white): https://resource.logitechg.com/content/dam/gaming/en/products/g502x-plus/gallery/g502x-plus-gallery-4-white.png
- MCHOSE: https://www.mchose.com.cn/gmouse/_next/static/media/G7_white.f3231821.png

The imagery is a static product render, not a live representation of RGB state or mouse color.

## Verification

### RGB And Controls Verified On 2026-09-19

- 15 profile, navigation, fixed-window and compiled-branding tests passed; Logi boundary lint passed.
- The installed app's RGB switch was toggled on and off on the real G502 X PLUS. Both writes were read-back verified,
  and the user confirmed the physical LEDs illuminated and then went dark. Final state: off.
- The two pre-write backups have valid CRCs and identical bytes 0...207; existing Mouse 5/6/7 mappings are unchanged.
- Main-window UI uses native toolbar tabs, glass hotspots and Apply button on macOS 26+, with fallback controls on older systems.
- Battery snapshots continued advancing without a battery-percentage change, confirming background polling remained active.

```sh
scripts/qa/lint-logi-boundary.sh
xcodebuild -project MouseControl.xcodeproj -scheme Debug -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/MouseControl \
  test -only-testing:MosTests/MouseControlProfileTests
```

Stop the running fork before tests. Tests use the same development signature; do not disable code signing.
Fixtures and unit tests never write to physical devices.

### Verified On 2026-09-18

- Signed universal Release app installed at `~/Applications/Mouse Control.app`; nested signature verification passed.
- Five `MouseControlProfileTests` passed; Logi boundary lint and whitespace checks passed.
- Real G502 X PLUS: app displayed 82%, 2.4 GHz, the existing Mouse 5/6/7 mappings and stored RGB-off state.
- Native top/side device views and embedded scrolling pane were inspected in the running app.
- Accessibility/device-control permission was confirmed enabled in System Settings.
- WidgetKit reported one configured widget. The actual widget extension generated a timeline from the shared snapshot with battery 82%, distinct from the gallery's 83% placeholder.
- Final GUI reopening was blocked by the Mac being locked. The G7 adapter and new GUI-triggered hardware writes still need live acceptance testing; no mouse configuration was changed during this app implementation.
