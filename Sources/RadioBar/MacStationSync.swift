import AppKit
import Combine

private enum StationPublishError: Error, Equatable {
    case changed, download, overlap, recovery
    var text: RadioText {
        switch self {
        case .changed: return RadioText("同步文件已变化，已停止覆盖。请检查后重新选择文件夹。", "The sync file changed. Publication stopped. Check it and select the folder again.")
        case .download: return RadioText("同步文件尚未下载完成，请稍后重试。", "The sync file has not finished downloading. Try again shortly.")
        case .overlap: return RadioText("请选择本机配置目录以外的独立文件夹。", "Choose a separate folder outside the local configuration directory.")
        case .recovery: return RadioText("旧版配置尚待恢复，请检查本机配置文件夹并重新启动。", "A previous configuration needs recovery. Check the local configuration folder and restart.")
        }
    }
}

enum MacStationSyncStatus: Equatable {
    case disconnected, waiting, checking, checked, unavailable
    var text: RadioText {
        switch self {
        case .disconnected: return RadioText("尚未设置同步", "Sync is not set up")
        case .waiting: return RadioText("更改已保存在本机，等待发布", "Changes saved locally; waiting to publish")
        case .checking: return RadioText("正在发布配置…", "Publishing configuration…")
        case .checked: return RadioText("配置已发布到同步文件夹", "Configuration published to the sync folder")
        case .unavailable: return RadioText("暂时无法发布，本机配置保留", "Publication unavailable; local configuration kept")
        }
    }
}

struct StationSyncReview: Identifiable {
    let id = UUID()
    let folderName: String
    let local: SharedStationConfiguration
    let existing: StationPublication?
    fileprivate let bookmark: Data
    fileprivate let directory: URL
}

private struct StationPublisherBinding: Codable {
    var schemaVersion = 2
    let bookmark: Data
    let folderName: String
    let libraryID: UUID
    var active = true
    var last: StationPublication?
    var pending: StationPublication?

    func validate() throws {
        guard schemaVersion == 2 else { throw StationSharingError.unsupportedVersion }
        guard !bookmark.isEmpty, folderName.count <= 1024 else { throw StationSharingError.invalidDocument }
        for publication in [last, pending].compactMap({ $0 }) {
            try publication.validate()
            guard publication.libraryID == libraryID else { throw StationSharingError.differentLibrary }
        }
        if let last, let pending {
            guard pending == last || pending.sequence > last.sequence else { throw StationSharingError.invalidDocument }
        }
    }
}

private enum StationPublishFolder {
    static func namespace(_ selected: URL, local: URL) throws -> URL {
        try StationSyncFiles.requireDirectory(selected)
        let result = selected.appendingPathComponent(StationSyncFiles.directoryName, isDirectory: true)
        let cloud = selected.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent(StationSyncFiles.directoryName, isDirectory: true).pathComponents
        let home = local.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard !cloud.starts(with: home), !home.starts(with: cloud) else { throw StationPublishError.overlap }
        let names = try FileManager.default.contentsOfDirectory(atPath: selected.path)
        if names.contains(".RadioBarSync.icloud") { throw StationPublishError.download }
        if names.contains(StationSyncFiles.directoryName) { try StationSyncFiles.requireDirectory(result) }
        return result
    }
    /// Call inside file coordination when replacing current.json.
    static func current(_ directory: URL) throws -> StationPublication? {
        let fm = FileManager.default
        let parentNames = try fm.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path)
        guard parentNames.contains(directory.lastPathComponent) else { return nil }
        try StationSyncFiles.requireDirectory(directory)
        let names = try fm.contentsOfDirectory(atPath: directory.path)
        let file = directory.appendingPathComponent(StationSyncFiles.currentName)
        if names.contains(".current.json.icloud") {
            try? fm.startDownloadingUbiquitousItem(at: file)
            throw StationPublishError.download
        }
        guard names.contains(StationSyncFiles.currentName) else { return nil }
        let values = try file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
            try? fm.startDownloadingUbiquitousItem(at: file)
            throw StationPublishError.download
        }
        return try StationPublication.decode(StationSyncFiles.readCoordinatedContents(file, maximumBytes: StationPublication.maximumBytes))
    }
    static func access<T>(bookmark: Data, local: URL, _ operation: (URL) throws -> T) throws -> T {
        try StationSyncDirectory(bookmark: bookmark).withAccess { selected in
            try operation(namespace(selected, local: local))
        }
    }
    static func read(bookmark: Data, local: URL) throws -> (URL, StationPublication?) {
        try access(bookmark: bookmark, local: local) { directory in
            var result: Result<StationPublication?, Error> = .failure(StationSharingError.unavailable)
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: directory.deletingLastPathComponent(), options: [], error: &error) { _ in
                result = Result { try current(directory) }
            }
            if let error { throw error }
            return (directory, try result.get())
        }
    }
    static func publish(_ publication: StationPublication, expected: StationPublication?, bookmark: Data, local: URL) throws {
        try access(bookmark: bookmark, local: local) { directory in
            try Task.checkCancellation()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            }
            try StationSyncFiles.requireDirectory(directory)
            var result: Result<Void, Error> = .failure(StationSharingError.unavailable)
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: directory.appendingPathComponent(StationSyncFiles.currentName), options: .forReplacing, error: &error) { file in
                result = Result {
                    try Task.checkCancellation()
                    let found = try current(directory)
                    if found == publication { return }
                    guard found == expected else { throw StationPublishError.changed }
                    try StationSyncFiles.replaceCoordinatedContents(publication.encoded(), at: file)
                }
            }
            if let error { throw error }
            try result.get()
        }
    }
}

/// Mac only publishes accepted local data. It never receives a remote configuration.
@MainActor final class MacStationSyncController: ObservableObject {
    @Published private(set) var status: MacStationSyncStatus = .disconnected
    @Published private(set) var isBusy = false
    @Published private(set) var isLinked = false
    @Published private(set) var folderURL: URL?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var errorText: RadioText?
    @Published private(set) var review: StationSyncReview?
    let localFile: URL
    let bindingFile: URL
    private let defaults: UserDefaults
    private let canPublish: () -> Bool
    private let recoveryChanged: (Bool) -> Void
    private let automatic: Bool
    private var binding: StationPublisherBinding?
    private var associationBytes: Data?
    private var acceptedDocument: Data?
    private var legacyLibraryID: UUID?
    private var epoch = UUID()
    private var task: Task<Void, Never>?
    private var observation: NSObjectProtocol?
    private var setup: MacICloudSyncSetup.Prepared?
    private var rerun = false
    #if RADIOBAR_TESTING
    var beforePublicationForTesting: (() async throws -> Void)?
    #endif

    init(localFile: URL, defaults: UserDefaults, automatic: Bool = true,
         canPublish: @escaping () -> Bool = { true }, recoveryChanged: @escaping (Bool) -> Void = { _ in }) {
        self.localFile = localFile; self.defaults = defaults; self.automatic = automatic
        self.canPublish = canPublish; self.recoveryChanged = recoveryChanged
        bindingFile = localFile.deletingLastPathComponent().appendingPathComponent("station-sync-association.json")
        do {
            _ = try Self.recoverBeforeStartup(file: localFile, defaults: defaults)
            acceptedDocument = try StationSyncFiles.read(localFile, maximumBytes: 1_048_576)
            _ = try StationDocument(data: acceptedDocument!)
            try loadBinding()
        } catch { fail(error) }
        if automatic {
            observation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.requestSync(delay: 0) }
            }
            requestSync(delay: 0)
        }
    }
    deinit {
        task?.cancel()
        if let observation { NotificationCenter.default.removeObserver(observation) }
    }

    /// Compatibility only: finish old local transactions before launch preferences/player read them.
    @discardableResult static func recoverBeforeStartup(file: URL, defaults: UserDefaults) throws -> SharedStationConfiguration? {
        let transaction = StationConfigurationTransaction(file: file, defaults: defaults)
        var restored = try transaction.recover()
        let association = file.deletingLastPathComponent().appendingPathComponent("station-sync-association.json")
        guard FileManager.default.fileExists(atPath: association.path) else { return restored }
        let bytes = try StationSyncFiles.read(association, maximumBytes: 24 * 1_048_576)
        guard var root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw StationSharingError.invalidDocument }
        if root["schemaVersion"] as? Int == 1, let rawApplication = root["application"], !(rawApplication is NSNull) {
            do {
                guard let application = rawApplication as? [String: Any], application["schemaVersion"] as? Int == 1,
                      let state = root["state"] as? [String: Any], state["schemaVersion"] as? Int == 1,
                      let library = state["libraryID"] as? String, let libraryID = UUID(uuidString: library),
                      let publishedLibrary = application["libraryID"] as? String, UUID(uuidString: publishedLibrary) == libraryID,
                      let target = application["configuration"], let expected = root["expectedApplication"] else { throw StationPublishError.recovery }
                let candidate = try JSONDecoder().decode(SharedStationConfiguration.self, from: JSONSerialization.data(withJSONObject: target))
                let original = try JSONDecoder().decode(SharedStationConfiguration.self, from: JSONSerialization.data(withJSONObject: expected))
                let current = try SharedStationConfiguration(document: StationDocument(data: StationSyncFiles.read(file, maximumBytes: 1_048_576)), preferences: .capture(from: defaults))
                let normalized = try candidate.normalized()
                if current == normalized { restored = normalized }
                else { restored = try transaction.apply(candidate, expecting: original) }
                root.removeValue(forKey: "application"); root.removeValue(forKey: "expectedApplication")
                try StationSyncFiles.replace(JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]), at: association)
            } catch { throw StationPublishError.recovery }
        }
        return restored
    }

    private func loadBinding() throws {
        guard FileManager.default.fileExists(atPath: bindingFile.path) else { return }
        isLinked = true
        let bytes = try StationSyncFiles.read(bindingFile, maximumBytes: 24 * 1_048_576)
        associationBytes = bytes
        let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        switch root?["schemaVersion"] as? Int {
        case 2:
            let value = try JSONDecoder().decode(StationPublisherBinding.self, from: bytes)
            try value.validate(); binding = value; isLinked = value.active
            folderURL = try? StationPublishFolder.access(bookmark: value.bookmark, local: localFile.deletingLastPathComponent()) { $0 }
            if value.active { status = .waiting }
        case 1:
            guard let encoded = root?["bookmark"] as? String, let bookmark = Data(base64Encoded: encoded), !bookmark.isEmpty,
                  let state = root?["state"] as? [String: Any], state["schemaVersion"] as? Int == 1,
                  let id = state["libraryID"] as? String, let library = UUID(uuidString: id) else { throw StationSharingError.invalidDocument }
            // Keep all old receipts in an archive when the user confirms v2 publication.
            legacyLibraryID = library
            isLinked = false
            folderURL = try StationPublishFolder.access(bookmark: bookmark, local: localFile.deletingLastPathComponent()) { $0 }
            isLinked = false
            errorText = RadioText("请重新设置同步以发布新版 iPhone 配置。旧备份和同步文件保留。", "Set up sync again to publish the new iPhone format. Previous backups and sync files are kept.")
        default: throw StationSharingError.unsupportedVersion
        }
    }
    private func persist(_ value: StationPublisherBinding) throws {
        try value.validate()
        let bytes = try JSONEncoder().encode(value)
        var result: Result<Void, Error> = .failure(StationSharingError.unavailable)
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: bindingFile, options: .forReplacing, error: &error) { file in
            result = Result {
                let exists = FileManager.default.fileExists(atPath: file.path)
                if let previous = associationBytes {
                    guard exists, try StationSyncFiles.readCoordinatedContents(file, maximumBytes: 24 * 1_048_576) == previous else { throw StationSharingError.changedLocally }
                } else if exists { throw StationSharingError.changedLocally }
                try StationSyncFiles.replaceCoordinatedContents(bytes, at: file)
            }
        }
        if let error { throw error }
        try result.get()
        associationBytes = bytes
        binding = value; isLinked = value.active
    }
    private func capture(acceptChanges: Bool = false) throws -> SharedStationConfiguration {
        let bytes = try StationSyncFiles.read(localFile, maximumBytes: 1_048_576)
        let document = try StationDocument(data: bytes)
        if acceptChanges { acceptedDocument = bytes }
        guard bytes == acceptedDocument else { throw StationSharingError.changedLocally }
        return try SharedStationConfiguration(document: document, preferences: .capture(from: defaults)).normalized()
    }
    func localConfigurationChanged(documentChanged: Bool = false) {
        do {
            _ = try capture(acceptChanges: documentChanged)
            if isLinked { status = .waiting; requestSync() }
        } catch { if isLinked { fail(error) } }
    }
    func interactionEnded() { requestSync() }
    func requestSync(delay: Double = 0.7) {
        guard automatic, isLinked, review == nil else { return }
        if isBusy { rerun = true; return }
        task?.cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }
    private func finish(_ token: UUID) {
        guard token == epoch else { return }
        isBusy = false
        if rerun { rerun = false; requestSync() }
    }
    private func current(_ token: UUID) -> Bool { token == epoch && !Task.isCancelled }
    private func contents(_ bookmark: Data) async throws -> (URL, StationPublication?) {
        let local = localFile.deletingLastPathComponent()
        return try await Task.detached(priority: .utility) { try StationPublishFolder.read(bookmark: bookmark, local: local) }.value
    }
    func prepareAssociation(to selected: URL) async {
        guard !isBusy, review == nil, canPublish() else { return }
        let token = epoch; isBusy = true
        defer { finish(token) }
        do {
            let local = try capture()
            let parent = try MacICloudSyncSetup.associationFolder(for: selected)
            let bookmark = try StationSyncDirectory(selecting: parent).bookmark
            let (directory, existing) = try await contents(bookmark)
            guard current(token), canPublish(), try capture() == local else { return }
            review = StationSyncReview(folderName: directory.path, local: local, existing: existing, bookmark: bookmark, directory: directory)
            errorText = nil
        } catch { if current(token) { fail(error) } }
    }
    func prepareICloudAssociation(locateRoot: @escaping @Sendable () throws -> URL = { try MacICloudSyncSetup.locateRoot() }) async -> Bool {
        guard !isLinked, !isBusy, review == nil else { return false }
        do {
            let found = try MacICloudSyncSetup.prepare(in: locateRoot())
            setup = found
            await prepareAssociation(to: found.folder)
            if review == nil { found.discardEmptyDirectory(); setup = nil }
            return false
        } catch {
            fail(error)
            let setupError = error as? MacICloudSetupError
            return setupError == nil || setupError == .unavailable
        }
    }
    func cancelReview() {
        review = nil; setup?.discardEmptyDirectory(); setup = nil
    }
    func confirmReview() async {
        guard let selected = review, !isBusy, canPublish() else { return }
        let token = epoch; isBusy = true
        defer { finish(token) }
        do {
            guard try capture() == selected.local else { throw StationSharingError.changedLocally }
            let (_, existing) = try await contents(selected.bookmark)
            guard current(token) else { return }
            guard existing == selected.existing else { throw StationPublishError.changed }
            let sameFolder = folderURL?.standardizedFileURL == selected.directory.standardizedFileURL
            let prior = sameFolder ? binding : nil
            let library = existing?.libraryID ?? prior?.libraryID ?? (sameFolder ? legacyLibraryID : nil) ?? UUID()
            let last = [prior?.last, prior?.pending, existing].compactMap { $0 }.filter { $0.libraryID == library }.max { $0.sequence < $1.sequence }
            var value = StationPublisherBinding(bookmark: selected.bookmark, folderName: selected.folderName, libraryID: library)
            value.last = existing ?? prior?.last
            if existing?.configuration != selected.local || existing != last {
                value.pending = try StationPublication(libraryID: library, sequence: (last?.sequence ?? 0) + 1, configuration: selected.local)
            }
            // Archive the old private association and explicitly replaced cloud configuration locally.
            if FileManager.default.fileExists(atPath: bindingFile.path) {
                try FileManager.default.copyItem(at: bindingFile, to: bindingFile.deletingLastPathComponent().appendingPathComponent("station-sync-association.backup-" + UUID().uuidString + ".json"))
            }
            if let existing, existing.configuration != selected.local {
                try existing.encoded().write(to: localFile.deletingLastPathComponent().appendingPathComponent("station-publication.backup-" + UUID().uuidString + ".json"), options: .withoutOverwriting)
            }
            try persist(value)
            folderURL = selected.directory; review = nil; setup = nil; epoch = UUID()
            isBusy = false
            await synchronize()
        } catch { if current(token) { fail(error) } }
    }
    func synchronize() async {
        guard isLinked, !isBusy, review == nil else { return }
        guard canPublish() else { status = .waiting; return }
        let token = epoch; isBusy = true; status = .checking; errorText = nil
        defer { finish(token) }
        do {
            guard var value = binding else { throw StationSharingError.unavailable }
            let (directory, found) = try await contents(value.bookmark)
            guard current(token) else { return }
            guard canPublish() else { status = .waiting; return }
            folderURL = directory
            guard found == nil || found == value.last || found == value.pending else { throw StationPublishError.changed }
            let local = try capture()
            if value.pending == nil {
                if value.last?.configuration == local {
                    value.pending = found == nil ? value.last : nil
                } else {
                    value.pending = try StationPublication(libraryID: value.libraryID, sequence: (value.last?.sequence ?? 0) + 1, configuration: local)
                }
                try persist(value) // Reserve the sequence before any cloud write.
            }
            if let publication = value.pending {
                #if RADIOBAR_TESTING
                try await beforePublicationForTesting?()
                guard current(token) else { return }
                #endif
                let bookmark = value.bookmark, parent = localFile.deletingLastPathComponent()
                let operation = Task.detached(priority: .utility) {
                    try StationPublishFolder.publish(publication, expected: found, bookmark: bookmark, local: parent)
                }
                try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
                guard current(token) else { return }
                value.last = publication; value.pending = nil
                try persist(value)
                rerun = try capture() != publication.configuration
            }
            status = rerun ? .waiting : .checked; lastChecked = Date()
        } catch { if current(token) { fail(error) } }
    }
    func openSyncFolder(using open: (URL) -> Bool = { directory in
        guard (try? directory.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true else { return false }
        return NSWorkspace.shared.open(directory)
    }) throws {
        guard isLinked, let value = binding else { throw StationSharingError.unavailable }
        try StationPublishFolder.access(bookmark: value.bookmark, local: localFile.deletingLastPathComponent()) { directory in
            try StationSyncFiles.requireDirectory(directory)
            guard open(directory) else { throw StationSharingError.unavailable }
        }
    }
    func disconnect() {
        do {
            guard var value = binding else { throw StationSharingError.unavailable }
            value.active = false; try persist(value)
            epoch = UUID(); task?.cancel(); rerun = false; isBusy = false
            review = nil; setup?.discardEmptyDirectory(); setup = nil
            status = .disconnected; errorText = nil; lastChecked = nil
            // Keep the private sequence receipt for safe reconnection; no cloud deletion.
        } catch { fail(error) }
    }
    private func fail(_ error: Error) {
        status = .unavailable
        errorText = (error as? StationPublishError)?.text ?? (error as? MacICloudSetupError)?.text ?? (error as? StationSharingError)?.text
            ?? RadioText("请检查同步文件夹的下载状态和访问权限，再重试。", "Check the sync folder download status and permissions, then retry.")
        let journal = localFile.deletingLastPathComponent().appendingPathComponent("station-sync-transaction.json")
        let recovering = FileManager.default.fileExists(atPath: journal.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: journal.path)) != nil
            || (error as? StationPublishError) == .recovery
        recoveryChanged(recovering)
        if recovering { errorText = StationPublishError.recovery.text }
    }
}
