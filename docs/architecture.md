# Chuu Architecture

## Active Project

`project.yml` generates the only active project, `Chuu.xcodeproj`. The normal shared scheme is `Chuu`; targets are `Chuu`, `ChuuWidget` and `ChuuTests`. `ChuuHardwareTests` is a separate, opt-in scheme for owner-approved hardware tests. Do not edit the generated project to add files; regenerate after moving or adding source files. `Examples/MouseAdapter/ExampleMouseAdapter.swift` belongs only to the test target.

| Directory | Responsibility |
| --- | --- |
| `Chuu/DeviceControl` | App model, hardware scan orchestration, HID transport, window, alerts |
| `Chuu/Devices` | Battery adapter contracts, explicit registry and vendor/model implementations |
| `Chuu/Devices/Logitech` | G502 X PLUS adapter and its validated onboard profile format |
| `Chuu/Devices/MCHOSE` | G7 battery request and response parser |
| `Chuu/Logi` | Inherited HID++ session/input integration, separate from battery adapters |
| `Chuu/Integration` | Bridge between the inherited Logi engine and the app |
| `Chuu/ScrollCore`, `ButtonCore`, `InputEvent`, `Shortcut` | Scrolling, input, and shortcut processing |
| `Chuu/Options`, `Windows` | Existing settings, per-app rules and embedded preference views |
| `ChuuWidget`, `Shared` | Widget, Codable snapshot file and shared localization |
| `ChuuTests`, `Examples` | Tests, fixture transports and test-only extension example |

## Battery Path

`MouseAdapterRegistry` declares supported vendor interfaces. Discovery and hot-plug watching derive their matching dictionaries from this registry. A scan creates a channel on the serial hardware worker, instantiates the selected adapter and maps its reading to `MouseSnapshot`. UI, alerts and the widget consume snapshots, not vendor packets.

Exact interface matching selects an adapter. Product-only recognition suppresses duplicate ordinary mouse interfaces from an already-supported receiver. Unknown standard USB/Bluetooth mice use generic presentation with no invented battery percentage. A timeout preserves an offline snapshot; an explicitly unsupported protocol/model is omitted. A successful read is required to mark a supported mouse online.

`ChuuModel` owns the 30-second polling timer and cached last-known battery value. It writes snapshots to the App Group and asks WidgetKit to refresh when relevant state changes. The widget cannot poll hardware itself. Sleep pauses polling; connection alerts also respect screen/session state.

## Write Boundary

The battery adapter protocol grants no profile-write capability. `MouseHardwareService.profile/save` remains explicitly G502-only. Its adapter verifies the device name and profile descriptor, checks the active sector and expected bytes, saves a backup, verifies the write and attempts rollback on failure. Do not generalize this by changing a product ID. A new writable model requires its own verified format, capability routing, UI and tests.

The inherited Logi engine and new battery readers are separate. The G502 receiver exclusion in `LogiSessionManager` prevents two owners from handling the same interface. When adding a Logitech model, review transport ownership as well as packet compatibility.

## Compatibility Identifiers

Source names are Chuu. These existing runtime identities deliberately remain unchanged so a source cleanup does not create a separate app, preference domain or widget:

- App bundle ID: `moe.khan.MouseControl`; widget: `moe.khan.MouseControl.BatteryWidget`.
- Executable: `MouseControl`, retained alongside the existing signing identity.
- App Group: `MA4UNJ3J25.moe.khan.MouseControl`.
- Widget kind: `MouseBatteryWidget`; URL scheme: `mousecontrol`.
- Snapshot file `mouse-batteries.json`, model IDs `g502x` / `g7`, and existing device IDs.
- Settings keys, shortcut identifiers (including inherited `mos...` values), notification identifiers and hardware-backup paths.

These are compatibility contracts, not display branding. New contributors should use their own signing configuration for a separate install; existing users rebuilding an update should retain these identities. No preference migration or hardware rewrite is performed by this rename.

Legacy upstream translations are under `docs/upstream/readmes`. Historical plans, website and release tooling are not authoritative for the current Chuu build. Original copyright comments and upstream URLs are attribution and should not be blindly renamed.
