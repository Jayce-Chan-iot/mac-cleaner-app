import XCTest
@testable import MacCleanerApp

final class AppUninstallerTests: XCTestCase {
    let appUninstaller = AppUninstaller()
    let home = FileManager.default.homeDirectoryForCurrentUser

    // A01: Exactly 12 search paths
    func test_searchPaths_count12() {
        let paths = appUninstaller.debugSearchPaths
        XCTAssertEqual(paths.count, 12, "AppUninstaller must scan exactly 12 ~/Library directories")
    }

    // A02 ★: No user document directories in search paths
    func test_scanPath_excludesUserDocuments() {
        let paths = appUninstaller.debugSearchPaths
        let expandedPaths = paths.map { $0.replacingOccurrences(of: "~", with: home.path) }
        let forbidden = ["Documents", "Desktop", "Pictures", "Downloads", "Movies", "Music"]
        for path in expandedPaths {
            for forbiddenDir in forbidden {
                let containsForbidden = path.hasSuffix("/\(forbiddenDir)")
                    || path.contains("/\(forbiddenDir)/")
                XCTAssertFalse(containsForbidden,
                    "Search path must not include user directory '\(forbiddenDir)': \(path)")
            }
        }
    }

    // A03 ★: AppUninstaller source code never calls removeItem
    func test_uninstallGoesToTrash_notRemoveItem() {
        // Walk up from the test source file to find the project root (where Package.swift lives)
        var currentURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var projectRoot: URL?
        while currentURL.path != "/" {
            let packageURL = currentURL.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageURL.path) {
                projectRoot = currentURL
                break
            }
            currentURL = currentURL.deletingLastPathComponent()
        }

        guard let root = projectRoot else {
            XCTFail("Cannot find project root (no Package.swift found)")
            return
        }

        let sourceFile = root.appendingPathComponent("Sources/MacCleanerApp/Services/AppUninstaller.swift")

        guard FileManager.default.fileExists(atPath: sourceFile.path) else {
            XCTFail("AppUninstaller.swift not found at expected path: \(sourceFile.path)")
            return
        }

        guard let source = try? String(contentsOf: sourceFile, encoding: .utf8) else {
            XCTFail("Cannot read AppUninstaller.swift source at \(sourceFile.path)")
            return
        }

        let removeItemCount = source.components(separatedBy: "removeItem").count - 1
        XCTAssertEqual(removeItemCount, 0,
            "AppUninstaller must NEVER call removeItem directly — must use TrashManager.moveToTrash")
    }

    // A04 ★: WeChat scanOrphans must not return chat DB files
    func test_bundleID_weChat_scanOrphans() async throws {
        let orphans = try await appUninstaller.scanOrphans(for: "com.tencent.xinWeChat")
        for orphan in orphans {
            let isChatDB = orphan.url.path.contains("Message") && orphan.url.pathExtension == "db"
            XCTAssertFalse(isChatDB,
                "WeChat chat database must not appear in scan results: \(orphan.url.path)")
        }
    }

    // A05: Normal scanOrphans returns results without crash
    func test_scanOrphans_doesNotCrash() async throws {
        // Even for non-existent bundle IDs, should return empty without crashing
        let orphans = try await appUninstaller.scanOrphans(for: "com.nonexistent.fakeapp.12345")
        XCTAssertEqual(orphans.count, 0, "Non-existent bundle ID should return empty array")
    }
}
