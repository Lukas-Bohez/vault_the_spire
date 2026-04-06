# Master Prompt: Final QOL + Stable Release (TorrentSpire AI 4.1.0)

You are working inside the Flutter project `torrent_spire_ai`.

## Mission
Ship a polished and reliable QOL release with:
- robust torrent UX (search, sort, tap-to-open details),
- accurate progress state after redownload/reset,
- Android-safe folder behavior,
- truthful status/progress reporting,
- no analyzer errors,
- release artifacts prepared in `1 Upload/`.

## Ground Rules
- Preserve existing architecture and service boundaries.
- Do not introduce breaking route or model changes unless required.
- Keep edits focused and minimal; avoid unrelated refactors.
- Fix root causes, not symptoms.
- Verify with `flutter analyze` and only stop when clean.

## Required Outcomes
1. Torrents list UX:
- Search bar toggle with live name filtering.
- Sort popup with clear active selection.
- Persist selected sort mode via `SettingsService.torrentSortMode`.
- Tappable torrent cards that navigate to detail screen.
- "No results" state when search yields none.

2. Android folder-open crash prevention:
- Never trigger `Uri.file(...)` open flow on Android for file-explorer actions.
- Show safe fallback (snackbar with path) on Android.
- Keep desktop folder-open behavior intact.

3. Progress truthfulness after redownload/reset:
- Ensure disk snapshot and runtime caches are both invalidated on reset paths.
- Prevent stale disk snapshot bytes from reporting 100% immediately after explicit reset.
- Keep progress merges consistent with runtime + DB + disk state.

4. Redownload behavior:
- `forceRedownload` must fully stop the torrent first.
- Remove downloaded content (except source metadata files required for restart).
- Restart cleanly from 0% without instant false seeding.

5. Detail screen readability:
- Human-readable byte sizes and rates.
- Keep key controls visible: refresh, redownload, logs.

6. Versioning and release:
- `pubspec.yaml` version must match release intent (`4.1.0+1`).
- About screen app version label must match marketing version (`4.1.0`).
- Build release artifacts and place expected outputs in `1 Upload/`.

7. Repository hygiene:
- Identify obsolete files/modules no longer referenced.
- Delete only files confirmed unused by import/reference checks.
- Re-run analysis after deletion.

## Verification Checklist
Run and pass:
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test` (if feasible in environment)
4. `flutter build apk --release --split-per-abi`
5. `flutter build windows --release`

Then confirm:
- APK(s) and Windows package exist in `1 Upload/`.
- Any removed files are truly unreferenced.
- No new analyzer warnings/errors introduced.

## Reporting Format
At the end, report:
1. Files changed.
2. Root-cause fixes implemented.
3. Validation results (commands + outcomes).
4. Release artifacts generated.
5. Files deleted as obsolete and why they were safe to remove.
