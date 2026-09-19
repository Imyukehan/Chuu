# Contributing to Chuu

Bug fixes, device adapters, tests, localization and focused UI improvements are welcome. The maintainer owns only a few mice; community-tested hardware support is especially valuable.

Read the [build guide](docs/build.md) and [architecture](docs/architecture.md). Use `Chuu.xcodeproj`, the `Chuu` scheme and the `ChuuTests` target. Edit `project.yml` for build changes, then regenerate the project with XcodeGen.

## Mouse Support

Follow the [adapter guide](docs/mouse-adapters.md). Start with battery reading only. Keep brand/model protocol details in `Chuu/Devices/<Vendor>/` and register exact HID interfaces. Do not enable writes by copying another model's offsets or merely matching a vendor ID.

A hardware PR should include:

- Exact mouse and receiver model, firmware, macOS version and connection mode.
- VID, PID, usage page and usage for the protocol interface.
- Sanitized request/response fixtures and parser tests for normal, malformed and missing responses.
- What was verified on a physical device, including unplug/replug, sleep and battery/charging behavior.
- Separate evidence for every claimed feature; battery support does not establish RGB or onboard-write support.
- Provenance and redistribution permission for optional artwork; generic artwork is fine.

Never include serial numbers, personal settings, hardware-profile backups, private keys or raw vendor-owned image sets. The example protocol is fictional and must not be sent to hardware.

## Validation

Stop Chuu before app-hosted tests. Use normal development signing, never `CODE_SIGNING_ALLOWED=NO` for tests.

```sh
xcodebuild -project Chuu.xcodeproj -scheme Chuu \
  -destination 'platform=macOS' -derivedDataPath build/Chuu test
scripts/qa/lint-logi-boundary.sh
git diff --check
```

Hardware-dependent tests skip unless explicitly enabled with `LOGI_REAL_DEVICE=1`. Do not enable them on someone else's machine without their consent. Explain remaining manual checks in your PR. Preserve existing settings, snapshot IDs, widget identity and shortcuts.

Report Chuu issues at [Imyukehan/Chuu](https://github.com/Imyukehan/Chuu/issues), not the upstream Mos issue tracker. Include reproducible steps, expected/actual behavior and relevant versions; redact personal information from logs.

## License

Contributions remain under this project's [CC BY-NC 4.0 license](LICENSE). Preserve Caldis/Mos attribution. Chuu is noncommercial and not an official product of any hardware vendor.
