# SKN QingNiao 75: Receiver Battery Investigation

Tested on 2026-11-15 with the owner's connected keyboard in 2.4 GHz mode.
The investigation queried device information only. No settings, lighting,
keymaps, pairing or firmware were changed. No battery adapter is registered.

## Device Identity

| Item | Observed value |
| --- | --- |
| USB manufacturer | SKN |
| Receiver product string | `Wireless Link ` (HID string includes a trailing space) |
| Receiver VID:PID | `362D:D101` |
| Raw HID interface | Usage page `FF60`, usage `61`, 32-byte input/output, report ID 0 |
| Paired keyboard VID:PID | `362D:1310`, returned by command `01` |
| Official definition | `QingNiao 75 ANSI Knob`, vendorProductId `908923664` |
| Keyboard firmware | `v1.0.3 2024-08-21-10:10:06` |
| Receiver firmware | `1.3.0 Jun 12 2024 15:54:25` |

The receiver also exposes mouse and keyboard input interfaces. Before Chuu
0.1.5, its mouse interface was mistaken for a generic mouse and marked online
solely because the USB receiver was present. Chuu 0.1.5 filters this receiver
from generic mouse discovery by exact VID:PID and known receiver names.
A future keyboard implementation should use its own device model and only
display a battery percentage after a valid query has been established.

## Observed Responses

Requests and responses are 32 bytes, zero-padded. Prefixes below omit padding.

| Request | Response prefix / meaning |
| --- | --- |
| `01` | `01 00 0C 36 2D 13 10 01 03` (VIA 12 and paired device identity) |
| `A0` | `A0 00 01 00` (legacy extension response; do not parse as modern feature support) |
| `A1` | `A1` followed by the keyboard firmware string |
| `A2` | `FF 00` (unsupported) |
| `B1` | `B1 01 00 00` (receiver version response) |
| `B2` | `B2 01 2D 36 00 00 01` (legacy receiver state; differs from newer slot layouts) |
| `B3` | `B3` followed by the receiver firmware string |
| `A7 01` | `FF 01` (misc protocol query unsupported) |
| `A7 0B` | `FF 0B` (sleep settings query unsupported) |

These responses establish working host-to-keyboard communication through the
receiver, but provide no battery percentage. The tested standard descriptors
also contain no battery-strength usage.

The `008C:0001` interface uses numbered reports (input `B1`, output `B2`,
plus feature reports). Sending an unnumbered report there produced no reply;
that is a transport mismatch, not evidence that this interface lacks battery
support. Its reports must not be guessed or confused with Raw HID commands.

## Source Checks

- [Official SKN Launcher](https://launcher.skn.net.cn/).
- [Official QingNiao 75 definition](https://launcher.keychron.com/static/device/908923664/json/v3.json).
- Tested Launcher bundle: `main.34acd3b74730c9c0.js`.
  Its ordinary keyboard implementation has no battery query/parser. Its
  trackball implementation has `A7 31` battery queries, but applicability to
  this keyboard has not been established; these were not sent.
- [Keychron firmware dispatcher](https://github.com/Keychron/qmk_firmware/blob/wireless_playground/keyboards/keychron/common/keychron_raw_hid.c)
  documents the read-only core and misc command families, but is not the
  identified SKN firmware's source.

The community Keychron-Vial wireless document mentions keyboard battery in
the sleep response. The official Launcher code inspected here parses only
timeouts there, and this firmware rejects that query. Do not build an adapter
around that claim. The fork's custom `AC` battery command is also absent from
stock firmware and conflicts with the official screen command.

## Reproduce and Continue

Inventory only:

```sh
swift tools/skn_receiver_probe.swift
```

With the owner's consent and the same receiver connected, run the fixed
read-only query list:

```sh
swift tools/skn_receiver_probe.swift --query
```

Next useful evidence: an official battery command for this firmware, a
vendor-provided protocol specification, or an observed battery query from a
compatible vendor utility. Investigate a documented numbered-report battery
query if one exists. Bluetooth battery reporting can be tested separately;
do not automatically switch connection modes or flash firmware for this probe.

## Follow-up Source Research (2026-11-15)

Current conclusion: no usable stock-firmware battery query has been identified
for this QingNiao 75 over its 2.4 GHz receiver. Treat this mode as unsupported
for battery telemetry. The exact SKN firmware source was not located; the
evidence below comes from related firmware and independently implemented
tools, together with the device responses above.

### Internal Battery Measurement Versus Host Reporting

Keychron's official wireless firmware contains `battery_measure()`,
`battery_get_voltage()` and `battery_get_percentage()`. Its default measurement
asks the LKBT51 radio module for state registers. This is an internal
MCU-to-radio operation, not a USB command that an application can send.
The related raw-HID dispatcher exposes protocol, version, features, layer and
settings commands, but no battery read. That explains how the keyboard can
display charge on its LEDs without providing an application-readable value.

Sources pinned to official revision `666862cb8123b64a6b96718d739c6203ad99031f`:

- [Internal battery implementation](https://github.com/Keychron/qmk_firmware/blob/666862cb8123b64a6b96718d739c6203ad99031f/keyboards/keychron/common/wireless/battery.c).
- [Host command dispatcher](https://github.com/Keychron/qmk_firmware/blob/666862cb8123b64a6b96718d739c6203ad99031f/keyboards/keychron/common/keychron_raw_hid.c).

### Community Implementations

- [InputScout K8 HE investigation](https://github.com/SPDG/inputscout/blob/main/docs/protocols/k8-he-wired.md):
  stock v1.1.1 exposes firmware and configuration telemetry, but no battery
  percentage over the known USB or receiver path. Its internal `BAT_LVL`
  action controls LEDs rather than returning a value to the host.
- [Keyboard Companion requirements](https://github.com/OutersGIT/keyboard-companion#requirements):
  USB/receiver battery support requires modified K10 HE or Q1 HE firmware.
  The [actual K10 HE patch](https://github.com/OutersGIT/k10he-battery-firmware/blob/171323703cb92ac6278eab4eb9a565baa4fc0749/patches/0001-k10he-battery-raw-hid.patch)
  adds `KC_GET_BATTERY = 0xA4` and periodically pushes percentage, voltage,
  charging state and transport through wireless Raw HID. `A4` is therefore
  an extension to that firmware, not an established stock SKN command.
- [Keychron Battery Monitor Q6 Ultra limitation](https://github.com/JGussey/keychron-battery-monitor#q6-ultra-24-ghz-limitation):
  its Q6 Ultra receiver reports connection, while keyboard battery comes from
  Bluetooth. Its receiver battery implementation is for the G5 mouse.

### Rejected Positive Claim

`dolfbarr/keychron-battery` advertises Max-series keyboard battery support,
but at revision `5052b65fe0a240835fb6bdf2e93a262a5d8f61ce` its
[MaxSeriesDriver.ProbeBattery](https://github.com/dolfbarr/keychron-battery/blob/5052b65fe0a240835fb6bdf2e93a262a5d8f61ce/internal/drivers/max_series.go)
simply returns `100, true, true`. It does not query the keyboard.
Its [receiver carrier probe](https://github.com/dolfbarr/keychron-battery/blob/5052b65fe0a240835fb6bdf2e93a262a5d8f61ce/internal/dongles/keychron_link.go)
also returns a fixed full-strength result on failure. Neither is evidence
of a working battery protocol and neither should be ported into Chuu.

No additional hardware commands or firmware updates were performed for this
follow-up. A usable next step requires exact-model source or vendor protocol
information. Firmware for another Keychron/Lemokey board is not a QingNiao 75
replacement. Bluetooth battery support remains a separate device-mode test.
