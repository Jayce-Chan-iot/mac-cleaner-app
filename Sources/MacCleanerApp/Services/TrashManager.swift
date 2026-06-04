import Foundation

// MARK: - Trash Item Model

struct TrashItem: Identifiable, Codable, Sendable {
    let id: String
    let originalPath: String
    let trashPath: String
    let size: Int64
    let fileName: String
    let deletedAt: Date
    let expiresAt: Date

    var remainingDays: Int {
        let seconds = expiresAt.timeIntervalSinceNow
        return max(0, Int(seconds / 86400))
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedExpiresAt: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: expiresAt)
    }
}

// MARK: - Manifest

private struct TrashManifest: Codable {
    var items: [TrashItem]
}

// MARK: - TrashManager Actor

actor TrashManager {
    private let fileManager = FileManager.default
    private let safetyManager = SafetyManager()

    let recycleBinURL: URL

    private var manifestURL: URL {
        recycleBinURL.appendingPathComponent(".trash-manifest.json")
    }

    private var manifest: TrashManifest
    private var purgeTimer: Timer?
    private var isStarted = false

    // MARK: - Init

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        recycleBinURL = docs.appendingPathComponent("MacCleanerApp 回收站")
        manifest = TrashManifest(items: [])
        try? fileManager.createDirectory(at: recycleBinURL, withIntermediateDirectories: true)
    }

#if DEBUG
    /// Test-only initializer with custom recycle bin path
    init(recycleBinPath: URL) {
        recycleBinURL = recycleBinPath
        manifest = TrashManifest(items: [])
        try? fileManager.createDirectory(at: recycleBinURL, withIntermediateDirectories: true)
    }
#endif

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        loadManifest()
        reconcileOrphans()

        let timer = Timer(timeInterval: 12 * 3600, repeats: true) { [weak self] _ in
            Task { await self?.purgeExpired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.purgeTimer = timer
        Task { await self.purgeExpired() }
    }

    func stop() {
        purgeTimer?.invalidate()
        purgeTimer = nil
    }

    // MARK: - Move to Trash

    @discardableResult
    func moveToTrash(_ urls: [URL]) async throws -> [TrashItem] {
        var newItems: [TrashItem] = []
        let now = Date()
        let expireDate = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        for url in urls {
            guard !safetyManager.isProtected(url) else { continue }
            guard fileManager.fileExists(atPath: url.path) else { continue }

            let itemID = UUID().uuidString
            let itemDir = recycleBinURL.appendingPathComponent(itemID)
            let destURL = itemDir.appendingPathComponent(url.lastPathComponent)

            do {
                try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
                try fileManager.moveItem(at: url, to: destURL)

                let fileSize: Int64 = {
                    if let values = try? destURL.resourceValues(forKeys: [.fileSizeKey]),
                       let size = values.fileSize {
                        return Int64(size)
                    }
                    return 0
                }()

                let item = TrashItem(
                    id: itemID,
                    originalPath: url.path,
                    trashPath: destURL.path,
                    size: fileSize,
                    fileName: url.lastPathComponent,
                    deletedAt: now,
                    expiresAt: expireDate
                )
                newItems.append(item)
            } catch {
                try? fileManager.removeItem(at: itemDir)
                continue
            }
        }

        manifest.items.append(contentsOf: newItems)
        saveManifest()

        return newItems
    }

    // MARK: - Restore

    func restore(_ item: TrashItem) async throws {
        let trashURL = URL(fileURLWithPath: item.trashPath)
        let originalURL = URL(fileURLWithPath: item.originalPath)

        guard fileManager.fileExists(atPath: trashURL.path) else {
            throw TrashError.fileNotFound
        }

        try fileManager.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try fileManager.moveItem(at: trashURL, to: originalURL)
        // Save manifest BEFORE cleanup (crash-safe)
        manifest.items.removeAll { $0.id == item.id }
        saveManifest()
        // Now safe to clean up the empty wrapper directory
        let itemDir = trashURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: itemDir)
    }

    // MARK: - Permanent Delete

    func permanentlyDelete(_ item: TrashItem) async throws {
        let trashURL = URL(fileURLWithPath: item.trashPath)

        guard fileManager.fileExists(atPath: trashURL.path) else {
            manifest.items.removeAll { $0.id == item.id }
            saveManifest()
            return
        }

        var resultingItemURL: NSURL?
        try fileManager.trashItem(at: trashURL, resultingItemURL: &resultingItemURL)

        let itemDir = trashURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: itemDir)

        manifest.items.removeAll { $0.id == item.id }
        saveManifest()
    }

    // MARK: - Query

    func getItems() -> [TrashItem] {
        manifest.items.sorted { $0.deletedAt > $1.deletedAt }
    }

    // MARK: - Purge

    func purgeExpired() async {
        let now = Date()
        let expired = manifest.items.filter { $0.expiresAt < now }

        for item in expired {
            let trashURL = URL(fileURLWithPath: item.trashPath)
            if fileManager.fileExists(atPath: trashURL.path) {
                var resultingItemURL: NSURL?
                try? fileManager.trashItem(at: trashURL, resultingItemURL: &resultingItemURL)
            }
            let itemDir = trashURL.deletingLastPathComponent()
            // Only cleanup if directory is empty (trashItem succeeded)
            let contents = (try? fileManager.contentsOfDirectory(atPath: itemDir.path)) ?? []
            if contents.isEmpty {
                try? fileManager.removeItem(at: itemDir)
            }
        }

        if !expired.isEmpty {
            manifest.items.removeAll { $0.expiresAt < now }
            saveManifest()
        }
    }

    // MARK: - Manifest I/O

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(TrashManifest.self, from: data) else {
            manifest = TrashManifest(items: [])
            return
        }
        manifest = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - Orphan Reconciliation

    private func reconcileOrphans() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: recycleBinURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        let knownIDs = Set(manifest.items.map { $0.id })

        for dirURL in contents {
            let dirName = dirURL.lastPathComponent
            guard !knownIDs.contains(dirName), !dirName.hasPrefix(".") else { continue }

            // Orphan found: move its contents to system Trash if possible
            if let fileURLs = try? fileManager.contentsOfDirectory(
                at: dirURL, includingPropertiesForKeys: nil, options: []
            ), let firstFile = fileURLs.first {
                var resultingItemURL: NSURL?
                try? fileManager.trashItem(at: firstFile, resultingItemURL: &resultingItemURL)
            }
            // Cleanup empty wrapper directory
            let remaining = (try? fileManager.contentsOfDirectory(atPath: dirURL.path)) ?? []
            if remaining.isEmpty {
                try? fileManager.removeItem(at: dirURL)
            }
        }
    }
}

// MARK: - Errors

enum TrashError: LocalizedError {
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "文件在回收站中不存在"
        }
    }
}
