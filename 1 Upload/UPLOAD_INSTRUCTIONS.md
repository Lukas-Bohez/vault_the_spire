# TorrentSpire AI Release Upload Instructions

## Files prepared in this folder
- `torrent_spire_ai-v3.0.1+1-release.aab`
- `torrent_spire_ai-windows-v3.0.1+1-release.zip`
- `SHA256SUMS.txt`

## Google Play Console (AAB)
1. Open your app in Play Console.
2. Go to `Testing` or `Production` release track.
3. Create a new release.
4. Upload `torrent_spire_ai-v3.0.1+1-release.aab`.
5. Copy release notes from `CHANGELOG.md` (v3.0.1 section) into Play release notes.
6. Complete Data Safety and App Content declarations using `DATA_SAFETY.md` and `PRIVACY_POLICY.md`.
7. Review pre-launch report, then roll out.

## GitHub Release (Desktop)
1. Create a GitHub release tag for `v3.0.1`.
2. Upload `torrent_spire_ai-windows-v3.0.1+1-release.zip`.
3. Upload `SHA256SUMS.txt` for integrity verification.
4. Paste release notes from `CHANGELOG.md`.

## Integrity check
Use SHA-256 hashes from `SHA256SUMS.txt` after upload to verify downloaded files are unchanged.
