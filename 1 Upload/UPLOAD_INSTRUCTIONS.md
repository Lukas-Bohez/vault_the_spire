# TorrentSpire AI Release Upload Instructions

## Files prepared in this folder
- `torrent_spire_ai-v3.0.1+2-release.aab`
- `torrent_spire_ai-v3.0.1+2-release.apk`
- `torrent_spire_ai-windows-v3.0.1+2-release.zip`
- `SHA256SUMS.txt`

## Google Play Console (AAB)
1. Open your app in Play Console.
2. Go to `Testing` or `Production` release track.
3. Create a new release.
4. Upload `torrent_spire_ai-v3.0.1+2-release.aab`.
5. Optionally upload `torrent_spire_ai-v3.0.1+2-release.apk` to internal testing if you need a direct-install artifact.
6. Copy release notes from `CHANGELOG.md` (v3.0.1 section) into Play release notes.
7. Complete Data Safety and App Content declarations using `DATA_SAFETY.md` and `PRIVACY_POLICY.md`.
8. Review pre-launch report, then roll out.

## GitHub Release (Desktop)
1. Create a GitHub release tag for `v3.0.1`.
2. Upload `torrent_spire_ai-windows-v3.0.1+2-release.zip`.
3. Upload `torrent_spire_ai-v3.0.1+2-release.apk` if you want a direct Android install artifact attached to the release.
4. Upload `SHA256SUMS.txt` for integrity verification.
5. Paste release notes from `CHANGELOG.md`.

## Integrity check
Use SHA-256 hashes from `SHA256SUMS.txt` after upload to verify downloaded files are unchanged.
