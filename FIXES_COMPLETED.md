# Fixes Completed - April 3, 2026

## Summary
All 4 user-reported issues have been successfully fixed, tested, and committed to git.

## Issues Fixed

### 1. Browse Button Opens Folder Instead of Picking
**File:** lib/screens/about_screen.dart
**Change:** Replaced `_pickDownloadDirectory()` with `_openDownloadFolder()`
**Implementation:**
- Uses `launchUrl()` with `LaunchMode.externalApplication` on desktop (Windows/Mac/Linux)
- Shows snackbar with path on Android
- Opens the existing download folder instead of letting user pick a new one

### 2. Pending Metadata Display Improved
**File:** lib/screens/torrent_detail_screen.dart
**Change:** Detail screen now shows appropriate status message instead of 0% progress
**Implementation:**
- Checks if `statusLabel == 'Pending Metadata'`
- Shows: "Status: Waiting for metadata from peers..."
- Falls back to: "Progress: X%" for other states
- Makes it clear torrent is waiting, not stuck or broken

### 3. Android Stuck Loading Torrents Fixed
**File:** lib/services/torrent_service.dart
**Change:** Added `_emitCachedStatesIfAvailable()` method called at startup
**Implementation:**
- Emits initial cached states immediately in `_ensureStateSyncStarted()`
- If no cached states yet, emits empty list so stream has data
- Database refresh happens asynchronously in background
- UI displays instantly instead of waiting on slow disk I/O

### 4. System Tray Setting Shows Restart Requirement
**File:** lib/screens/about_screen.dart
**Change:** Updated toggle callback to show informational message
**Implementation:**
- Shows snackbar: "System tray will be enabled/disabled when you restart the app"
- Explains to user that TrayService is initialized at app startup
- Setting is properly persisted in SharedPreferences

## Verification
- ✅ All changes committed to git (commit 537a08f)
- ✅ APK built successfully (76.4 MB)
- ✅ Windows exe built successfully
- ✅ Zero compilation errors
- ✅ All code reviewed and verified correct

## Status
**COMPLETE** - All user requirements met and implemented.
