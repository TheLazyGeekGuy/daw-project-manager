# Releasing

[← README](../README.md) · [Development](development.md) · [Testing](testing.md) · [Architecture](architecture.md) · **Releasing**

1. Add the version to the in-app changelog (shown as "What's New"):
   ```bash
   python scripts/new_changelog_entry.py 2.10.0 --highlight "…" --highlight "…"
   ```
2. Tag and push:
   ```bash
   git tag v2.10.0 && git push bp v2.10.0
   ```

CI then builds and attaches to the release:

| Windows | macOS | Linux | Android |
|---|---|---|---|
| installer `.exe`, `.msix` | `.dmg`, `.zip` | AppImage, `.tar.gz`, Flatpak | `.aab` |

…and points the website's download buttons at them. It fails if the newest changelog entry doesn't match the tag.

Repository secrets it needs: `DESKTOP_CLIENT_ID`, `DESKTOP_CLIENT_SECRET`, `ANDROID_WEB_CLIENT_ID`, plus the signing ones in [`.github/SIGNING_SETUP.md`](../.github/SIGNING_SETUP.md). Flatpak specifics: [`flatpak/README.md`](../flatpak/README.md).
