# Automated Test Packages

`.github/workflows/test-release.yml` builds **unnotarized, ad-hoc-signed test packages**, not stable or notarized releases. It needs no signing secrets. This workflow is separate from the inherited Mos release scripts and never updates an appcast.

## Version Tags

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in `project.yml`. Regenerate the project and add a changelog entry.
2. Commit and push the changes. Create an annotated `vMAJOR.MINOR.PATCH` tag on that commit and push the tag.
3. Actions checks out that exact tag, builds an Apple Silicon / Intel universal Release app, verifies both bundle versions, architectures and code signatures, then packages a ZIP with license, notices and installation notes.
4. On success, a GitHub **prerelease** is created with the ZIP, SHA256SUMS and build metadata. It is not marked as the latest stable release.

Example for a future version (do not move an existing tag):

```sh
git tag -a v0.1.2 -m 'Chuu 0.1.2'
git push origin v0.1.2
```

The tag must match the built app's version, and the widget must match both app version and build number. Failed builds do not publish a release. Existing releases and assets are never overwritten; use a new version for corrections. An existing source-only tag can receive its first package through the manual workflow below.

## Manual Run

In GitHub **Actions > Build Test Release > Run workflow**, select `main`, enter an existing version tag and choose whether to publish. With **publish off** (the default), the verified ZIP is available only as an Actions artifact for 14 days. With **publish on**, it also creates a new GitHub prerelease. Build logs are retained for 7 days.

The packaging tools come from the selected workflow revision; application source always comes from the specified tag. This permits packaging a tag that predates the workflow. `build-info.json` records the exact application commit. The publisher checks that the tag has not moved since the build.

## Security And Limitations

- Uses the GitHub-hosted [`xcode-27` runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), because Chuu currently references macOS 27 SDK APIs. The runner is currently a public preview; availability or SDK changes can require workflow maintenance.
- Build jobs have read-only repository access. Only the separate publisher has `contents: write`; it runs on this repository, not forks. Third-party actions are pinned to commit hashes. There are no pull-request or `pull_request_target` release triggers.
- The workflow uses only the built-in `GITHUB_TOKEN`; it does not read Apple credentials, import certificates or alter signing keys.
- No local vendor artwork, hardware-profile backups or user settings are included. The packaging script rejects ignored artwork in a development checkout.
- Ad-hoc signatures are not Developer ID signatures. macOS may block first launch, and Accessibility permission may need to be granted again. Do not disable Gatekeeper globally.
- WidgetKit is included, but App Group sharing and widget operation are not validated with this signing mode. Keep a normally signed local build if you depend on the widget.
- The script builds and inspects an isolated bundle; it does not launch it or replace an installed Chuu. It does not run hardware tests or unsigned/ad-hoc app-hosted tests.
- Checksums cover archive integrity, not developer identity. Public distribution signing and notarization are a separate future step; see [updates](updates.md).

## Local Validation

```sh
bash -n scripts/ci/package-test-build.sh
python3 -B -m unittest discover -s scripts/ci -p '*_tests.py'
```

The full packaging script takes a **clean clone checked out at an existing tag**, that tag, and an output directory outside the clone:

```sh
bash scripts/ci/package-test-build.sh /path/to/clean-checkout v0.1.1 /tmp/chuu-test-package
```

It requires Xcode 27+, XcodeGen and Python 3. Do not run it against the main local development checkout containing optional private artwork.
