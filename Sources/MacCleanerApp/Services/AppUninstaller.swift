import Foundation

actor AppUninstaller {
    private let searchPaths: [String] = [
        "~/Library/Application Support",
        "~/Library/Caches",
        "~/Library/Preferences",
        "~/Library/Containers",
        "~/Library/Group Containers",
        "~/Library/Logs",
        "~/Library/Saved Application State",
        "~/Library/WebKit",
        "~/Library/Cookies",
        "~/Library/HTTPStorages",
        "~/Library/LaunchAgents",
        "~/Library/Mail"
    ]

#if DEBUG
    nonisolated var debugSearchPaths: [String] { searchPaths }
#endif

    func scanApps() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let fm = FileManager.default
        let appDirs = ["/Applications", "\(fm.homeDirectoryForCurrentUser.path)/Applications"]

        for dir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                              includingPropertiesForKeys: [.fileSizeKey],
                                                              options: [.skipsHiddenFiles]) else { continue }
            for url in contents where url.pathExtension == "app" {
                if let app = parseApp(at: url) {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { ($0.name).localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func parseApp(at url: URL) -> InstalledApp? {
        let infoPlist = url.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: infoPlist),
              let bundleID = plist["CFBundleIdentifier"] as? String else { return nil }

        let name = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
        let version = plist["CFBundleShortVersionString"] as? String
        let size = directorySize(at: url)

        return InstalledApp(name: name, bundleID: bundleID, version: version, appURL: url, appSize: size, orphans: [])
    }

    func scanOrphans(for bundleID: String) -> [FileItem] {
        var orphans: [FileItem] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        for searchPath in searchPaths {
            let expanded = searchPath.replacingOccurrences(of: "~", with: home)
            let dirURL = URL(fileURLWithPath: expanded)

            let exactURL = dirURL.appendingPathComponent(bundleID)
            if fm.fileExists(atPath: exactURL.path) {
                let size = directorySize(at: exactURL)
                orphans.append(makeFileItem(url: exactURL, size: size, isDirectory: true))
            }

            guard let contents = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for item in contents where item.lastPathComponent.hasPrefix(bundleID) {
                if item != exactURL {
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let attrs = try? fm.attributesOfItem(atPath: item.path)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    orphans.append(makeFileItem(url: item, size: size, isDirectory: isDir))
                }
            }
        }
        return orphans.sorted { $0.size > $1.size }
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey],
                                              options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            autoreleasepool {
                if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int64 {
                    total += size
                }
            }
        }
        return total
    }

    /// Construct a FileItem compatible with the project's existing model
    private func makeFileItem(url: URL, size: Int64, isDirectory: Bool) -> FileItem {
        FileItem(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            size: size,
            modificationDate: nil,
            lastAccessDate: nil,
            creationDate: nil,
            isDirectory: isDirectory,
            fileType: FileItem.FileCategory.from(extension: url.pathExtension)
        )
    }
}
