# Releasing

[← README](../README.md) · [Development](development.md) · [Testing](testing.md) · [Architecture](architecture.md) · **Releasing**

**Release with the `release` skill**, in [Claude Code](https://claude.com/claude-code) at the root of this repo:

```
/release 2.10.0
```

It asks for two things up front, the version and the notes (the in-app "What's New" highlights and the GitHub release notes), then does the rest: writes the changelog and Flatpak metainfo entries, checks both version gates, runs the tests, publishes the GitHub release, and watches the pipeline. If a build fails, it deletes the release and tag, fixes the cause, and tries again. The steps are in [`.claude/skills/release/SKILL.md`](../.claude/skills/release/SKILL.md).

Don't release by hand by tagging and pushing. **A bare tag fails the release**: every build job uploads to a GitHub release that has to exist already, so the release is created first (`gh release create`), and creating it is what pushes the tag.

## What CI checks and builds

Before building, the `Unit Tests` job fails the run unless the tag matches **both**:

- the newest entry in `assets/changelog/changelog.json` (bundled, because the Flatpak build has no network);
- the newest `<release>` in `flatpak/com.bandpassrecords.dpm.metainfo.xml` (Flathub's changelog, and the Flatpak build's version).

`pubspec.yaml` stays at `0.0.0+0`: CI stamps the version from the tag.

Then, in about 15 minutes, it attaches to the release:

| Windows | macOS | Linux | Android |
|---|---|---|---|
| installer `.exe`, `.msix` | `.dmg`, `.zip` | AppImage, `.tar.gz`, Flatpak | `.aab` |

…runs an iOS compile check, and points the website's download buttons at the new files. Flathub picks the new tag up by itself (its bot opens the PR).

Repository secrets it needs (Settings → Secrets and variables → Actions):

| For | Secrets |
|---|---|
| Google Drive sign-in (every build but Flatpak) | `DESKTOP_CLIENT_ID`, `DESKTOP_CLIENT_SECRET`, `ANDROID_WEB_CLIENT_ID` — see [Development setup](development.md#google-drive-sign-in-optional) |
| Android signing | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` |
| macOS signing and notarization | `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_DEVELOPER_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` — how to get each: [`.github/SIGNING_SETUP.md`](../.github/SIGNING_SETUP.md) |

Flatpak specifics: [`flatpak/README.md`](../flatpak/README.md).
