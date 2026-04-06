# Master Prompt: Stability + Mobile Torrent Features (2026-04-06)

You are working inside the Flutter project torrent_spire_ai.

## Mission
Deliver a reliability and UX hardening pass that fixes torrent data integrity/runtime stability issues and makes core torrent actions fully accessible on mobile.

## Priority Order
1. Remove safe redundant generated artifacts first.
2. Fix crash-class issues and corrupted-download causes.
3. Fix file presence validation and status truthfulness.
4. Fix file picker/folder explorer instability.
5. Ensure mobile users can add and create torrents from the Torrents screen.
6. Apply additional user-facing quality improvements found during implementation.

## Mandatory Problems To Fix

### A) Stream close race crashes
- Fix uncaught Bad state: Cannot add event after closing in dtorrent_task_v2 write/state flows.
- Patch all relevant queue/add callsites so updates become no-ops (or safe false returns) after close.
- Ensure no dead Futures are left waiting when enqueue fails.

### B) File presence truth and torrent list correctness
- When building torrent list/status, do not trust stale DB/runtime bytes if files are missing on disk.
- Detect missing paths and represent a user-visible missing-files state.
- Keep pending metadata behavior non-fatal and separate from missing-file errors.

### C) Explorer/picker lockup and startup IO pressure
- Remove or reduce heavy recursive disk scans that can lock/stall Windows explorer.
- Prefer targeted scan strategy:
  - exact torrent directory/file match first,
  - shallow candidate fallback second,
  - avoid broad recursive scans over whole download roots when unnecessary.
- Serialize picker operations per screen to avoid concurrent picker calls.
- Use native Windows explorer launch behavior when opening folders.

### D) Mobile action parity
- On mobile (Android + iOS), Torrents screen must expose:
  - add magnet link,
  - add .torrent file,
  - create torrent.
- Actions must be reachable from the main Torrents UI without desktop-only affordances.

### E) Download usability and integrity
- Make new torrents default to sequential mode so partially downloaded media becomes usable earlier.
- Keep write/flush code robust against disposal races so piece state does not desync and corrupt output.

## Additional Improvements To Include
- Improve user-facing status labels/messages for missing files and file-in-use errors.
- Ensure folder open actions fail gracefully with clear feedback.
- Keep all changes backward compatible with existing routes/models.

## Cleanup Rules
- Delete only redundant generated artifacts (build outputs, temporary coverage outputs, other regenerable files).
- Do not delete source, assets, docs, or tests unless proven unused and approved.
- If a file cannot be removed because another process holds a lock, report it explicitly.

## Validation Checklist (Required)
1. flutter analyze
2. Targeted torrent tests (at minimum):
   - test/torrent_service_test.dart
   - test/torrent_file_test.dart
   - test/magnet_link_test.dart
3. Confirm no new analyzer errors/warnings in changed files.
4. Confirm mobile add/create torrent actions are visible and wired.
5. Confirm missing-files status appears when expected.
6. Confirm no add-after-close exceptions remain in patched paths.

## Output Report Format
Return:
1. Files changed.
2. Root cause per issue and exact fix applied.
3. What redundant artifacts were deleted (and what could not be deleted due to lock).
4. Validation command outputs summary.
5. Any remaining risks and recommended next steps.
