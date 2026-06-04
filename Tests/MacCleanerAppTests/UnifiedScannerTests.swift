import XCTest
import os
@testable import MacCleanerApp

final class UnifiedScannerTests: XCTestCase {
    let unifiedScanner = UnifiedScanner()
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = TestDataFactory.createTempDir(name: "scan_test_\(UUID().uuidString.prefix(8))")
    }

    override func tearDown() {
        TestDataFactory.cleanup(tempDir)
        super.tearDown()
    }

    // U01: Categorization + duplicate detection via four-way split scan
    func test_fourWaySplit() async throws {
        // Duplicate candidates: two files with identical content and same size > 1024 bytes
        let dupContent = String(repeating: "D", count: 3000) // 3000 bytes > 1024 min
        TestDataFactory.createFile(at: tempDir, name: "dup_a.txt", content: dupContent)
        TestDataFactory.createFile(at: tempDir, name: "dup_b.txt", content: dupContent)

        // Categorized files with known extensions
        TestDataFactory.createFile(at: tempDir, name: "photo.jpg", content: String(repeating: "J", count: 2000))
        TestDataFactory.createFile(at: tempDir, name: "notes.pdf", content: String(repeating: "P", count: 3000))
        TestDataFactory.createFile(at: tempDir, name: "song.mp3", content: String(repeating: "M", count: 5000))
        // A file with no recognized extension → .other
        TestDataFactory.createFile(at: tempDir, name: "data.xyz", content: String(repeating: "X", count: 1000))

        let result = try await unifiedScanner.scan(rootURL: tempDir)

        // All four output containers should exist
        XCTAssertNotNil(result.categorized, "categorized output should exist")
        XCTAssertNotNil(result.duplicates, "duplicates output should exist")

        // Categorization: verify files are sorted by extension into correct categories
        let totalCategorized = result.categorized.values.flatMap { $0 }.count
        XCTAssertEqual(totalCategorized, 6, "All 5 files should be categorized")

        // Known extension → specific category
        let imageFiles = result.categorized[.image] ?? []
        XCTAssertEqual(imageFiles.count, 1, "photo.jpg → .image")
        XCTAssertTrue(imageFiles.contains(where: { $0.fileName == "photo.jpg" }))

        let docFiles = result.categorized[.document] ?? []
        XCTAssertEqual(docFiles.count, 3, "notes.pdf, dup_a.txt, dup_b.txt → .document")
        XCTAssertTrue(docFiles.contains(where: { $0.fileName == "notes.pdf" }))

        let audioFiles = result.categorized[.audio] ?? []
        XCTAssertEqual(audioFiles.count, 1, "song.mp3 → .audio")

        let otherFiles = result.categorized[.other] ?? []
        XCTAssertEqual(otherFiles.count, 1, "data.xyz (unrecognized extension) → .other")
        XCTAssertTrue(otherFiles.contains(where: { $0.fileName == "data.xyz" }))

        // Duplicate detection: two files with identical content → 1 duplicate group
        XCTAssertEqual(result.duplicates.count, 1, "Two identical 3000-byte files should form 1 duplicate group")
        guard let dupGroup = result.duplicates.first else {
            XCTFail("No duplicate group returned")
            return
        }
        XCTAssertEqual(dupGroup.files.count, 2, "Duplicate group should contain both files")
        XCTAssertEqual(dupGroup.wasteSize, dupGroup.fileSize, "wasteSize = fileSize × 1 (one duplicate)")
    }

    // U02: Progress handler is called (batch flush verification)
    func test_batchFlush_progressHandlerCalled() async throws {
        // Create 600+ small files (exceeds batchSize of 500 to trigger at least one flush)
        for i in 0..<600 {
            TestDataFactory.createFile(at: tempDir, name: "file_\(i).txt", content: String(repeating: "T", count: 100))
        }

        let counter = OSAllocatedUnfairLock(initialState: 0)
        let _ = try await unifiedScanner.scan(
            rootURL: tempDir,
            progressHandler: { _, _ in
                counter.withLock { $0 += 1 }
            }
        )

        let callCount = counter.withLock { $0 }
        XCTAssertGreaterThan(callCount, 1, "Progress handler should be called multiple times via batch flushing")
    }

    // U03: Scan completes without crash even on empty directory
    func test_emptyDirectory_doesNotCrash() async throws {
        let emptyDir = TestDataFactory.createTempDir(name: "empty_scan")
        defer { TestDataFactory.cleanup(emptyDir) }

        let result = try await unifiedScanner.scan(rootURL: emptyDir)

        XCTAssertEqual(result.largeFiles.count, 0, "Empty dir should have no large files")
        XCTAssertEqual(result.duplicates.count, 0, "Empty dir should have no duplicates")
    }
}
