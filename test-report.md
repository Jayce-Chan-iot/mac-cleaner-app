# MacCleanerApp Test Report

**Date:** 2026-06-02
**Version:** 0.1.0 (development)
**Swift:** 6.0
**macOS Target:** 14.0+
**Build Status:** `swift build` — PASS

---

## Test File List and Case Counts

| # | File | Test Cases | Coverage Area |
|---|------|-----------|---------------|
| 1 | `JunkDetectorTests.swift` | 10 | Junk detection rules — cache, logs, Xcode, Docker, false-positive prevention (Documents, Desktop, WeChat, Chrome, VS Code) |
| 2 | `TrashManagerTests.swift` | 7 | Recycle bin operations — move, restore, permanent delete, expiry purge, orphan reconciliation, system path blocking, batch file handling |
| 3 | `SafetyManagerTests.swift` | 6 | Path protection — system paths, user documents, all 13 protected prefixes, system extensions, non-existent file handling |
| 4 | `AppUninstallerTests.swift` | 5 | Uninstaller — 12 search paths, user document exclusion, removeItem ban enforcement, WeChat chat DB exclusion, non-existent bundle ID resilience |
| 5 | `DuplicateDetectorTests.swift` | 4 | Duplicate detection — identical files, different content same size, small file filtering, three-level hash pipeline |
| 6 | `UnifiedScannerTests.swift` | 3 | Unified stream scanner — four-way split output, batch flush progress handler, empty directory resilience |
| **Total** | **6 test files** | **35** | |

(Test helper `TestDataFactory.swift` contains 0 test cases — it provides shared setup/teardown utilities only.)

---

## Test Case Details

### JunkDetectorTests (10 tests)

| ID | Name | Description |
|----|------|-------------|
| J01 | `test_cacheRule_matchesUserCache` | User `~/Library/Caches` matches the cache junk rule |
| J02 | `test_logRule_matchesSystemLog` | `~/Library/Logs/DiagnosticReports` matches the log rule |
| J03 | `test_xcodeRule_matchesDerivedData` | Xcode DerivedData path matches the xcodeJunk rule |
| J04 | `test_userDocument_NOT_matchedAsJunk` | `~/Documents` files are NOT matched by any junk rule (false-positive guard) |
| J05 | `test_userDesktop_NOT_matchedAsJunk` | `~/Desktop` files are NOT matched by any junk rule (false-positive guard) |
| J06 | `test_weChatData_NOT_matchedAsJunk` | WeChat container data is NOT matched as junk (false-positive guard) |
| J07 | `test_chromeProfile_NOT_matchedAsJunk` | Chrome browser profile is NOT matched as junk (false-positive guard) |
| J08 | `test_ruleCount_equals22` | Rules array contains exactly 22 entries |
| J09 | `test_dockerContainer_matchesRule` | Docker container directory matches the dockerLeftovers rule |
| J10 | `test_vscodeSettings_NOT_matchedAsJunk` | VS Code user settings are NOT matched as junk (false-positive guard) |

### TrashManagerTests (7 tests)

| ID | Name | Description |
|----|------|-------------|
| T01 | `test_moveToTrash_createsEntry` | `moveToTrash` creates a manifest entry and moves the file physically |
| T02 | `test_restore_putsFileBack` | Restore returns the file to its original path and removes it from manifest |
| T03 | `test_permanentlyDelete_trashItem` | Permanent delete removes file from recycle and manifest |
| T04 | `test_purgeExpired_nonExpiredSurvive` | Non-expired items (within 7-day window) survive purge |
| T05 | `test_reconcileOrphans_onStartup` | Orphan files in recycle directory are handled without crash during startup |
| T06 | `test_moveToTrash_blocksSystemPath` | System paths (`/System/Library`) are silently skipped by moveToTrash |
| T07 | `test_moveToTrash_multipleFiles` | Batch operation with 3 files creates 3 manifest entries |

### SafetyManagerTests (6 tests)

| ID | Name | Description |
|----|------|-------------|
| S01 | `test_systemPathBlocked` | `/System/Library/CoreServices/Finder.app` is protected |
| S02 | `test_userDocumentNotBlocked` | User `~/Documents/report.pdf` is NOT protected (safe to clean) |
| S03 | `test_binSbinUsrLibBlocked` | 7 representative system paths (`/bin`, `/sbin`, `/usr/lib`, etc.) are all protected |
| S04 | `test_trashItemCalledNotRemoveItem` | `trashItems` handles non-existent files gracefully (returns 0, no crash) |
| S05 | `test_whitelistCompleteness` | All 13 protected path prefixes are verified as protected |
| S06 | `test_systemExtensionsBlocked` | `.kext`, `.framework`, `.bundle`, `.dylib` extensions are protected anywhere on disk |

### DuplicateDetectorTests (4 tests)

| ID | Name | Description |
|----|------|-------------|
| D01 | `test_identicalFiles_detected` | 3 identical files (2KB each) produce exactly 1 duplicate group with 3 files |
| D02 | `test_differentContent_notDetected` | Same-size files with different content are NOT grouped as duplicates |
| D03 | `test_tooSmallFiles_skipped` | Files below `minFileSize` (1024 bytes) are skipped entirely |
| D04 | `test_level1_sizeFilter_and_hashFilter_work` | Level 1 size grouping and Level 2 hash filtering correctly exclude unique-size and different-content files |

### UnifiedScannerTests (3 tests)

| ID | Name | Description |
|----|------|-------------|
| U01 | `test_fourWaySplit` | Scan produces all four outputs (junk, largeFiles, duplicates, categorized) with non-empty categorized count |
| U02 | `test_batchFlush_progressHandlerCalled` | 600+ files trigger batch flush (every 500 files), progress handler called multiple times |
| U03 | `test_emptyDirectory_doesNotCrash` | Empty directory scan completes cleanly with zero results |

### AppUninstallerTests (5 tests)

| ID | Name | Description |
|----|------|-------------|
| A01 | `test_searchPaths_count12` | `debugSearchPaths` contains exactly 12 `~/Library` directories |
| A02 | `test_scanPath_excludesUserDocuments` | None of the 12 search paths include Documents, Desktop, Pictures, Downloads, Movies, or Music |
| A03 | `test_uninstallGoesToTrash_notRemoveItem` | Source code of `AppUninstaller.swift` contains zero `removeItem` calls (deletion goes through `TrashManager.moveToTrash`) |
| A04 | `test_bundleID_weChat_scanOrphans` | WeChat orphan scan excludes chat database files (`.db` in Message path) |
| A05 | `test_scanOrphans_doesNotCrash` | Non-existent bundle ID returns empty array without crash |

---

## Summary Table

| Metric | Value |
|--------|-------|
| Total test files | 6 |
| Total test cases | **35** |
| Test helper files | 1 (`TestDataFactory.swift`) |
| Build status | `swift build` — PASS (0 errors) |
| Swift concurrency check | Strict (Complete) |
| Module tested | `MacCleanerApp` |

### Coverage by Module

| Module | Tests | Key Risk Area |
|--------|-------|---------------|
| JunkDetector | 10 | False-positive prevention (5 of 10 tests) |
| TrashManager | 7 | Data safety (system path blocking, orphan recovery) |
| SafetyManager | 6 | White-list completeness (all 13 prefixes verified) |
| AppUninstaller | 5 | Safety (removeItem ban, user directory exclusion) |
| DuplicateDetector | 4 | Three-level hash pipeline correctness |
| UnifiedScanner | 3 | Stream integrity, batch flushing, resilience |

---

## Known Limitations

1. **XCTest requires Xcode to execute.** All tests compile via `swift build` but cannot be run with `swift test` using the CLI-only Swift toolchain. Xcode 16+ is required to execute the test suite (`⌘+U` in Xcode, or `xcodebuild test`).

2. **No integration tests.** All 35 tests are unit tests targeting individual services in isolation. End-to-end tests (full scan → delete → restore flow) are not yet implemented.

3. **No UI tests.** The SwiftUI interface (ContentView, module views, NavigationSplitView layout) has no UI tests. Interaction flows like delete confirmation dialogs and Dynamic Island notifications are untested at the UI layer.

4. **Performance tests.** No performance benchmarks exist for memory pressure (<200MB target) or scan throughput. The batch-flush test (U02) is the closest approximation, verifying the progress handler is called multiple times.

5. **Crash recovery tests.** The TrashManager's manifest-based crash recovery is tested only via the reconcileOrphans startup path (T05). No simulation of mid-operation crashes exists.

6. **Test data factory scope.** `TestDataFactory` creates real files on disk in a temp directory. Tests rely on `setUp`/`tearDown` for cleanup. Any test interrupted mid-flight (e.g., by a crash or SIGKILL) may leave orphan temp directories behind.

---

*Report generated on 2026-06-02 via automated analysis.*
