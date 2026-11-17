# Chuu Updates

## Distribution

Chuu uses **Sparkle 2 + public GitHub Releases**. No GitHub login, token, private update server or GitHub Pages site is required by the installed app.

- Feed: `https://raw.githubusercontent.com/Imyukehan/Chuu/main/release/chuu-appcast.xml`.
- Downloads: immutable versioned GitHub Release ZIP URLs, never GitHub source archives or expiring asset redirects.
- App and embedded widget: Apple Silicon, Developer ID signed, hardened runtime enabled, notarized and stapled.
- Feed and archive: signed with Chuu's Ed25519 key. Only the public verification key is embedded in the app; the private key stays in the maintainer's login Keychain under account `moe.khan.MouseControl`.
- Automatic checks run every 12 hours while Chuu runs and can be disabled in **General**. Installation asks for confirmation. **Chuu > Check for Updates...** checks immediately.
- Existing settings, bundle IDs, widget kind and the paid-team App Group remain stable.

The initial 0.1.6 build (`20261117.1`) predates the feed. Install the newer signed bootstrap once to join the update channel. Subsequent updates are handled by Sparkle. Legacy ad-hoc packages are excluded from the feed.

## Preparing A Release

1. Change version/build in `project.yml`; use a new `YYYYMMDD.N` build for every artifact and regenerate with XcodeGen.
2. Run focused tests, review the diff and commit the app changes. Keep credentials, hardware backups, preferences and local audit reports out of Git.
3. Build and notarize using the local Keychain identities:

```sh
bash scripts/distribution/build-notarized.sh --preflight
bash scripts/distribution/build-notarized.sh
```

Preflight verifies the release repository, the **Developer ID Application** identity for team `7XZ82S4RRS`, Sparkle tools and notarization credentials. The default Keychain profile is `chuu-notary`; override it with `CHUU_NOTARY_PROFILE` if necessary.

The script archives arm64, exports Developer ID, submits to Apple, staples and verifies the ticket, checks Gatekeeper and produces a clean ZIP, archive signature and checksums under `build/distribution/<version>-<build>/`. Development builds and app-hosted tests retain Apple Development signing.

4. Review bilingual release notes. Create a **draft** release tagged `v<version>` and upload the notarized ZIP and SHA256SUMS. Never overwrite an existing published asset.
5. Generate and verify the signed feed, using the reviewed HTML notes:

```sh
python3 scripts/distribution/make_appcast.py \
  build/distribution/<version>-<build>/Chuu-<version>-<build>-arm64.zip \
  <reviewed-notes.html> build/chuu-appcast.xml
```

6. Review the feed and draft together. Copy the final signed feed to `release/chuu-appcast.xml`, commit it, and obtain approval to push code and the matching release tag. The user publishes the reviewed GitHub draft after branch/tag alignment. Coordinate feed publication with release publication so the feed does not point to an unavailable draft asset during normal use.
7. Verify the feed and ZIP anonymously, then use an older signed installation to check, download, verify, install and relaunch through Sparkle. Confirm the build advanced and settings survived.

None of the local distribution tools publishes or pushes automatically. The old upstream appcast and release scripts are historical; Chuu uses only `release/chuu-appcast.xml`.

## CI Test Packages

The [test-package workflow](ci-releases.md) is manual and produces diagnostic artifacts only. It does not publish releases or modify the signed feed, and its packaged app has the feed disabled. Apple and Sparkle private signing keys are not uploaded to CI by this workflow.

## References

- [Sparkle setup](https://sparkle-project.org/documentation/)
- [Publishing a Sparkle update](https://sparkle-project.org/documentation/publishing/)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
