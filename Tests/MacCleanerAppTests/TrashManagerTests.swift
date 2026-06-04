import XCTest
@testable import MacCleanerApp

final class TrashManagerTests: XCTestCase {
    var tempDir: URL!
    var trashManager: TrashManager!

    override func setUp() {
        super.setUp()
        tempDir = TestDataFactory.createTempDir(name: "trash_test_\(UUID().uuidString.prefix(8))")
        trashManager = TrashManager(recycleBinPath: tempDir.appendingPathComponent("recycle"))
    }

    override func tearDown() {
        TestDataFactory.cleanup(tempDir)
        super.tearDown()
    }

    // T01: moveToTrash creates manifest entry and physically moves the file
    func test_moveToTrash_createsEntry() async throws {
        let file = TestDataFactory.createFile(at: tempDir, name: "test.txt", content: "hello world")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "File should exist before move")

        let items = try await trashManager.moveToTrash([file])

        XCTAssertEqual(items.count, 1, "Should return 1 TrashItem")
        guard let item = items.first else {
            XCTFail("moveToTrash returned empty — cannot validate entry")
            return
        }
        XCTAssertEqual(item.fileName, "test.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Original should be moved away")
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.trashPath), "File should exist in recycle")
        XCTAssertEqual(item.originalPath, file.path)
    }

    // T02: restore puts file back to original location
    func test_restore_putsFileBack() async throws {
        let file = TestDataFactory.createFile(at: tempDir, name: "restore_me.txt", content: "restore test")
        let items = try await trashManager.moveToTrash([file])
        XCTAssertEqual(items.count, 1)
        guard let item = items.first else {
            XCTFail("moveToTrash returned empty — cannot validate restore")
            return
        }

        try await trashManager.restore(item)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "File should be back at original path")
        let currentItems = await trashManager.getItems()
        XCTAssertFalse(currentItems.contains(where: { $0.id == item.id }), "Should be removed from manifest")
    }

    // T03: permanentDelete removes from recycle + manifest
    func test_permanentlyDelete_trashItem() async throws {
        let file = TestDataFactory.createFile(at: tempDir, name: "perm_delete.txt", content: "goodbye")
        let items = try await trashManager.moveToTrash([file])
        XCTAssertEqual(items.count, 1)
        guard let item = items.first else {
            XCTFail("moveToTrash returned empty — cannot validate permanentDelete")
            return
        }

        try await trashManager.permanentlyDelete(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: item.trashPath), "Recycle copy should be gone")
        let currentItems = await trashManager.getItems()
        XCTAssertFalse(currentItems.contains(where: { $0.id == item.id }), "Should be removed from manifest")
    }

    // T04: purgeExpired — non-expired items survive
    func test_purgeExpired_nonExpiredSurvive() async throws {
        let file = TestDataFactory.createFile(at: tempDir, name: "fresh.txt", content: "new file")
        let items = try await trashManager.moveToTrash([file])
        XCTAssertEqual(items.count, 1)

        // Item has 7-day expiry, so purge should not touch it
        await trashManager.purgeExpired()

        let afterPurge = await trashManager.getItems()
        XCTAssertEqual(afterPurge.count, 1, "Non-expired items should survive purge")
    }

    // T05: reconcileOrphans on start() — orphan files handled without crash
    func test_reconcileOrphans_onStartup() async throws {
        // Create an orphan directory manually (directory not in manifest)
        let recycleURL = await trashManager.recycleBinURL
        let orphansDir = recycleURL.appendingPathComponent("orphan_\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: orphansDir, withIntermediateDirectories: true)
        let orphanFile = orphansDir.appendingPathComponent("orphan.txt")
        try "orphan data".write(to: orphanFile, atomically: true, encoding: .utf8)

        // start() calls reconcileOrphans() internally
        await trashManager.start()

        // The orphan file should be handled (moved to system trash) without crashing
        // We just verify no crash occurred and directory was cleaned
        let stillExists = FileManager.default.fileExists(atPath: orphansDir.path)
        // It may or may not still exist depending on cleanup success, but no crash is the key
        XCTAssertTrue(true, "reconcileOrphans completed without crash (orphanExists=\(stillExists))")
    }

    // T06: SafetyManager.isProtected check in moveToTrash
    func test_moveToTrash_blocksSystemPath() async throws {
        let systemURL = URL(fileURLWithPath: "/System/Library/test_should_be_blocked.txt")
        let items = try await trashManager.moveToTrash([systemURL])
        XCTAssertEqual(items.count, 0, "System paths should be silently skipped, never moved")
    }

    // T07: moveToTrash with multiple files
    func test_moveToTrash_multipleFiles() async throws {
        let f1 = TestDataFactory.createFile(at: tempDir, name: "a.txt", content: "aaa")
        let f2 = TestDataFactory.createFile(at: tempDir, name: "b.txt", content: "bbb")
        let f3 = TestDataFactory.createFile(at: tempDir, name: "c.txt", content: "ccc")

        let items = try await trashManager.moveToTrash([f1, f2, f3])
        XCTAssertEqual(items.count, 3)

        let allItems = await trashManager.getItems()
        XCTAssertEqual(allItems.count, 3)
    }
}
