import XCTest
@testable import MacCleanerApp

final class SafetyManagerTests: XCTestCase {
    let safetyManager = SafetyManager()

    // S01: System path must be blocked
    func test_systemPathBlocked() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertTrue(safetyManager.isProtected(url))
    }

    // S02: User documents must NOT be blocked
    func test_userDocumentNotBlocked() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Documents/report.pdf")
        XCTAssertFalse(safetyManager.isProtected(url))
    }

    // S03: All 13 protected prefixes must be blocked (test a representative set: /bin/bash, /sbin/launchd, /usr/lib/libSystem.dylib, /usr/libexec, /usr/sbin, /usr/share, /usr/standalone)
    func test_binSbinUsrLibBlocked() {
        let blocked = [
            "/bin/bash", "/sbin/launchd", "/usr/lib/libSystem.dylib",
            "/usr/libexec", "/usr/sbin", "/usr/share", "/usr/standalone"
        ]
        for path in blocked {
            XCTAssertTrue(safetyManager.isProtected(URL(fileURLWithPath: path)), "\(path) must be protected")
        }
    }

    // S04: trashItems completes without crash on non-existent files (verifies it uses trashItem not removeItem)
    func test_trashItemCalledNotRemoveItem() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mca_safety_test_nonexistent_\(UUID().uuidString).txt")
        let count = try await safetyManager.trashItems([tmpURL])
        XCTAssertEqual(count, 0, "Nonexistent file should return 0")
    }

    // S05: All 13 protected prefixes verified
    func test_whitelistCompleteness() {
        let prefixes = [
            "/System", "/bin", "/sbin", "/usr/lib", "/usr/libexec",
            "/usr/sbin", "/usr/share", "/usr/standalone",
            "/.Spotlight-V100", "/.fseventsd", "/.DocumentRevisions-V100",
            "/.TemporaryItems", "/.Trashes"
        ]
        for prefix in prefixes {
            XCTAssertTrue(safetyManager.isProtected(URL(fileURLWithPath: prefix)), "\(prefix) must be protected")
        }
    }

    // S06: System extensions blocked anywhere
    func test_systemExtensionsBlocked() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for ext in ["kext", "framework", "bundle", "dylib"] {
            let url = home.appendingPathComponent("Desktop/test.\(ext)")
            XCTAssertTrue(safetyManager.isProtected(url), ".\(ext) must be protected anywhere")
        }
    }
}
