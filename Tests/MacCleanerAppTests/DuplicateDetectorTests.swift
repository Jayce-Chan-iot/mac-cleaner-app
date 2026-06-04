import XCTest
@testable import MacCleanerApp

final class DuplicateDetectorTests: XCTestCase {
    let duplicateDetector = DuplicateDetector()
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = TestDataFactory.createTempDir(name: "dup_test_\(UUID().uuidString.prefix(8))")
    }

    override func tearDown() {
        TestDataFactory.cleanup(tempDir)
        super.tearDown()
    }

    // D01: 3 identical files with content exceeding minFileSize (1KB) → 1 duplicate group
    func test_identicalFiles_detected() async throws {
        let bigContent = String(repeating: "ABCDEFGHIJ", count: 200) // 2000 bytes > 1024
        TestDataFactory.createDuplicateFiles(at: tempDir, count: 3, namePrefix: "bigsame", content: bigContent)

        let groups = try await duplicateDetector.findDuplicates(in: tempDir)

        XCTAssertEqual(groups.count, 1, "Should find exactly 1 duplicate group")
        guard let group = groups.first else {
            XCTFail("No duplicate group returned — cannot validate group contents")
            return
        }
        XCTAssertEqual(group.files.count, 3, "Group should contain all 3 identical files")
        XCTAssertEqual(group.wasteSize, group.fileSize * 2, "wasteSize = fileSize * (count-1)")
    }

    // D02: Same size, different content → NOT duplicates
    func test_differentContent_notDetected() async throws {
        let content1 = String(repeating: "A", count: 2000) // 2000 bytes
        let content2 = String(repeating: "B", count: 2000) // same size, different content
        TestDataFactory.createFile(at: tempDir, name: "diff_1.txt", content: content1)
        TestDataFactory.createFile(at: tempDir, name: "diff_2.txt", content: content2)

        let groups = try await duplicateDetector.findDuplicates(in: tempDir)
        XCTAssertTrue(groups.isEmpty, "Different content with same size should NOT be grouped")
    }

    // D03: Files smaller than minFileSize (1024 bytes) should be skipped
    func test_tooSmallFiles_skipped() async throws {
        let smallContent = "x" // 1 byte, well below 1024 byte minFileSize
        TestDataFactory.createFile(at: tempDir, name: "tiny_1.txt", content: smallContent)
        TestDataFactory.createFile(at: tempDir, name: "tiny_2.txt", content: smallContent)

        let groups = try await duplicateDetector.findDuplicates(in: tempDir)
        XCTAssertTrue(groups.isEmpty, "Files smaller than minFileSize (1024 bytes) should be skipped")
    }

    // D04: Level 1 size grouping — unique sizes discarded; same-size different-content not duplicated
    func test_level1_sizeFilter_and_hashFilter_work() async throws {
        // Two files with same size (5KB) but different content
        // → grouped at Level 1, filtered out at Level 2 (different prefix hash)
        let contentA = String(repeating: "X", count: 5000)
        let contentB = String(repeating: "Y", count: 5000)
        TestDataFactory.createFile(at: tempDir, name: "big_A.bin", content: contentA)
        TestDataFactory.createFile(at: tempDir, name: "big_B.bin", content: contentB)
        // One file with unique size (under minFileSize) — filtered at minFileSize check
        TestDataFactory.createFile(at: tempDir, name: "small_1.txt", content: "tiny")

        let groups = try await duplicateDetector.findDuplicates(in: tempDir)
        XCTAssertTrue(groups.isEmpty, "Same-size random-content files should not be duplicates")
    }
}
