# Chuu Updates

## Current State

Chuu includes Sparkle 2 and a native **Chuu > Check for Updates...** command, also available from the status-item menu. The development app does not yet have a Chuu update feed or public update-signing key. Checking manually shows that state and offers the project's [GitHub Releases](https://github.com/Imyukehan/Chuu/releases) page; it does not claim the installed version is current.

Automatic checks remain inactive until both `SUFeedURL` (HTTPS) and `SUPublicEDKey` (a 32-byte Ed25519 public key in Base64) are configured. Inherited upstream feeds are rejected. Never reuse Mos release artifacts, signing keys or feeds for Chuu.

## Recommended Distribution

Use **Sparkle 2 + GitHub Releases + GitHub Pages**:

- GitHub Releases hosts versioned, signed and notarized Chuu app archives, such as ZIP or DMG. GitHub's automatically generated source archives are not app updates.
- GitHub Pages hosts an `appcast.xml` describing versions, minimum OS versions, download URLs, signatures and release notes.
- Sparkle checks the appcast, presents available updates, verifies downloads, installs and relaunches. No custom update server is required.

The repository's inherited `release/`, website and workflow files are upstream history, not an active Chuu publishing pipeline. Review their destinations before adopting any of them.

## First Release Checklist

1. Keep Chuu's installed app/widget identifiers and App Group stable. Increment `CFBundleVersion` for each release and set a user-facing `CFBundleShortVersionString`.
2. Build the app and embedded widget with the appropriate distribution entitlements, Developer ID signing and notarization. The local Apple Development build is not the public distribution artifact.
3. Generate Chuu's own Sparkle EdDSA key pair. Protect and back up the private key outside the repository; embed only the public key as `SUPublicEDKey`.
4. Use Sparkle's `generate_appcast` to sign archives and create the feed, using immutable versioned GitHub Release asset URLs. Set `SUFeedURL` to the actual HTTPS Chuu appcast location, not a placeholder.
5. Publish the assets before publishing an appcast that references them. Keep release notes and version/OS constraints accurate.
6. Verify an actual older signed installation updating to a newer release. Confirm signature rejection, app relaunch, preserved preferences, input permissions and widget behavior before calling in-app updates ready.

The menu/configuration tests do not replace this final install-and-update test. Feed hosting, distribution signing and release automation are intentionally not provisioned by the menu change.

## References

- [Sparkle setup](https://sparkle-project.org/documentation/)
- [Publishing a Sparkle update](https://sparkle-project.org/documentation/publishing/)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
