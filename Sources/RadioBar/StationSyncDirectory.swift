import Foundation
#if os(macOS)
import Darwin
#endif

/// Platform-specific directory authorization; bookmark data is private to each installation.
struct StationSyncDirectory {
    let bookmark: Data

    init(selecting url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    init(bookmark: Data) { self.bookmark = bookmark }

    /// A stale/revoked bookmark requires explicit reselection; never fall back to a guessed path.
    func withAccess<T>(_ operation: (URL) throws -> T) throws -> T {
        var stale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        guard !stale else { throw CocoaError(.fileReadNoPermission) }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #if !os(macOS)
        guard accessing else { throw CocoaError(.fileReadNoPermission) }
        #endif
        // Non-sandboxed macOS access can succeed without a security-scope extension.
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
        return try operation(url)
    }
}

#if os(macOS)
enum MacICloudSetupError: Error, Equatable {
    case unavailable, occupied, multipleLibraries, waitingForDownload

    var text: RadioText {
        switch self {
        case .unavailable:
            return RadioText("无法自动访问 iCloud Drive，请选择已有同步文件夹，或在 iCloud Drive 中选择一个位置。",
                             "Could not access iCloud Drive automatically. Choose an existing sync folder or a location in iCloud Drive.")
        case .occupied:
            return RadioText("RadioBar 同步位置已有其他文件，未覆盖或新建目录。请选择已有同步文件夹或其他位置。",
                             "The RadioBar sync location contains other files. Nothing was replaced or created. Choose an existing sync folder or another location.")
        case .multipleLibraries:
            return RadioText("发现多个 RadioBar 同步目录，请选择要关联的文件夹；未合并或覆盖配置。",
                             "Multiple RadioBar sync folders were found. Choose the one to connect; no configurations were merged or replaced.")
        case .waitingForDownload:
            return RadioText("已有同步目录尚未下载完成，请在 Finder 中下载后重试；不会另建同步目录。",
                             "An existing sync folder has not finished downloading. Download it in Finder and try again; no replacement folder will be created.")
        }
    }
}

/// Best-effort adapter for the current non-sandboxed Mac build, not an iCloud-container API.
/// The conventional CloudDocs location is only a candidate: the system must identify it
/// as ubiquitous. Never create that root, use it after a revoked bookmark, or use it on iOS.
enum MacICloudSyncSetup {
    struct Prepared {
        let folder: URL
        let createdDirectory: URL?

        func discardEmptyDirectory() {
            guard let createdDirectory else { return }
            // rmdir is atomic and refuses nonempty directories and symlinks. Never recursively
            // remove an item: another Mac or provider may have populated it since creation.
            NSFileCoordinator().coordinate(writingItemAt: createdDirectory, options: .forDeleting, error: nil) { url in
                url.withUnsafeFileSystemRepresentation { path in
                    if let path { _ = Darwin.rmdir(path) }
                }
            }
        }
    }

    static func locateRoot(candidate suppliedCandidate: URL? = nil) throws -> URL {
        let library = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        let candidate = suppliedCandidate ?? library.appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        do {
            let values = try candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey])
            guard values.isDirectory == true, values.isSymbolicLink != true, values.isUbiquitousItem == true else {
                throw MacICloudSetupError.unavailable
            }
            return candidate
        } catch { throw MacICloudSetupError.unavailable }
    }

    static func associationFolder(for selected: URL) throws -> URL {
        guard selected.lastPathComponent == StationSyncFiles.directoryName else { return selected }
        try requireDirectory(selected)
        let nested = selected.appendingPathComponent(StationSyncFiles.directoryName, isDirectory: true)
        guard try !directoryExists(nested) else { return selected }
        try validateNamespace(selected)
        return selected.deletingLastPathComponent()
    }

    /// root has already been identified by locateRoot; tests inject an isolated directory.
    static func prepare(in root: URL) throws -> Prepared {
        var result: Result<Prepared, Error> = .failure(MacICloudSetupError.unavailable)
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: root, options: .forMerging, error: &coordinationError) { root in
            result = Result {
                try Task.checkCancellation()
                try requireDirectory(root)
                let standard = root.appendingPathComponent("RadioBar", isDirectory: true)
                let legacy = root.appendingPathComponent(StationSyncFiles.directoryName, isDirectory: true)
                let standardExists = try directoryExists(standard)
                let legacyExists = try directoryExists(legacy)
                let standardNamespace = standard.appendingPathComponent(StationSyncFiles.directoryName, isDirectory: true)
                let namespaceExists = standardExists ? try directoryExists(standardNamespace) : false
                if legacyExists && namespaceExists { throw MacICloudSetupError.multipleLibraries }
                if legacyExists {
                    try validateNamespace(legacy)
                    return Prepared(folder: root, createdDirectory: nil)
                }
                if namespaceExists {
                    try validateNamespace(standardNamespace)
                    return Prepared(folder: standard, createdDirectory: nil)
                }
                if standardExists {
                    let contents = try FileManager.default.contentsOfDirectory(at: standard, includingPropertiesForKeys: nil)
                    guard contents.allSatisfy({ [".DS_Store", ".localized"].contains($0.lastPathComponent) }) else {
                        throw MacICloudSetupError.occupied
                    }
                    return Prepared(folder: standard, createdDirectory: nil)
                }
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: standard, withIntermediateDirectories: false)
                return Prepared(folder: standard, createdDirectory: standard)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
                                                    .ubiquitousItemDownloadingStatusKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw MacICloudSetupError.occupied }
        if values.isUbiquitousItem == true, let status = values.ubiquitousItemDownloadingStatus, status != .current {
            throw MacICloudSetupError.waitingForDownload
        }
    }

    private static func directoryExists(_ url: URL) throws -> Bool {
        let fm = FileManager.default
        // Check the parent enumeration instead of treating permission errors as absence.
        let names = try fm.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        if names.contains("." + url.lastPathComponent + ".icloud") { throw MacICloudSetupError.waitingForDownload }
        guard names.contains(url.lastPathComponent) else { return false }
        try requireDirectory(url)
        return true
    }

    private static func validateNamespace(_ url: URL) throws {
        for file in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            let name = file.lastPathComponent
            if name.hasSuffix(".icloud") { throw MacICloudSetupError.waitingForDownload }
            if [".DS_Store", ".localized"].contains(name) { continue }
            guard name == StationSyncFiles.currentName || (file.pathExtension == "json" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil) else {
                throw MacICloudSetupError.occupied
            }
        }
    }
}
#endif
