import Foundation

struct InstalledApp: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let bundleID: String
    let version: String?
    let appURL: URL
    let appSize: Int64
    var orphans: [FileItem]
    var orphanSize: Int64 { orphans.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { appSize + orphanSize }
}
