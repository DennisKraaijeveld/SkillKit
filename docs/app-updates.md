# SkillKit app updates

SkillKit uses Sparkle 2 for signed in-app updates. App updates are intentionally separate from skill-package updates:

- **SkillKit > Check for Updates** opens Sparkle's standard update flow.
- **Settings > Updates** shows the installed version and controls automatic checks and downloads.
- The workspace toolbar shows an update icon only when an app update is available, downloading, ready to install, or has failed.
- A downloaded update changes the toolbar action to **Restart to Update**.

Unsigned local builds leave `SPARKLE_PUBLIC_ED_KEY` empty. The Updates pane reports that app updates are unavailable in that build instead of requesting an unsigned feed.

## One-time release setup

Download the same Sparkle version pinned in `macos/project.yml`, generate a dedicated Ed25519 key, and export its private seed:

```bash
curl -fsSLO https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz
tar -xJf Sparkle-2.9.4.tar.xz
./bin/generate_keys --account skillkit
./bin/generate_keys --account skillkit -x skillkit-sparkle-private-key
```

Keep the exported private key outside the repository. Add its complete base64 contents as the `SPARKLE_PRIVATE_KEY` Actions secret, then remove the exported file after storing it in the team's secret manager. The release workflow derives the matching public key and embeds it in the signed app, so the two values cannot drift.

Export the **Developer ID Application** certificate and private key from Keychain Access as a password-protected `.p12`. Configure these GitHub Actions secrets:

| Name | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password used to export the `.p12` |
| `KEYCHAIN_PASSWORD` | Throwaway password for the CI keychain |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `SPARKLE_PRIVATE_KEY` | Base64 private seed exported by `generate_keys` |

The app verifies the archive before extraction and also requires a signed appcast. Losing the Sparkle private key prevents publishing updates accepted by existing installations, so back it up independently of GitHub.

## Publish a release

Create and push a stable semantic-version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow derives the internal bundle build as `(major + 1).minor.patch` from the tag. The offset keeps tag-derived builds newer than the legacy `0.1.0` and `0.1.1` artifacts, which both used build `1`. Sparkle compares this internal build number, not the user-facing version, when deciding whether an update is newer.

`.github/workflows/release.yml` then:

1. Builds a universal arm64/x86_64 Release archive.
2. Signs the app and bundled MCP helper with Developer ID.
3. Submits the app to Apple's notarization service and staples the ticket.
4. Creates `SkillKit-VERSION.dmg`, signs it with Developer ID, and notarizes and staples the disk image separately.
5. Creates `SkillKit-VERSION.zip` and signs it with the Sparkle key.
6. Generates a signed `appcast.xml` with embedded release notes.
7. Publishes the DMG, Sparkle ZIP, and appcast to the tagged GitHub release.

The DMG is the manual download to share on the website and social channels. Sparkle continues to use the ZIP so adding the DMG does not create a second update item in the appcast.

Installed apps read the feed from:

```text
https://github.com/DennisKraaijeveld/SkillKit/releases/latest/download/appcast.xml
```

The workflow accepts only tags shaped like `vMAJOR.MINOR.PATCH`. Do not publish a GitHub release manually from the same tag before the workflow unless you intend the workflow to replace its release assets and notes.
