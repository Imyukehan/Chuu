# Manual CI Test Packages

The normal installation is a signed, notarized GitHub Release distributed through [Sparkle](updates.md). `.github/workflows/test-release.yml` is a separate **manual** diagnostic workflow for unnotarized ad-hoc packages. It never creates a release and never updates the appcast.

## Running

In **Actions > Build Test Release > Run workflow**, select `main` and enter an existing `vMAJOR.MINOR.PATCH` tag. The workflow checks out that exact tag, builds arm64, validates app/widget versions and artwork, and uploads a ZIP, checksums and metadata as an artifact retained for 14 days. Build logs are retained for 7 days. Existing source archives and release assets are unchanged.

The release tag must match the marketing version, and app/widget build numbers must match. Packaging tools come from the selected workflow revision; source comes from the requested tag.

## Boundaries

- Uses the `xcode-27` Apple Silicon runner required by Chuu's current SDK APIs. Third-party actions remain pinned to commits.
- Repository access is read-only. No Apple credentials, Developer ID private keys or Sparkle private keys are imported into CI.
- Produces arm64 only; these artifacts do not support Intel Macs.
- Removes `SUFeedURL` and disables automatic checks before re-signing the host app ad hoc. Diagnostic artifacts cannot enter the signed distribution update channel.
- Disables hardened-runtime library validation only in this isolated ad-hoc build. Normal local and distribution builds retain hardened runtime.
- Widget sharing requires a valid team signature and matching App Group, so use a notarized distribution when the widget is essential.
- The startup smoke test runs only on a disposable CI runner and rejects early exit. It does not exercise real hardware, input permissions or widget UI.
- User preferences and hardware backups are excluded from the package. Source credits and artwork ownership notices remain in NOTICES.md.

## Local Validation

```sh
bash -n scripts/ci/package-test-build.sh
python3 -B -m unittest discover -s scripts/ci -p '*_tests.py'
bash scripts/qa/test-snapshot-storage.sh
```

For a full diagnostic package, use a clean checkout at an existing tag:

```sh
bash scripts/ci/package-test-build.sh /path/to/clean-checkout v0.1.7 /tmp/chuu-test-package
```

Local packaging does not launch the ad-hoc app or replace the installed signed app. Signing, notarization and the real update channel use `scripts/distribution/` instead.
