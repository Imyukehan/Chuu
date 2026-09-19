# Copilot Instructions for Chuu

Read `@../AGENTS.md` first. This file is intentionally thin so Copilot, Codex, Claude, and other agents share one source of truth.

For reviews and generated changes, pay special attention to:

- macOS 14 compatibility and availability fallbacks.
- `Chuu` scheme build/test commands in `Chuu.xcodeproj`.
- Xcode target membership for new or moved Swift files.
- `NSLocalizedString(_:comment:)` and the two separate `.xcstrings` catalogs.
- `Chuu/Logi` / `Chuu/Integration` boundaries and `scripts/qa/lint-logi-boundary.sh`.
- Regression tests for bug fixes and clear verification evidence before claiming success.
- Human confirmation before release, signing, notarization, security-report, or real-device actions.
