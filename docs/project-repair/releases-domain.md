# Native DPM music catalog, rights, distribution and communication

Status: **initial pure Dart domain models and tests**. No Katsu connector or Suno-specific behavior is implemented. Existing DPM `Release`, `ReleaseFile` and `TodoItem` remain unchanged, so no Hive migration or generated adapter update is necessary for these first models.

## Key domain distinctions

- **Artist**: stable ID and name; credits connect an artist to a recording.
- **Musical work**: underlying composition with rightsholders and optional ISWC.
- **Recording**: independent track with optional ISRC, origin/lineage, DAW project link.
- **Album/EP/single/compilation**: ordered track collection and potential UPC/EAN.
- **Playlist**: independently ordered selection, not a released album by definition.
- **Assets**: master, mix, preview, stem, cover, lyrics, MIDI and documents; maintain associations and validation state.
- **Rights filing**: work + organization (SACEM, BMI, PRS or another authority), evidence, status. Submission does not equal acceptance.
- **Distributor delivery**: distributor release and separate platform-specific delivery statuses (Spotify, Apple Music, etc.). Delivery is not proof of public availability.
- **Communication plan**: posts and assets for a track or whole release, schedule, publication status and missing-coverage reporting.

## Concepts researched from a separate music archiving application

Katsu's architectural concepts suggested immutable identities, lossless-master precedence, separation of original data from user metadata, relationship/lineage tracking, versioned assets, release stage tracking, rights evidence, and communication coverage. **No Katsu source code or provider-specific authentication is copied into DPM.**

## Next integration gates

1. Design persistent repositories and profile-scoped migrations, respecting existing Release and MusicProject relationships.
2. Add native Releases subviews for Albums, Artists, Playlists, Rights, Distribution and Communication.
3. Add metadata forms, credit allocation, evidence attachments and status histories with explicit reviewer confirmation.
4. Test data migration, backward compatibility and UI localization.
5. Keep external distributor/rights platforms manual until explicitly authenticated integrations exist, with audit logs and no invented publication success.

All comments and documentation are in English. No unsupported external API automation or publication action is implied.
