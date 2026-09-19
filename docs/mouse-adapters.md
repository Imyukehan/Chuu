# Adding Mouse Support

The maintainer has limited physical hardware. Contributions for additional manufacturers and models are welcome, especially read-only battery adapters with reproducible fixtures. There is no promise that an entire brand shares one protocol.

## Start Small

1. Record the exact mouse/receiver model, firmware and connection mode. Identify the vendor protocol interface's VID, PID, usage page and usage. USB, receiver and Bluetooth modes may expose different interfaces and protocols.
2. Verify the battery query and response using legitimate documentation or observed behavior. Record report ID, length, response header, battery offset/range, and charging semantics. Remove serial numbers and other personal data from fixtures.
3. Add `Chuu/Devices/<Vendor>/<Model>MouseAdapter.swift`. Implement `MouseBatteryAdapter.readBattery()` and a `MouseAdapterDescriptor` with an immutable model ID and exact interface IDs.
4. Register the descriptor and channel factory in `Chuu/Devices/MouseAdapterRegistry.swift`. Discovery and hot-plug matching update automatically. Do not register wildcard vendor IDs or treat a familiar product name as proof of protocol support.
5. Add pure parser and mock-transport tests in `ChuuTests`. Generate the project and run tests before trying hardware.
6. With the device owner's consent, verify the battery reading and connection lifecycle on the actual device. Document tested firmware/mode and unsupported features in both READMEs.

## Contracts

`MouseBatteryReading` carries a verified name, an optional percentage in `0...100`, and a charging flag. `nil` means unknown battery, not zero. Set charging only when the protocol establishes it; otherwise leave it false. The current snapshot format cannot distinguish unknown charging from not charging, so document that limitation for your adapter.

Throw `MouseHardwareError.unsupported` when the receiver responds but the paired model or required feature is not supported. Timeouts and malformed data must not be converted to a guessed reading. The service turns failures into offline state and rejects out-of-range percentages.

`MouseReportTransport.exchange` accepts a request, report ID and response matcher. The live `MouseHIDChannel` owns open/close and run-loop delivery on a single serial worker. The matcher must discriminate unrelated input reports. The adapter must validate length and all required fields again before indexing. The existing channel uses output reports with a 64-byte input buffer and a 1.5-second timeout; protocols requiring feature reports, larger buffers or another transport need an explicit transport extension and tests, not an unsafe workaround.

The existing Logitech adapter also uses the channel's HID++ feature/query helpers, which currently address receiver slot 1. Do not assume those helpers support every receiver, direct USB mode, or Bluetooth. `G502MouseAdapter.name()` verifies the paired model before reading or writing model-specific data.

## Runnable Example

[ExampleMouseAdapter.swift](../Examples/MouseAdapter/ExampleMouseAdapter.swift) is compiled into **ChuuTests only**. It illustrates a descriptor, injectable transport, response matching and parser. Its IDs and three-byte protocol are fictional, it is absent from the runtime registry, and it must never be sent to real hardware.

[MouseAdapterTests.swift](../ChuuTests/MouseAdapterTests.swift) exercises the example without opening HID. It also tests the real G7 request/decoder, unrelated responses, truncation, invalid percentages, timeout/offline behavior and exact registry matching.

```sh
xcodegen generate --spec project.yml
# Quit Chuu before running app-hosted tests; keep normal signing.
xcodebuild -project Chuu.xcodeproj -scheme Chuu \
  -destination 'platform=macOS' -derivedDataPath build/Chuu \
  test -only-testing:ChuuTests/MouseAdapterTests
```

For a real adapter, remove the example's `@testable import Chuu`, put the implementation in the application source tree and replace all fictional bytes/IDs with validated protocol definitions. Keep the corresponding fixture tests.

## Presentation and Writes

Battery-only models need no UI fork: snapshots automatically feed the mouse page, connection capsule and widget. Unknown artwork falls back to the generic mouse symbol. Optional artwork mapping lives in `Shared/MouseSnapshot.swift`; include only assets you have redistribution rights for. The main G502 view and its physical button hotspots are model-specific and must not be reused for unrelated shapes.

Battery support does **not** enable onboard button mapping, DPI or RGB. Those operations currently remain G502-specific and require independent model validation, backup/read-back/rollback, explicit UI capability routing and hardware evidence. Do not expose another model through the G502 profile path.

## Acceptance Checklist

- Exact interface and firmware match; other interfaces and unsupported models are rejected.
- Valid 0%, intermediate and 100% readings; unknown, truncated, invalid and unrelated responses.
- Connected receiver with sleeping/off mouse does not look like a fresh successful battery read.
- Reconnect, unplug, sleep/wake and no repeated wake popups.
- Charging behavior verified separately; note third-party docks that do not report it.
- No input disruption, duplicate interface ownership, profile writes or unsolicited lighting changes.
- Fixtures and logs contain no serial numbers, user configuration or private backups.
- Default tests require no hardware. Record actual device checks separately, rather than claiming mock tests validate the physical device.

Also see [architecture](architecture.md), [build instructions](build.md) and [CONTRIBUTING](../CONTRIBUTING.md).
