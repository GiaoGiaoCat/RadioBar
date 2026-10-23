import AppKit
import Foundation

@MainActor private final class Client {
    let file: URL
    let suite = "RadioBar.SinglePublisher." + UUID().uuidString
    let defaults: UserDefaults
    var controller: MacStationSyncController!
    var blocked = false
    var recoveryBlocked = false
    init(_ root: URL) throws {
        file = root.appendingPathComponent("stations.json")
        defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.document("Original").data.write(to: file)
        defaults.set(0.37, forKey: "volume"); defaults.set("english", forKey: "appLanguage")
        reopen()
    }
    static func document(_ name: String) throws -> StationDocument {
        let object: [String: Any] = ["schemaVersion": 1, "unknown": ["keep": true], "stations": [
            ["id": "custom.test", "name": ["zh": "测试电台", "en": name], "urls": ["https://fixture.invalid/live?token=a%2Bb"], "extra": 17]
        ]]
        return try StationDocument(data: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
    func reopen(automatic: Bool = false) {
        recoveryBlocked = false
        controller = MacStationSyncController(localFile: file, defaults: defaults, automatic: automatic,
            canPublish: { [weak self] in self?.blocked == false }, recoveryChanged: { [weak self] in self?.recoveryBlocked = $0 })
    }
    func edit(_ name: String, accepted: Bool = true) throws {
        try Self.document(name).data.write(to: file, options: .atomic)
        if accepted { controller.localConfigurationChanged(documentChanged: true) }
    }
    func close() { controller = nil; defaults.removePersistentDomain(forName: suite) }
}

@main @MainActor struct MacStationSyncTests {
    static var checks = 0
    static let fm = FileManager.default
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { fatalError(message) }; checks += 1
    }
    static func publication(_ cloud: URL) throws -> StationPublication {
        try StationPublication.decode(Data(contentsOf: cloud.appendingPathComponent("RadioBarSync/current.json")))
    }
    static func file(_ cloud: URL) -> URL { cloud.appendingPathComponent("RadioBarSync/current.json") }
    private static func connect(_ client: Client, _ cloud: URL) async throws {
        await client.controller.prepareAssociation(to: cloud)
        try check(client.controller.review != nil, "association requires confirmation: \(client.controller.errorText?.en ?? "")")
        await client.controller.confirmReview()
        try check(client.controller.isLinked && client.controller.status == .checked, "publication succeeded: \(client.controller.errorText?.en ?? "")")
    }
    static func main() async throws {
        let root = fm.temporaryDirectory.appendingPathComponent("RadioBar-PublisherTests-" + UUID().uuidString)
        let cloud = root.appendingPathComponent("cloud")
        try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let a = try Client(root.appendingPathComponent("local")); defer { a.close() }
        var opened: URL?
        func openSyncFolder(succeeds: Bool = true) -> Bool {
            do {
                try a.controller.openSyncFolder { opened = $0; return succeeds }
                return true
            } catch { return false }
        }
        try check(!openSyncFolder() && opened == nil, "unlinked folder never opens a guessed location")
        await a.controller.prepareAssociation(to: cloud)
        try check(a.controller.review != nil && !fm.fileExists(atPath: file(cloud).path), "preview has no cloud writes")
        a.controller.cancelReview()
        try check(!a.controller.isLinked && !fm.fileExists(atPath: a.controller.bindingFile.path), "cancel keeps local state")
        let initial = try Data(contentsOf: a.file)
        try await connect(a, cloud)
        let first = try publication(cloud)
        try check(first.sequence == 1 && first.configuration.document.data == initial, "first full configuration")
        try check(first.publishedAt > 1_700_000_000, "Unix timestamp")
        try check(Data(contentsOf: a.file) == initial, "publish never rewrites local JSON")
        let bytes = try Data(contentsOf: file(cloud))
        let receipt = try Data(contentsOf: a.controller.bindingFile)
        let namespace = cloud.appendingPathComponent("RadioBarSync")
        var rejectedLocalFolder = false
        do { try a.controller.openSyncFolder() } catch { rejectedLocalFolder = true }
        try check(rejectedLocalFolder, "iCloud folder action refuses a local directory without opening Finder")
        try check(openSyncFolder() && opened?.resolvingSymlinksInPath() == namespace.resolvingSymlinksInPath(), "open exact authorized sync namespace")
        try check(!openSyncFolder(succeeds: false), "Finder refusal is reported")
        let moved = cloud.appendingPathComponent("saved-sync")
        try fm.moveItem(at: namespace, to: moved)
        opened = nil
        try check(!openSyncFolder() && opened == nil && !fm.fileExists(atPath: namespace.path), "missing namespace is not recreated or replaced by a fallback")
        try fm.createSymbolicLink(at: namespace, withDestinationURL: moved)
        try check(!openSyncFolder() && opened == nil, "sync folder symlinks are refused")
        try fm.removeItem(at: namespace); try fm.moveItem(at: moved, to: namespace)
        try check(Data(contentsOf: file(cloud)) == bytes && Data(contentsOf: a.controller.bindingFile) == receipt, "opening folders never changes publication or binding")
        await a.controller.synchronize()
        try check(Data(contentsOf: file(cloud)) == bytes, "no-op does not rewrite current.json")
        try a.edit("Changed")
        await a.controller.synchronize()
        try check(publication(cloud).sequence == 2, "accepted edit increments once")
        try check(publication(cloud).configuration.document.data == Data(contentsOf: a.file), "unknown fields and URL bytes preserved")
        a.defaults.set("random", forKey: "defaultStation")
        a.controller.localConfigurationChanged(); await a.controller.synchronize()
        try check(publication(cloud).sequence == 3 && publication(cloud).configuration.preferences.defaultStation == "random", "preferences publish")
        try check(a.defaults.double(forKey: "volume") == 0.37 && a.defaults.string(forKey: "appLanguage") == "english", "device prefs untouched")
        let beforeExternal = try Data(contentsOf: file(cloud))
        try a.edit("External", accepted: false); await a.controller.synchronize()
        try check(a.controller.status == .unavailable && Data(contentsOf: file(cloud)) == beforeExternal, "unloaded external edits never publish")
        a.controller.localConfigurationChanged(documentChanged: true); await a.controller.synchronize()
        try check(publication(cloud).sequence == 4, "successful reload accepts document")
        a.blocked = true; try a.edit("WhileEditing"); await a.controller.synchronize()
        try check(publication(cloud).sequence == 4, "active editor delays publication")
        a.blocked = false; await a.controller.synchronize()
        try check(publication(cloud).sequence == 5, "publish after editing")
        // Crash/offline after reserving a sequence, then further edits and restart.
        a.controller.beforePublicationForTesting = { throw CocoaError(.fileWriteNoPermission) }
        try a.edit("Offline"); await a.controller.synchronize()
        try check(publication(cloud).sequence == 5, "failed publication preserves cloud")
        try a.edit("AfterRestart"); a.reopen()
        await a.controller.synchronize()
        try check(publication(cloud).sequence == 6 && publication(cloud).configuration.document == Client.document("Offline"), "reserved publication replayed exactly")
        await a.controller.synchronize()
        try check(publication(cloud).sequence == 7 && publication(cloud).configuration.document == Client.document("AfterRestart"), "new edit receives next sequence")
        a.controller.disconnect(); a.reopen()
        try check(!a.controller.isLinked, "disconnect survives restart")
        opened = nil
        try check(!openSyncFolder() && opened == nil, "stopped sync cannot open a retained folder receipt")
        try await connect(a, cloud)
        try check(publication(cloud).sequence == 7, "reconnect does not reset sequence")
        try fm.removeItem(at: file(cloud)); await a.controller.synchronize()
        try check(publication(cloud).sequence == 7, "missing cloud file replays exact saved version")
        // Unexpected remote content never modifies local configuration or gets silently overwritten.
        let own = try publication(cloud)
        let remote = try StationPublication(libraryID: own.libraryID, sequence: own.sequence + 10, configuration: SharedStationConfiguration(document: Client.document("Remote"), preferences: own.configuration.preferences))
        try remote.encoded().write(to: file(cloud), options: .atomic)
        let localBefore = try Data(contentsOf: a.file)
        await a.controller.synchronize()
        try check(a.controller.status == .unavailable && publication(cloud) == remote, "unexpected cloud content stops publication")
        try check(Data(contentsOf: a.file) == localBefore, "Mac never adopts remote")
        await a.controller.prepareAssociation(to: cloud)
        try check(a.controller.review?.existing == remote, "reselection previews existing configuration")
        a.controller.cancelReview()
        try check(publication(cloud) == remote, "cancel keeps remote")
        try await connect(a, cloud)
        try check(publication(cloud).sequence == remote.sequence + 1, "explicit takeover advances sequence")
        try check(fm.contentsOfDirectory(atPath: a.file.deletingLastPathComponent().path).contains { $0.hasPrefix("station-publication.backup-") }, "replaced publication archived locally")
        let good = try Data(contentsOf: file(cloud))
        for invalid in [Data("broken".utf8), Data(repeating: 32, count: StationPublication.maximumBytes + 1)] {
            try invalid.write(to: file(cloud), options: .atomic); await a.controller.synchronize()
            try check(a.controller.status == .unavailable && Data(contentsOf: file(cloud)) == invalid, "invalid cloud preserved")
        }
        try good.write(to: file(cloud), options: .atomic)
        let placeholder = cloud.appendingPathComponent("RadioBarSync/.current.json.icloud")
        try Data().write(to: placeholder); await a.controller.synchronize()
        try check(a.controller.status == .unavailable && Data(contentsOf: file(cloud)) == good, "placeholder not treated as missing")
        try fm.removeItem(at: placeholder)
        try fm.removeItem(at: file(cloud)); try fm.createSymbolicLink(at: file(cloud), withDestinationURL: a.file)
        await a.controller.synchronize()
        try check(a.controller.status == .unavailable && Data(contentsOf: a.file) == localBefore, "symlink refused")
        try fm.removeItem(at: file(cloud)); try good.write(to: file(cloud))
        // A stopped in-flight job cannot reactivate the association.
        a.controller.beforePublicationForTesting = { a.controller.disconnect() }
        try a.edit("Cancelled"); await a.controller.synchronize()
        try check(!a.controller.isLinked && Data(contentsOf: file(cloud)) == good, "stop cancels before cloud commit")
        a.reopen(); try await connect(a, cloud)
        try check(publication(cloud).sequence == remote.sequence + 3, "reconnect respects reserved sequence")
        let old = namespace.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
        try Data("old UUID history, ignored".utf8).write(to: old)
        await a.controller.synchronize()
        try check(Data(contentsOf: old) == Data("old UUID history, ignored".utf8), "old cloud history untouched")
        // Invalid private state cannot be overwritten by a routine sync or new association.
        let association = a.controller.bindingFile, saved = try Data(contentsOf: association)
        try Data("{\"schemaVersion\":99}".utf8).write(to: association, options: .atomic)
        try a.edit("PrivateChanged"); await a.controller.synchronize()
        try check(Data(contentsOf: association) == Data("{\"schemaVersion\":99}".utf8), "external association protected")
        try saved.write(to: association, options: .atomic); a.reopen()
        await a.controller.prepareAssociation(to: a.file.deletingLastPathComponent())
        try check(a.controller.review == nil, "local and cloud directories cannot overlap")
        try await migration(root, cloud: root.appendingPathComponent("legacy-cloud"))
        try backupChecks(root.appendingPathComponent("backups"))
        try await automaticChecks(root)
        print("PASS: \(checks) single Mac publication / migration / backup checks")
    }
    static func migration(_ root: URL, cloud: URL) async throws {
        try fm.createDirectory(at: cloud.appendingPathComponent("RadioBarSync"), withIntermediateDirectories: true)
        let a = try Client(root.appendingPathComponent("legacy-local")); defer { a.close() }
        let bookmark = try StationSyncDirectory(selecting: cloud).bookmark, library = UUID()
        let legacy: [String: Any] = ["schemaVersion": 1, "bookmark": bookmark.base64EncodedString(), "folderName": "legacy", "state": ["schemaVersion": 1, "libraryID": library.uuidString, "deviceID": UUID().uuidString]]
        let bytes = try JSONSerialization.data(withJSONObject: legacy)
        try bytes.write(to: a.controller.bindingFile); a.reopen()
        try check(!a.controller.isLinked && a.controller.errorText != nil, "v1 asks to confirm new publisher")
        try await connect(a, cloud)
        try check(publication(cloud).libraryID == library && publication(cloud).sequence == 1, "v1 library preserved")
        let archives = try fm.contentsOfDirectory(at: a.file.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("station-sync-association.backup-") }
        try check(archives.contains { (try? Data(contentsOf: $0)) == bytes }, "v1 receipt archived exactly")
        let original = try SharedStationConfiguration(document: StationDocument(data: Data(contentsOf: a.file)), preferences: .capture(from: a.defaults))
        let candidate = SharedStationConfiguration(document: try Client.document("RecoveredLegacyChoice"), preferences: original.preferences)
        var pending = legacy
        pending["application"] = ["schemaVersion": 1, "libraryID": library.uuidString, "configuration": try JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate))]
        pending["expectedApplication"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
        try JSONSerialization.data(withJSONObject: pending).write(to: a.controller.bindingFile, options: .atomic)
        _ = try MacStationSyncController.recoverBeforeStartup(file: a.file, defaults: a.defaults)
        try check(Data(contentsOf: a.file) == candidate.document.data, "previously confirmed old remote application completed before migration")
        try check(a.defaults.double(forKey: "volume") == 0.37, "legacy recovery leaves volume")
        // A malformed previously confirmed application must block edits even without a journal.
        pending["application"] = ["configuration": ["invalid": true]]
        try JSONSerialization.data(withJSONObject: pending).write(to: a.controller.bindingFile, options: .atomic)
        a.reopen()
        try check(a.recoveryBlocked, "invalid legacy application cannot bypass recovery protection")
        try Data("broken journal".utf8).write(to: a.file.deletingLastPathComponent().appendingPathComponent("station-sync-transaction.json"))
        a.reopen()
        try check(a.recoveryBlocked, "invalid old transaction blocks editing")
        let journal = a.file.deletingLastPathComponent().appendingPathComponent("station-sync-transaction.json")
        try fm.removeItem(at: journal)
        try fm.createSymbolicLink(at: journal, withDestinationURL: root.appendingPathComponent("missing-recovery-target"))
        a.reopen()
        try check(a.recoveryBlocked, "dangling old transaction link cannot bypass recovery protection")
    }
    static func backupChecks(_ root: URL) throws {
        let a = try Client(root); defer { a.close() }
        let old = root.appendingPathComponent("stations.backup-edit-" + UUID().uuidString + ".json")
        try Data("old retained".utf8).write(to: old)
        for i in 0..<8 {
            let bytes = try Data(contentsOf: a.file)
            let backup = try StationLocalBackup.create(for: a.file, original: bytes)
            try Client.document("Edit\(i)").data.write(to: a.file, options: .atomic)
            _ = StationLocalBackup.completed(backup, for: a.file)
        }
        var names = try fm.contentsOfDirectory(atPath: root.path)
        try check(names.filter { $0.hasPrefix("stations.backup-v2-") }.count == 5, "fixed last five completed backups")
        try check(Data(contentsOf: old) == Data("old retained".utf8), "legacy backups never pruned")
        let pending = try StationLocalBackup.create(for: a.file, original: Data(contentsOf: a.file))
        let unknown = root.appendingPathComponent("stations.backup-v2-user.json")
        try Data("user file".utf8).write(to: unknown)
        let journal = root.appendingPathComponent("station-sync-transaction.json")
        try Data().write(to: journal)
        let completed = try StationLocalBackup.create(for: a.file, original: Data(contentsOf: a.file))
        _ = StationLocalBackup.completed(completed, for: a.file)
        names = try fm.contentsOfDirectory(atPath: root.path)
        try check(names.filter { $0.hasPrefix("stations.backup-v2-") && $0 != unknown.lastPathComponent }.count == 6, "recovery prevents rotation")
        try check(fm.fileExists(atPath: pending.path) && Data(contentsOf: unknown) == Data("user file".utf8), "failed backup and unknown file preserved")
        try fm.removeItem(at: journal)
        var session = try StationEditorSession(file: a.file, station: StationConfiguration.decode(Data(contentsOf: a.file))[0])
        session.nameEN = "ActualSave"
        _ = try session.save(deleting: false)
        try check(fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("stations.backup-v2-") && $0 != unknown.lastPathComponent }.count == 5, "actual editor rotates on successful save")
    }
    static func automaticChecks(_ root: URL) async throws {
        let a = try Client(root.appendingPathComponent("auto-local")); defer { a.close() }
        let cloud = root.appendingPathComponent("auto-cloud")
        try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
        try await connect(a, cloud); a.reopen(automatic: true)
        try a.edit("Automatic")
        for _ in 0..<200 {
            if try publication(cloud).sequence == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try check(publication(cloud).sequence == 2 && publication(cloud).configuration.document == Client.document("Automatic"), "accepted changes automatically publish")
    }
}
