# Chuu Agent Guide

Chuu is a noncommercial fork of Caldis/Mos. Preserve the CC BY-NC 4.0 license, upstream attribution and history. Current build requirements are macOS 14+ and Xcode 27.1. Historical upstream plans, website, release scripts and translations are not current Chuu instructions.

## Start Here

1. Read this file and `.agents/INDEX.md`.
2. Check `git status --short`; preserve unrelated changes.
3. Read only relevant source, tests and topic documents.

Current user/system instructions take precedence, then this file, topic guides and active source. Keep tool-specific instruction files as links to this guide rather than duplicate rules.

## Build and Test

`project.yml` is the source of truth. Use `Chuu.xcodeproj`, targets `Chuu`, `ChuuWidget`, `ChuuTests`, and the shared `Chuu` scheme. Regenerate with XcodeGen after adding or moving files. `Examples/MouseAdapter/ExampleMouseAdapter.swift` is test-only.

```sh
./script/build_and_run.sh --build
xcodebuild -project Chuu.xcodeproj -scheme Chuu \
  -destination 'platform=macOS' -derivedDataPath build/Chuu test
scripts/qa/lint-logi-boundary.sh
git diff --check
```

Stop this app's `MouseControl` process before app-hosted tests. Keep normal Apple Development signing. **Never use `CODE_SIGNING_ALLOWED=NO` for tests**: changing identity can trigger TCC prompts while an input tap is active. The normal scheme disables hardware tests. `ChuuHardwareTests` enables `LOGI_REAL_DEVICE=1` and requires explicit user consent and connected hardware.

See `docs/build.md` for signing and installation. `--install` retains one rollback bundle and does not erase preferences. Do not change signing identity or entitlement values as part of a source rename.

## Boundaries

- Battery adapters live in `Chuu/Devices/<Vendor>/`, registered through `MouseAdapterRegistry`; read `docs/mouse-adapters.md` before extending support. Do not guess hardware-write commands or expose another model through the G502 profile path.
- The inherited Logi engine lives in `Chuu/Logi`, with app integration in `Chuu/Integration`. Run the boundary lint for related changes.
- Keep high-frequency input paths free of extra allocations, synchronous I/O and logging.
- UI strings use `NSLocalizedString`. Shared Chuu strings are in `Shared/Chuu.xcstrings`; upstream UI catalogs remain separate.
- Preserve bundle IDs, executable name, App Group, widget kind, snapshot model/device IDs, URL scheme, settings keys and shortcut identifiers. These are compatibility contracts, documented in `docs/architecture.md`, not branding to replace globally.
- Never publish local vendor-owned renders, private keys, user preferences, hardware backups or migration data.

## Verification

Scale verification to risk. New logic needs regression tests; file/target changes need a build; cross-module changes need broader tests. Check the actual window after UI or storyboard/module changes. Report what ran and what remains unverified, not hypothetical release risks unrelated to the task.

For release/notarization work read `.agents/skills/release-preparation/SKILL.md`, but reconcile inherited upstream commands against the current Chuu project first. Public push/release, signing changes, real-device tests and changes to persisted data require explicit user authorization. Community maintenance work uses `.agents/skills/community-pr-loop/SKILL.md`; do not act against upstream's tracker on Chuu's behalf.

## References

- `.agents/docs/code-map.md`, `.agents/docs/testing.md`, `.agents/docs/quality-gates.md`
- `docs/architecture.md`, `docs/mouse-adapters.md`, `docs/build.md`
- `CONTRIBUTING.md`, `LOCALIZATION.md`
