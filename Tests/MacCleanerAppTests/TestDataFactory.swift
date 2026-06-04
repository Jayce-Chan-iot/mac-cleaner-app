import Foundation

/// Shared test helper — creates temporary files/directories with known content
enum TestDataFactory {
    /// Create a temporary directory that self-destructs on deinit.
    /// Uses the user's home directory (NOT NSTemporaryDirectory /private/var)
    /// so that files are not silently filtered by SafetyManager / scanner path guards.
    static func createTempDir(name: String = UUID().uuidString) -> URL {
        let fm = FileManager.default
        let homeBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".mca_test_sandbox", isDirectory: true)
        let tmp = homeBase.appendingPathComponent("mca_test_\(name)", isDirectory: true)
        // Clean any stale directory from a previous crashed run
        try? fm.removeItem(at: tmp)
        try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    /// Create a file at path with given content, returns the URL
    @discardableResult
    static func createFile(at dir: URL, name: String, content: String) -> URL {
        let fileURL = dir.appendingPathComponent(name)
        try! content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Create N files with identical content
    static func createDuplicateFiles(at dir: URL, count: Int, namePrefix: String = "dup", content: String = "identical content here") -> [URL] {
        (0..<count).map { i in
            createFile(at: dir, name: "\(namePrefix)_\(i).txt", content: content)
        }
    }

    /// Cleanup test directory
    static func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Create a file of a specific byte size
    static func createFile(ofSize bytes: Int, at dir: URL, name: String) -> URL {
        let fileURL = dir.appendingPathComponent(name)
        let data = Data(count: bytes)
        try! data.write(to: fileURL)
        return fileURL
    }

    /// Verify path is accessible (reverse-protection check)
    static func pathExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
