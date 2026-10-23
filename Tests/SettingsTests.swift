import Foundation

@MainActor
private final class FakeLoginManager: LoginItemManaging {
    var state: LoginItemState = .disabled
    var resultState: LoginItemState = .enabled
    var failure: Error?
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    var requests: [Bool] = []
    var openedSettings = false
    func setEnabled(_ enabled: Bool) async throws {
        requests.append(enabled)
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        state = enabled ? resultState : .disabled
    }
    func openSystemSettings() { openedSettings = true }
}

@main
struct SettingsTests {
    @MainActor private static func editorInputChecks() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RadioBar-EditorInput-" + UUID().uuidString)
        let file = StationCatalog.userFile(in: root)
        let originalCatalogue = StationCatalog.stations
        let suite = "RadioBar.EditorInput." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            StationCatalog.apply(originalCatalogue)
            defaults.removePersistentDomain(forName: suite)
            try? manager.removeItem(at: root)
        }
        let original = try StationCatalog.defaultData()
        _ = try StationCatalog.load(userFile: file, defaultData: original)
        let settings = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        var add = try StationEditorSession(file: file, station: nil)
        add.nameZH = "\u{FEFF}\u{200B}  测试 电台 ☕️ \u{2060}"
        add.nameEN = "\u{200E}  Test Station  \u{200F}"
        add.fullNameZH = "\u{200B}中文 全称\u{FEFF}"
        add.fullNameEN = "\u{2060}Full Name\u{200B}"
        add.categoryZH = "\t 音乐 \u{FEFF}"
        add.categoryEN = "\u{FEFF} Music \n"
        add.frequency = "\u{200B} 96.3 \u{FEFF}"
        let signed = "https://fixture.invalid/live?key=a%2Bb&token=keep%20space&raw=%E2%80%8B"
        add.addresses = "\r\n \t\r\n\u{FEFF}  " + signed + "  \u{200B}\r\n\u{2060}\r\n  https://fixture.invalid/backup  \r\n\r\n"
        let error = await settings.saveStation(add, deleting: false)
        precondition(error == nil)
        let created = Station(rawValue: add.stationID)!
        precondition(created.title.zh == "测试 电台 ☕️" && created.title.en == "Test Station")
        precondition(created.fullName == RadioText("中文 全称", "Full Name"))
        precondition(created.category == RadioText("音乐", "Music") && created.frequencyMHz == "96.3")
        let disk = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let record = (disk["stations"] as! [[String: Any]]).first { $0["id"] as? String == add.stationID }!
        precondition(record["urls"] as? [String] == [signed, "https://fixture.invalid/backup"])
        let saved = try Data(contentsOf: file)
        let prefs = defaults.dictionaryRepresentation() as NSDictionary
        let beforeBackups = try manager.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).count
        var invalid = try StationEditorSession(file: file, station: created)
        for marker in ["\u{200B}", "\u{FEFF}", "\u{2060}", "\u{202E}", "\u{200D}", "\u{FE0F}", "\u{0000}", "\t", " "] {
            invalid.addresses = "\r\n\r\nhttps://fixture.invalid/live?token=private" + marker + "signature"
            let failure = await settings.saveStation(invalid, deleting: false)
            precondition(failure?.en.contains("line 3") == true && failure?.zh.contains("第 3 行") == true)
            precondition(failure?.en.contains("private") == false && !settings.isUpdatingStations)
        }
        for empty in ["\n\r\n\t ", "\u{FEFF}\n\u{200B}\n\u{2060}"] {
            invalid.addresses = empty
            let failure = await settings.saveStation(invalid, deleting: false)
            precondition(failure != nil)
        }
        invalid.addresses = signed
        invalid.nameEN = "\u{FEFF}\u{200B}  \u{2060}"
        let emptyNameError = await settings.saveStation(invalid, deleting: false)
        precondition(emptyNameError != nil)
        invalid.nameEN = "Test Station"
        invalid.fullNameZH = "\u{200B}"
        invalid.fullNameEN = "\u{FEFF}"
        invalid.categoryZH = "\u{2060}"
        invalid.categoryEN = "\u{200B}"
        invalid.frequency = "\u{FEFF}"
        let optionalData = try invalid.candidate(deleting: false)
        let optionalDoc = try JSONSerialization.jsonObject(with: optionalData) as! [String: Any]
        let cleared = (optionalDoc["stations"] as! [[String: Any]]).first { $0["id"] as? String == created.id }!
        precondition(cleared["fullName"] == nil && cleared["category"] == nil && cleared["frequencyMHz"] == nil)
        let afterInvalid = try Data(contentsOf: file)
        let afterBackups = try manager.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).count
        precondition(afterInvalid == saved && beforeBackups == afterBackups && prefs == defaults.dictionaryRepresentation() as NSDictionary)
        // Opening an older file and changing only one language must not normalize its other fields.
        var legacy = disk
        var records = legacy["stations"] as! [[String: Any]]
        let index = records.firstIndex { $0["id"] as? String == created.id }!
        records[index]["name"] = ["zh": "  保留首尾  ", "en": "Old name", "unknown": "preserve"]
        records[index]["urls"] = ["https://fixture.invalid/音乐?token=%2B"]
        legacy["stations"] = records
        try JSONSerialization.data(withJSONObject: legacy).write(to: file, options: .atomic)
        var legacyEdit = try StationEditorSession(file: file, station: created)
        legacyEdit.nameEN = "\u{FEFF} New name \u{200B}"
        let legacyData = try legacyEdit.candidate(deleting: false)
        let legacyDoc = try JSONSerialization.jsonObject(with: legacyData) as! [String: Any]
        let kept = (legacyDoc["stations"] as! [[String: Any]]).first { $0["id"] as? String == created.id }!
        let names = kept["name"] as! [String: String]
        precondition(names["zh"] == "  保留首尾  " && names["en"] == "New name" && names["unknown"] == "preserve")
        precondition(kept["urls"] as? [String] == records[index]["urls"] as? [String])
        print("PASS: editor cleans boundary whitespace/hidden characters, ignores CRLF/blank lines, preserves emoji/normal spaces/signed queries and untouched fields, rejects internal invisible URL characters with original line numbers, and leaves file/preferences/backups unchanged on rejection")
    }

    @MainActor private static func editorChecks() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RadioBar-Editor-" + UUID().uuidString)
        let file = StationCatalog.userFile(in: root)
        let factory = StationCatalog.stations
        let suite = "RadioBar.Editor." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            StationCatalog.apply(factory)
            defaults.removePersistentDomain(forName: suite)
            try? manager.removeItem(at: root)
        }
        _ = try StationCatalog.load(userFile: file, defaultData: StationCatalog.defaultData())
        var document = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        document["futureRoot"] = ["keep": true]
        var entries = document["stations"] as! [[String: Any]]
        entries[0]["futureEntry"] = "preserved"
        var originalName = entries[0]["name"] as! [String: Any]
        originalName["futureLanguage"] = "retained"
        entries[0]["name"] = originalName
        entries[0]["defaultVisible"] = false
        document["stations"] = entries
        try JSONSerialization.data(withJSONObject: document).write(to: file, options: .atomic)
        _ = await AppSettings(defaults: defaults, loginManager: FakeLoginManager()).updateStations(restoring: false, supportDirectory: root)
        let settings = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        let observer = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        var add = try StationEditorSession(file: file, station: nil)
        let oldData = try Data(contentsOf: file)
        let oldPreferences = defaults.dictionaryRepresentation() as NSDictionary
        let invalidError = await settings.saveStation(add, deleting: false)
        precondition(invalidError != nil)
        let unchangedData = try Data(contentsOf: file)
        precondition(unchangedData == oldData && oldPreferences == defaults.dictionaryRepresentation() as NSDictionary)
        add.nameZH = "新电台"; add.nameEN = "New station"
        add.addresses = "https://fixture.invalid/live?token=keep&key=1\nhttps://fixture.invalid/backup"
        let addedError = await settings.saveStation(add, deleting: false)
        precondition(addedError == nil && !settings.isUpdatingStations)
        let added = Station(rawValue: add.stationID)!
        precondition(added.urls[0].query == "token=keep&key=1" && added.urls.count == 2)
        precondition(settings.orderedStations.last == added && observer.orderedStations.last == added)
        let backups = try manager.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("stations.backup-v2-") }
        precondition(backups.count == 1)
        let backupData = try Data(contentsOf: backups[0])
        precondition(backupData == oldData)
        let addedData = try Data(contentsOf: file)
        for builtin in [Station.kiss, .musicRadio] {
            do {
                _ = try StationEditorSession(file: file, station: builtin)
                fatalError("Built-ins cannot be edited or deleted through an editor session")
            } catch is StationConfigurationError { }
        }
        var edit = try StationEditorSession(file: file, station: Station.bcc)
        edit.nameEN = "Edited BCC"; edit.fullNameZH = "中文全称"; edit.fullNameEN = "Full name"
        let editError = await settings.saveStation(edit, deleting: false)
        precondition(editError == nil)
        let editedDoc = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition((editedDoc["futureRoot"] as! [String: Bool])["keep"] == true)
        let editedEntries = editedDoc["stations"] as! [[String: Any]]
        precondition(editedEntries[0]["futureEntry"] as? String == "preserved")
        precondition(editedEntries[0]["defaultVisible"] as? Bool == false)
        precondition((editedEntries[0]["name"] as! [String: Any])["futureLanguage"] as? String == "retained")
        precondition(Station.bcc.title.en == "Edited BCC" && Station.bcc.fullName?.en == "Full name")
        let conflict = try StationEditorSession(file: file, station: added)
        try addedData.write(to: file, options: .atomic)
        let liveBeforeConflict = StationCatalog.stations
        let conflictError = await settings.saveStation(conflict, deleting: true)
        precondition(conflictError?.en.contains("outside") == true)
        let externalData = try Data(contentsOf: file)
        precondition(externalData == addedData && StationCatalog.stations == liveBeforeConflict)
        let failed = try StationEditorSession(file: file, station: added)
        do {
            _ = try failed.save(deleting: true, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            fatalError("Failed write must throw")
        } catch is CocoaError { }
        let afterWriteFailure = try Data(contentsOf: file)
        precondition(afterWriteFailure == addedData)
        // Backup failure must abort before calling the writer.
        var wrote = false
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: file.deletingLastPathComponent().path)
        do {
            _ = try failed.save(deleting: true, write: { _, _ in wrote = true })
            fatalError("Backup failure must throw")
        } catch { }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.deletingLastPathComponent().path)
        precondition(!wrote)
        settings.defaultStation = .station(added)
        for station in settings.visibleStations where station != added { settings.setStationVisible(station, false) }
        let delete = try StationEditorSession(file: file, station: added)
        let deleteError = await settings.saveStation(delete, deleting: true)
        precondition(deleteError == nil && Station(rawValue: added.id) == nil)
        precondition(settings.defaultStation == .lastListened && !settings.visibleStations.isEmpty)
        precondition(observer.orderedStations == settings.orderedStations)
        let missing = file.deletingLastPathComponent().appendingPathComponent("missing.json")
        do { _ = try StationEditorSession(file: missing, station: nil); fatalError("Missing config must not be replaced") } catch { }
        precondition(!manager.fileExists(atPath: missing.path))
        print("PASS: editor validates before writing, preserves metadata/IDs/query strings, backs up exact bytes, rejects external conflicts and built-ins, aborts backup/write failures, and publishes add/edit/delete with repaired references")
    }

    @MainActor private static func reloadCatalogueChecks() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RadioBar-Reload-" + UUID().uuidString)
        let file = StationCatalog.userFile(in: root)
        let factory = StationCatalog.stations
        let suite = "RadioBar.Reload." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            StationCatalog.apply(factory)
            defaults.removePersistentDomain(forName: suite)
            try? manager.removeItem(at: root)
        }
        _ = try StationCatalog.load(userFile: file, defaultData: StationCatalog.defaultData())
        let settings = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        let secondObserver = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        let retained = Station.bcc
        settings.moveStation(retained, relativeTo: .kiss, after: false)
        settings.setStationVisible(.ufo, false)
        settings.defaultStation = .station(.swissJazz)
        defaults.set("swissJazz", forKey: "station")
        func write(_ entries: [[String: Any]]) throws {
            try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "stations": entries], options: .prettyPrinted)
                .write(to: file, options: .atomic)
        }
        func entry(_ id: String, name: String, visible: Bool = true) -> [String: Any] {
            ["id": id, "name": ["zh": name, "en": name], "urls": ["https://fixture.invalid/new.mp3"], "defaultVisible": visible]
        }
        try write([entry("custom.new", name: "New", visible: false), entry("bcc", name: "Renamed"), entry("ufo", name: "UFO")])
        let result = await settings.updateStations(restoring: false, supportDirectory: root)
        guard case .reloaded = result else { fatalError("Valid configuration must apply") }
        precondition(!settings.isUpdatingStations && settings.orderedStations.first?.id == "bcc")
        precondition(settings.orderedStations.first?.menuName.en == "Renamed")
        precondition(settings.orderedStations.last?.id == "custom.new", "New IDs append to existing order")
        precondition(settings.defaultStation == .lastListened && defaults.string(forKey: "defaultStation") == nil)
        precondition(settings.hiddenStations.map(\.id).sorted() == ["custom.new", "ufo"])
        precondition(secondObserver.orderedStations.first?.menuName.en == "Renamed")
        precondition(PlaybackPreferences(defaults: defaults).station == retained)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let previous = settings.orderedStations
        try Data("{ token=private INVALID JSON".utf8).write(to: file, options: .atomic)
        guard case .reloadFailed(let error) = await settings.updateStations(restoring: false, supportDirectory: root) else {
            fatalError("Invalid file must fail")
        }
        precondition(!error.zh.contains("private") && settings.orderedStations == previous)
        precondition(before == defaults.dictionaryRepresentation() as NSDictionary)
        try manager.removeItem(at: file)
        guard case .reloadFailed = await settings.updateStations(restoring: false, supportDirectory: root) else { fatalError("Missing file must fail") }
        precondition(!manager.fileExists(atPath: file.path))
        try write([entry("custom.new", name: "New", visible: false), entry("bcc", name: "Renamed"), entry("ufo", name: "UFO")])
        guard case .unchanged = await settings.updateStations(restoring: false, supportDirectory: root) else { fatalError("Same semantic contents") }
        settings.setStationVisible(Station(rawValue: "custom.new")!, true)
        settings.moveStation(.kiss, relativeTo: .musicRadio, after: true)
        precondition(defaults.stringArray(forKey: StationOrder.preferenceKey)!.contains("swissJazz"), "Reordering must retain removed IDs")
        guard case .restored = await settings.updateStations(restoring: true, supportDirectory: root) else { fatalError("Restore and apply") }
        precondition(Station.allCases.map(\.id) == factory.map(\.id))
        precondition(settings.hiddenStations.contains(.ufo))
        precondition(settings.orderedStations.contains(.swissJazz))
        try write([entry("custom.new", name: "Back", visible: false)])
        _ = await settings.updateStations(restoring: false, supportDirectory: root)
        precondition(settings.isStationVisible(Station(rawValue: "custom.new")!), "Explicit visibility survives removal and re-addition")
        settings.defaultStation = .random
        try write([])
        _ = await settings.updateStations(restoring: false, supportDirectory: root)
        precondition(settings.defaultStation == .random && !settings.visibleStations.isEmpty)
        print("PASS: hot reload publishes complete metadata, appends new IDs, repairs default/last references, preserves latent order/visibility, leaves failed/missing files and preferences unchanged, and applies restored JSON immediately")
    }
    private static func restoreCatalogueChecks() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RadioBar-Restore-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent("stations.json")
        let factory = try StationCatalog.defaultData()
        // Invalid JSON is backed up byte-for-byte too; no user content is discarded.
        let original = Data("{ invalid user JSON\n".utf8)
        try original.write(to: file)
        let liveIDs = Station.allCases.map(\.id)
        guard case .restored(let backup) = StationCatalog.restore(userFile: file) else { fatalError("Restore must succeed") }
        precondition(backup.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        let files = try manager.contentsOfDirectory(atPath: root.path)
        precondition(files.count == 2)
        let backedUp = try Data(contentsOf: backup)
        let restored = try Data(contentsOf: file)
        precondition(backedUp == original && restored == factory)
        precondition(Station.allCases.map(\.id) == liveIDs, "File restore must not mutate live playback catalogue")
        guard case .restored(let second) = StationCatalog.restore(userFile: file) else { fatalError("Repeated restore") }
        precondition(second != backup)
        let secondData = try Data(contentsOf: second)
        precondition(secondData == factory)
        try original.write(to: file)
        guard case .restoreFailed(let failedBackup) = StationCatalog.restore(userFile: file, write: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }) else { fatalError("Write failure must retain backup") }
        let failedData = try Data(contentsOf: failedBackup)
        let unchanged = try Data(contentsOf: file)
        precondition(failedData == original && unchanged == original)
        guard case .restoreFailed(let invalidBackup) = StationCatalog.restore(userFile: file, defaultData: { Data() }) else {
            fatalError("Invalid bundled data must not overwrite user file")
        }
        let invalidBackupData = try Data(contentsOf: invalidBackup)
        precondition(invalidBackupData == original)
        var attemptedWrite = false
        guard case .backupFailed = StationCatalog.restore(userFile: root.appendingPathComponent("missing.json"), write: { _, _ in
            attemptedWrite = true
        }) else { fatalError("Missing source must abort") }
        precondition(!attemptedWrite)
        guard case .backupFailed = StationCatalog.restore(userFile: root) else { fatalError("Directory is not a configuration") }
        // A read-only folder permits reading the source but prevents creating a backup.
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        let backupFailure = StationCatalog.restore(userFile: file, write: { _, _ in attemptedWrite = true })
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        guard case .backupFailed = backupFailure else { fatalError("Backup permission failure must abort") }
        let afterFailure = try Data(contentsOf: file)
        precondition(!attemptedWrite && afterFailure == original)
        print("PASS: restore backs up exact bytes, uses unique sibling files, preserves live catalogue, aborts on backup failure and retains backups on restore failure")
    }
    @MainActor private static func customCatalogueChecks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RadioBar-CustomSettings-" + UUID().uuidString)
        let suite = "RadioBar.CustomSettings." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let file = StationCatalog.userFile(in: root)
        let factory = try StationCatalog.defaultData()
        defer {
            try? factory.write(to: file, options: .atomic)
            _ = StationCatalog.start(defaults: defaults, supportDirectory: root)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        _ = try StationCatalog.load(userFile: file, defaultData: factory)
        func writeEntries(_ ids: [String], name: String = "Custom", visible: Bool = true) throws {
            let entries = ids.map { ["id": $0, "name": ["zh": "自定义电台", "en": name],
                                     "urls": ["https://fixture.invalid/live.mp3"], "defaultVisible": visible] as [String: Any] }
            try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "stations": entries]).write(to: file, options: .atomic)
            precondition(StationCatalog.start(defaults: defaults, supportDirectory: root) == nil)
        }
        try writeEntries(["custom.one", "custom.two"])
        let first = Station(rawValue: "custom.one")!
        let second = Station(rawValue: "custom.two")!
        defaults.set(first.id, forKey: "station")
        defaults.set(second.id, forKey: "defaultStation")
        let settings = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(settings.orderedStations == [.kiss, .musicRadio, first, second])
        precondition(PlaybackPreferences(defaults: defaults).station == second)
        settings.moveStation(first, relativeTo: .kiss, after: false)
        settings.setStationVisible(second, false)
        precondition(settings.defaultStation == .lastListened)
        precondition(PlaybackPreferences(defaults: defaults).station == first)
        try writeEntries(["custom.one", "custom.two", "custom.three"], name: "Renamed")
        let renamed = Station(rawValue: "custom.one")!
        let third = Station(rawValue: "custom.three")!
        let restored = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(renamed == first && renamed.menuName.en == "Renamed")
        precondition(restored.orderedStations == [first, .kiss, .musicRadio, second, third])
        precondition(restored.hiddenStations == [second])
        let random = PlaybackPreferences(defaults: defaults, chooseRandom: { _ in third })
        precondition(random.station == first)
        defaults.set("random", forKey: "defaultStation")
        precondition(PlaybackPreferences(defaults: defaults, chooseRandom: { _ in third }).station == third)
        defaults.set(first.id, forKey: "defaultStation")
        try writeEntries([])
        let removed = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(removed.visibleStations == [.kiss, .musicRadio])
        precondition(PlaybackPreferences(defaults: defaults).station == .kiss)
        removed.setStationVisible(.kiss, false)
        removed.setStationVisible(.musicRadio, false)
        precondition(removed.visibleStations == [.musicRadio])
        defaults.removePersistentDomain(forName: suite)
        try writeEntries(["custom.one", "custom.two"], visible: false)
        let initialHidden = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(initialHidden.hiddenStations == [first, second])
        precondition(initialHidden.visibleStations == [.kiss, .musicRadio])
        initialHidden.setStationVisible(first, true)
        try writeEntries(["custom.one", "custom.two"], visible: true)
        let changedDefaults = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(changedDefaults.isStationVisible(first) && changedDefaults.isStationVisible(second))
        changedDefaults.setStationVisible(second, false)
        try writeEntries(["custom.one", "custom.two"], visible: false)
        let restoredChoices = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(restoredChoices.isStationVisible(first) && !restoredChoices.isStationVisible(second))
        try writeEntries(["custom.one", "custom.two"], visible: true)
        precondition(!AppSettings(defaults: defaults, loginManager: FakeLoginManager()).isStationVisible(second))
        defaults.removeObject(forKey: StationVisibility.overridesKey)
        defaults.set([first.id], forKey: StationVisibility.preferenceKey)
        precondition(StationVisibility.hiddenStations(defaults: defaults) == [first])
        defaults.set(["kiss": false, "musicRadio": true], forKey: StationVisibility.overridesKey)
        StationIDMigration.apply(to: defaults)
        let migrated = defaults.dictionary(forKey: StationVisibility.overridesKey) as! [String: Bool]
        precondition(migrated == ["builtin.kiss": false, "builtin.music-radio": true])
        defaults.set(Dictionary(uniqueKeysWithValues: Station.allCases.map { ($0.id, false) }), forKey: StationVisibility.overridesKey)
        let allHidden = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(allHidden.visibleStations.count == 1)
        let remaining = allHidden.visibleStations[0]
        allHidden.setStationVisible(remaining, false)
        precondition(allHidden.visibleStations == [remaining])
        print("PASS: JSON initial visibility, unmodified defaults follow edits, explicit show/hide survive edits, legacy hidden migration, override ID migration and nonempty menu recovery")
        print("PASS: custom station startup/default/random, rename identity, order/visibility persistence, appended IDs, deletion fallback and built-in-only visibility")
    }

    @MainActor static func main() async throws {
        try await editorInputChecks()
        try await editorChecks()
        try await reloadCatalogueChecks()
        try restoreCatalogueChecks()
        try customCatalogueChecks()
        let suite = "RadioBar.SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = FakeLoginManager()
        let settings = AppSettings(defaults: defaults, loginManager: manager)
        precondition(settings.language == .system && manager.requests.isEmpty)
        precondition(settings.appearance == .system)
        for appearance in AppAppearance.allCases {
            settings.appearance = appearance
            precondition(AppSettings(defaults: defaults, loginManager: manager).appearance == appearance)
        }
        defaults.set("invalid", forKey: AppAppearance.preferenceKey)
        precondition(AppSettings(defaults: defaults, loginManager: manager).appearance == .system)
        settings.appearance = .system
        print("PASS: appearance defaults to system, persists all three choices, and safely handles unknown values")
        precondition(!settings.alwaysShowDockIcon)
        settings.alwaysShowDockIcon = true
        precondition(AppSettings(defaults: defaults, loginManager: manager).alwaysShowDockIcon)
        settings.alwaysShowDockIcon = false
        precondition(!AppSettings(defaults: defaults, loginManager: manager).alwaysShowDockIcon)
        print("PASS: Dock icon defaults to settings-only and persists always-show preference")
        precondition(!settings.animateMenuBarIcon)
        settings.animateMenuBarIcon = true
        precondition(AppSettings(defaults: defaults, loginManager: manager).animateMenuBarIcon)
        settings.animateMenuBarIcon = false
        precondition(!AppSettings(defaults: defaults, loginManager: manager).animateMenuBarIcon)
        print("PASS: menu bar animation defaults off and persists both values")
        precondition(settings.showSleepTimerInMenuBar)
        settings.showSleepTimerInMenuBar = false
        precondition(!AppSettings(defaults: defaults, loginManager: manager).showSleepTimerInMenuBar)
        settings.showSleepTimerInMenuBar = true
        precondition(AppSettings(defaults: defaults, loginManager: manager).showSleepTimerInMenuBar)
        precondition(settings.menuBarDisplay == .iconOnly)
        settings.menuBarDisplay = .iconAndStation
        precondition(AppSettings(defaults: defaults, loginManager: manager).menuBarDisplay == .iconAndStation)
        settings.menuBarDisplay = .iconOnly
        precondition(AppSettings(defaults: defaults, loginManager: manager).menuBarDisplay == .iconOnly)
        defaults.set("invalid", forKey: MenuBarDisplay.preferenceKey)
        precondition(AppSettings(defaults: defaults, loginManager: manager).menuBarDisplay == .iconOnly)
        print("PASS: menu bar display defaults to icon only, persists both modes and handles unknown values")
        precondition(AppLanguage.system.usesChinese(preferredLanguages: ["zh-Hant-TW", "en"]))
        precondition(!AppLanguage.system.usesChinese(preferredLanguages: ["en-US", "zh-Hans"]))
        precondition(AppLanguage.chinese.usesChinese(preferredLanguages: ["en"]))
        precondition(!AppLanguage.english.usesChinese(preferredLanguages: ["zh"]))
        let traditional = RadioText("电台设置：音乐继续播放，连接失败后重试", "Station settings")
        precondition(traditional.value(.traditionalChinese) == "電台設置：音樂繼續播放，連接失敗後重試")
        for identifier in ["zh-Hant", "zh-Hant-TW", "zh-TW", "zh-HK", "zh_MO", "ZH-hant-hk"] {
            precondition(traditional.value(.system, preferredLanguages: [identifier, "en"]) == traditional.value(.traditionalChinese))
        }
        for identifier in ["zh-Hans", "zh-CN", "zh-SG", "zh", "zh-Hans-HK"] {
            precondition(traditional.value(.system, preferredLanguages: [identifier]) == traditional.zh)
        }
        precondition(traditional.value(.system, preferredLanguages: ["en-US", "zh-Hant"]) == traditional.en)
        precondition(traditional.value(.system, preferredLanguages: []) == traditional.en)
        precondition(traditional.value(.chinese, preferredLanguages: ["zh-Hant"]) == traditional.zh)
        precondition(traditional.value(.traditionalChinese, preferredLanguages: ["en"]) == "電台設置：音樂繼續播放，連接失敗後重試")
        precondition(Station.bcc.menuName.value(.traditionalChinese) == "台灣中廣音樂網")
        precondition(RadioError.playback.displayText.value(.traditionalChinese).contains("連接失敗"))
        for language in AppLanguage.allCases {
            settings.language = language
            precondition(AppSettings(defaults: defaults, loginManager: manager).language == language)
        }
        precondition(AppLanguage(rawValue: "chinese") == .chinese)
        print("PASS: generic Traditional Chinese, system script/region detection, explicit overrides and all persisted languages")
        settings.language = .english
        let restored = AppSettings(defaults: defaults, loginManager: manager)
        precondition(restored.language == .english && manager.requests.isEmpty)
        defaults.set("invalid", forKey: AppLanguage.preferenceKey)
        precondition(AppSettings(defaults: defaults, loginManager: manager).language == .system)
        print("PASS: system language fallback and persisted explicit language; startup does not register")

        // An in-flight playback request stays in place when the UI language changes.
        let pending = PendingResolver()
        let radio = RadioPlayer(resolver: pending, defaults: defaults)
        radio.play()
        for _ in 0..<100 {
            if pending.continuation != nil { break }
            await Task.yield()
        }
        precondition(pending.continuation != nil)
        settings.language = .chinese
        precondition(radio.statusText.value(settings.language) == "连接中…")
        settings.language = .traditionalChinese
        precondition(radio.statusText.value(settings.language) == "連接中…")
        precondition(pending.calls == 1 && radio.wantsPlayback)
        settings.language = .english
        precondition(radio.statusText.value(settings.language) == "Connecting…")
        settings.menuBarDisplay = .iconAndStation
        settings.menuBarDisplay = .iconOnly
        precondition(pending.calls == 1 && radio.station == .kiss && radio.wantsPlayback)
        for appearance in AppAppearance.allCases { settings.appearance = appearance }
        precondition(pending.calls == 1 && radio.station == .kiss && radio.wantsPlayback)
        print("PASS: appearance changes preserve the current playback request")
        radio.pause()
        pending.continuation?.resume(throwing: CancellationError())
        pending.continuation = nil
        for station in Station.allCases {
            precondition(!station.displayName.value(.english).isEmpty)
            precondition(!station.resolutionText.value(.english).isEmpty)
        }
        let serviceError: Error = RadioError.playback
        precondition(serviceError.radioDisplayText.en == "The live stream failed. Retry or choose another station")
        precondition(RadioError.timeout.displayText.en.contains("timed out"))
        print("PASS: immediate language switch preserves the playback session; English stations and errors")

        await settings.setLaunchAtLogin(true)
        precondition(settings.loginState == .enabled && settings.loginError == nil)
        await settings.setLaunchAtLogin(false)
        precondition(settings.loginState == .disabled)
        manager.resultState = .requiresApproval
        await settings.setLaunchAtLogin(true)
        precondition(settings.loginState == .requiresApproval && settings.loginState.isOn)
        settings.openLoginSettings()
        precondition(manager.openedSettings)
        manager.state = .enabled
        settings.refreshLoginState()
        precondition(settings.loginState == .enabled)
        manager.failure = NSError(domain: "Fixture", code: 42)
        await settings.setLaunchAtLogin(false)
        precondition(settings.loginState == .enabled && settings.loginError?.en.contains("42") == true)
        precondition(!settings.isUpdatingLogin)
        manager.failure = nil
        await settings.setLaunchAtLogin(false)
        precondition(settings.loginState == .disabled && settings.loginError == nil)
        print("PASS: enable/disable, required approval, external changes and registration failures")

        manager.suspend = true
        let operation = Task { await settings.setLaunchAtLogin(true) }
        for _ in 0..<100 {
            if manager.continuation != nil { break }
            await Task.yield()
        }
        precondition(settings.isUpdatingLogin && manager.continuation != nil)
        let count = manager.requests.count
        await settings.setLaunchAtLogin(false)
        precondition(manager.requests.count == count)
        manager.continuation?.resume()
        await operation.value
        precondition(!settings.isUpdatingLogin && settings.loginState == .requiresApproval)
        print("PASS: overlapping login changes are blocked; tests never register a real login item")
        await startupPlaybackChecks()
        await randomStartupChecks()
        await visibilityChecks()
        await orderingChecks()
    }

    @MainActor private static func orderingChecks() async {
        let suite = "RadioBar.OrderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = FakeLoginManager()
        let settings = AppSettings(defaults: defaults, loginManager: manager)
        precondition(settings.orderedStations == Station.allCases && !settings.hasCustomStationOrder)
        settings.setStationVisible(.ufo, false)
        settings.defaultStation = .station(.bcc)
        let drag = ChannelReorderSession()
        drag.begin(.swissJazz)
        precondition(drag.hover(.kiss, after: false))
        precondition(settings.orderedStations == Station.allCases)
        precondition(defaults.object(forKey: StationOrder.preferenceKey) == nil)
        drag.cancel()
        precondition(drag.source == nil && drag.target == nil && settings.orderedStations == Station.allCases)
        drag.begin(.swissJazz)
        precondition(drag.hover(.kiss, after: false))
        precondition(drag.commit(settings: settings))
        let top = [.swissJazz] + Station.allCases.filter { $0 != .swissJazz }
        precondition(settings.orderedStations == top && settings.hasCustomStationOrder)
        precondition(drag.source == nil && drag.target == nil)
        precondition(AppSettings(defaults: defaults, loginManager: manager).orderedStations == top)
        precondition(settings.visibleStations == top.filter { $0 != .ufo })
        precondition(settings.defaultStation == .station(.bcc) && settings.hiddenStations == [.ufo])
        print("PASS: drag previews do not save; cancel is a no-op; valid drop saves stable IDs and restores ordered visible stations")

        settings.moveStation(.swissJazz, relativeTo: .grooveSalad, after: true)
        precondition(settings.orderedStations == Station.allCases)
        settings.moveStation(.kiss, relativeTo: .swissJazz, after: true)
        precondition(settings.orderedStations.last == .kiss && settings.orderedStations.first == .musicRadio)
        settings.moveStation(.kiss, relativeTo: .musicRadio, after: false)
        precondition(settings.orderedStations == Station.allCases)
        for source in Station.allCases {
            for target in Station.allCases where source != target {
                for after in [false, true] {
                    settings.resetStationOrder()
                    settings.moveStation(source, relativeTo: target, after: after)
                    let result = settings.orderedStations
                    precondition(result.count == Station.allCases.count && Set(result) == Set(Station.allCases))
                    precondition(result.filter { $0 != source } == Station.allCases.filter { $0 != source })
                    let sourceIndex = result.firstIndex(of: source)!
                    let targetIndex = result.firstIndex(of: target)!
                    precondition(after ? sourceIndex == targetIndex + 1 : sourceIndex + 1 == targetIndex)
                }
            }
        }
        print("PASS: all 264 upward/downward and before/after moves preserve uniqueness and unaffected order, including first/last positions")

        settings.moveStation(.ufo, relativeTo: .kiss, after: false)
        precondition(settings.orderedStations.first == .ufo && !settings.visibleStations.contains(.ufo))
        settings.setStationVisible(.ufo, true)
        precondition(settings.visibleStations.first == .ufo)
        settings.setStationVisible(.ufo, false)
        settings.resetStationOrder()
        precondition(settings.orderedStations == Station.allCases && settings.hiddenStations == [.ufo])
        precondition(settings.defaultStation == .station(.bcc) && !settings.hasCustomStationOrder)
        precondition(defaults.object(forKey: StationOrder.preferenceKey) == nil)
        drag.begin(.bcc)
        precondition(!drag.hover(.bcc, after: false) && !drag.commit(settings: settings))
        precondition(settings.orderedStations == Station.allCases)
        drag.begin(.kiss); drag.hover(.bcc, after: false); drag.leave(.bcc)
        precondition(!drag.commit(settings: settings))
        print("PASS: hidden stations can be reordered and restored in place; reset preserves visibility/default; self/outside drops do not reorder")

        defaults.set(["swissJazz", "swissJazz", "unknown", "bcc"], forKey: StationOrder.preferenceKey)
        let repaired: [Station] = [.swissJazz, .bcc] + Station.allCases.filter { $0 != .swissJazz && $0 != .bcc }
        precondition(StationOrder.stations(defaults: defaults) == repaired)
        let restored = AppSettings(defaults: defaults, loginManager: manager)
        precondition(restored.orderedStations == repaired)
        defaults.set("invalid", forKey: StationOrder.preferenceKey)
        precondition(StationOrder.stations(defaults: defaults) == Station.allCases)
        defaults.set([String](), forKey: StationOrder.preferenceKey)
        precondition(StationOrder.stations(defaults: defaults) == Station.allCases)
        print("PASS: duplicates/unknown IDs are removed, missing/new stations appended, invalid/empty order recovers factory order")

        defaults.removeObject(forKey: StationOrder.preferenceKey)
        let launchSettings = AppSettings(defaults: defaults, loginManager: manager)
        launchSettings.moveStation(.swissJazz, relativeTo: .kiss, after: false)
        defaults.set(Station.ufo.rawValue, forKey: "station")
        launchSettings.defaultStation = .lastListened
        precondition(PlaybackPreferences(defaults: defaults).station == .swissJazz)
        launchSettings.defaultStation = .station(.bcc)
        precondition(PlaybackPreferences(defaults: defaults).station == .bcc)
        launchSettings.defaultStation = .random
        let snapshot = PlaybackPreferences(defaults: defaults, chooseRandom: { eligible in
            precondition(eligible == launchSettings.visibleStations)
            precondition(!eligible.contains(.ufo) && Set(eligible).count == eligible.count)
            return eligible.last
        })
        precondition(snapshot.station == .grooveSalad)
        print("PASS: hidden-last fallback follows custom order, fixed default remains fixed, random uses each visible station exactly once")

        launchSettings.defaultStation = .station(.bcc)
        launchSettings.autoPlayOnLaunch = true
        let resolver = PendingResolver()
        let radio = RadioPlayer(resolver: resolver, defaults: defaults)
        await waitForRequest(resolver)
        launchSettings.moveStation(.bcc, relativeTo: .swissJazz, after: false)
        launchSettings.resetStationOrder()
        precondition(resolver.calls == 1 && radio.station == .bcc && radio.wantsPlayback)
        radio.pause()
        let request = resolver.continuation!
        resolver.continuation = nil
        request.resume(throwing: CancellationError())
        await Task.yield()
        print("PASS: sorting/reset keep the active player connection and selected station unchanged")
    }

    @MainActor private static func visibilityChecks() async {
        let suite = "RadioBar.VisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = FakeLoginManager()
        let settings = AppSettings(defaults: defaults, loginManager: manager)
        precondition(settings.visibleStations == Station.allCases && settings.hiddenStations.isEmpty)
        settings.defaultStation = .station(.bcc)
        settings.setStationVisible(.bcc, false)
        precondition(!settings.visibleStations.contains(.bcc))
        precondition(settings.defaultStation == .lastListened)
        precondition(defaults.object(forKey: PlaybackPreferences.defaultStationKey) == nil)
        precondition(settings.stationVisibilityFeedback == .defaultReset)
        settings.dismissStationVisibilityFeedback()
        precondition(settings.stationVisibilityFeedback == nil)
        let restored = AppSettings(defaults: defaults, loginManager: manager)
        precondition(restored.hiddenStations == [.bcc] && restored.visibleStations == settings.visibleStations)
        settings.setStationVisible(.bcc, true)
        precondition(settings.visibleStations == Station.allCases)
        precondition(settings.stationVisibilityFeedback == nil, "Ordinary visibility changes must remain quiet")
        print("PASS: upgrade shows all stations; hiding/showing persists by stable ID, restores original order, and resets a hidden fixed default")

        settings.setStationVisible(.bcc, false)
        settings.setStationVisible(.grooveSalad, false)
        settings.defaultStation = .random
        let expected = Station.allCases.filter { $0 != .bcc && $0 != .grooveSalad }
        for candidate in expected {
            let snapshot = PlaybackPreferences(defaults: defaults, chooseRandom: { eligible in
                precondition(eligible == expected)
                return candidate
            })
            precondition(snapshot.station == candidate)
        }
        defaults.set(Station.bcc.rawValue, forKey: "station")
        precondition(PlaybackPreferences(defaults: defaults, chooseRandom: { _ in .bcc }).station == .kiss)
        settings.defaultStation = .lastListened
        precondition(PlaybackPreferences(defaults: defaults).station == .kiss)
        defaults.set(Station.bcc.rawValue, forKey: PlaybackPreferences.defaultStationKey)
        precondition(PlaybackPreferences(defaults: defaults).station == .kiss)
        precondition(AppSettings(defaults: defaults, loginManager: manager).defaultStation == .lastListened)
        print("PASS: random receives only visible stations; hidden last/default and an invalid random result fall back to a visible station")

        for station in Station.allCases where station != .swissJazz { settings.setStationVisible(station, false) }
        precondition(settings.visibleStations == [.swissJazz])
        precondition(!settings.canHideStation(.swissJazz) && settings.canHideStation(.bcc))
        let beforeBlockedHide = defaults.dictionaryRepresentation() as NSDictionary
        settings.setStationVisible(.swissJazz, false)
        precondition(settings.visibleStations == [.swissJazz])
        precondition(settings.stationVisibilityFeedback == .lastVisible)
        precondition(beforeBlockedHide == defaults.dictionaryRepresentation() as NSDictionary,
                     "Rejected last-visible hide must not save any preference")
        precondition(StationVisibilityFeedback.lastVisible.text.value(.traditionalChinese).contains("顯示"))
        settings.dismissStationVisibilityFeedback()
        settings.setStationVisible(.bcc, true)
        precondition(settings.visibleStations == [.bcc, .swissJazz])
        settings.setStationVisible(.swissJazz, false)
        precondition(settings.visibleStations == [.bcc])
        precondition(settings.stationVisibilityFeedback == nil)
        print("PASS: final visible station cannot be hidden; restoring a hidden station allows another to be hidden")

        defaults.removeObject(forKey: StationVisibility.overridesKey)
        defaults.set(Station.allCases.map(\.rawValue) + ["unknown-future-station"], forKey: StationVisibility.preferenceKey)
        precondition(StationVisibility.visibleStations(defaults: defaults) == [.kiss])
        precondition(AppSettings(defaults: defaults, loginManager: manager).visibleStations == [.kiss])
        defaults.set(["unknown-future-station"], forKey: StationVisibility.preferenceKey)
        precondition(StationVisibility.visibleStations(defaults: defaults) == Station.allCases)
        defaults.set("invalid-type", forKey: StationVisibility.preferenceKey)
        precondition(StationVisibility.visibleStations(defaults: defaults) == Station.allCases)
        defaults.removeObject(forKey: StationVisibility.preferenceKey)
        print("PASS: corrupt all-hidden, unknown IDs and invalid preference types retain a usable station list")

        let liveSettings = AppSettings(defaults: defaults, loginManager: manager)
        liveSettings.defaultStation = .station(.bcc)
        liveSettings.autoPlayOnLaunch = true
        let resolver = PendingResolver()
        let radio = RadioPlayer(resolver: resolver, defaults: defaults)
        await waitForRequest(resolver)
        let request = resolver.continuation!
        liveSettings.setStationVisible(.bcc, false)
        precondition(radio.station == .bcc && radio.wantsPlayback && resolver.calls == 1)
        precondition(resolver.continuation != nil && !liveSettings.visibleStations.contains(radio.station))
        let nextLaunch = PlaybackPreferences(defaults: defaults)
        precondition(nextLaunch.station == .kiss && nextLaunch.autoPlayOnLaunch)
        radio.pause()
        resolver.continuation = nil
        request.resume(throwing: CancellationError())
        await Task.yield()
        precondition(!radio.wantsPlayback)
        print("PASS: hiding an active station does not cancel/restart its connection; next launch excludes it, and Pause still works")
    }

    @MainActor private static func randomStartupChecks() async {
        let suite = "RadioBar.RandomStartupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        defaults.set(Station.bcc.rawValue, forKey: "station")
        settings.defaultStation = .random
        precondition(AppSettings(defaults: defaults, loginManager: FakeLoginManager()).defaultStation == .random)
        for candidate in Station.allCases {
            var draws = 0
            let snapshot = PlaybackPreferences(defaults: defaults, chooseRandom: { stations in
                draws += 1
                precondition(stations == Station.allCases)
                return candidate
            })
            precondition(snapshot.station == candidate && !snapshot.autoPlayOnLaunch)
            precondition(snapshot.station == candidate && draws == 1)
            precondition(defaults.string(forKey: PlaybackPreferences.defaultStationKey) == "random")
        }
        let silentResolver = PendingResolver()
        let silent = RadioPlayer(resolver: silentResolver, defaults: defaults)
        precondition(Station.allCases.contains(silent.station) && !silent.wantsPlayback && silentResolver.calls == 0)
        print("PASS: random default persists, all twelve stations are eligible, one draw per launch snapshot; autoplay off stays silent")

        let selectedSilently = silent.station
        settings.autoPlayOnLaunch = true
        let resolver = PendingResolver()
        let radio = RadioPlayer(resolver: resolver, defaults: defaults)
        await waitForRequest(resolver)
        let selected = radio.station
        precondition(Station.allCases.contains(selected) && resolver.stations == [selected])
        settings.defaultStation = .station(.kiss)
        settings.defaultStation = .random
        precondition(resolver.calls == 1 && radio.station == selected && radio.wantsPlayback)
        precondition(silent.station == selectedSilently && silentResolver.calls == 0)
        radio.pause()
        resolver.continuation?.resume(throwing: CancellationError())
        resolver.continuation = nil
        radio.play()
        await waitForRequest(resolver)
        precondition(radio.station == selected && resolver.stations == [selected, selected])
        radio.pause()
        resolver.continuation?.resume(throwing: CancellationError())
        resolver.continuation = nil
        precondition(defaults.string(forKey: PlaybackPreferences.defaultStationKey) == "random")
        print("PASS: random autoplay requests exactly the chosen station; settings changes and pause/resume do not reroll or overwrite the random preference")

        settings.autoPlayOnLaunch = false
        var unexpectedDraws = 0
        for candidate in Station.allCases {
            settings.defaultStation = .station(candidate)
            precondition(defaults.string(forKey: PlaybackPreferences.defaultStationKey) == candidate.rawValue)
            precondition(AppSettings(defaults: defaults, loginManager: FakeLoginManager()).defaultStation == .station(candidate))
            let fixed = PlaybackPreferences(defaults: defaults, chooseRandom: { _ in unexpectedDraws += 1; return nil })
            precondition(fixed.station == candidate)
        }
        settings.defaultStation = .lastListened
        precondition(defaults.object(forKey: PlaybackPreferences.defaultStationKey) == nil)
        let last = PlaybackPreferences(defaults: defaults, chooseRandom: { _ in unexpectedDraws += 1; return nil })
        precondition(last.station == selected && unexpectedDraws == 0)
        print("PASS: all legacy fixed-station values and last-listened mode round-trip unchanged and never invoke random selection")
    }

    @MainActor private static func waitForRequest(_ resolver: PendingResolver) async {
        for _ in 0..<100 {
            if resolver.continuation != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("The startup request did not begin")
    }

    @MainActor private static func startupPlaybackChecks() async {
        let suite = "RadioBar.StartupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(settings.defaultStation == .lastListened && !settings.autoPlayOnLaunch)
        defaults.set(Station.ufo.rawValue, forKey: "station")
        defaults.set(0.31, forKey: "volume")
        let stoppedResolver = PendingResolver()
        let stopped = RadioPlayer(resolver: stoppedResolver, defaults: defaults)
        precondition(stopped.station == .ufo && !stopped.wantsPlayback && stoppedResolver.calls == 0)

        settings.defaultStation = .station(.shanghai)
        let shanghai = RadioPlayer(resolver: PendingResolver(), defaults: defaults)
        precondition(shanghai.station == .shanghai && !shanghai.wantsPlayback)
        precondition(AppSettings(defaults: defaults, loginManager: FakeLoginManager()).defaultStation == .station(.shanghai))
        print("PASS: Shanghai station persists as default and is restored at silent startup")
        settings.defaultStation = .station(.loveRadio)
        let loveRadio = RadioPlayer(resolver: PendingResolver(), defaults: defaults)
        precondition(loveRadio.station == .loveRadio && !loveRadio.wantsPlayback)
        precondition(AppSettings(defaults: defaults, loginManager: FakeLoginManager()).defaultStation == .station(.loveRadio))
        print("PASS: Love Radio persists as default and is restored at silent startup")
        settings.defaultStation = .station(.classic947)
        let classic947 = RadioPlayer(resolver: PendingResolver(), defaults: defaults)
        precondition(classic947.station == .classic947 && !classic947.wantsPlayback)
        precondition(AppSettings(defaults: defaults, loginManager: FakeLoginManager()).defaultStation == .station(.classic947))
        print("PASS: Classic 947 persists as default and is restored at silent startup")

        settings.defaultStation = .station(.musicRadio)
        settings.autoPlayOnLaunch = true
        let restored = AppSettings(defaults: defaults, loginManager: FakeLoginManager())
        precondition(restored.defaultStation == .station(.musicRadio) && restored.autoPlayOnLaunch)
        precondition(stopped.station == .ufo && !stopped.wantsPlayback && stoppedResolver.calls == 0)
        print("PASS: migration preserves last station and silent startup; settings persist without starting or switching playback")

        let resolver = PendingResolver()
        let launched = RadioPlayer(resolver: resolver, defaults: defaults)
        precondition(launched.station == .musicRadio && launched.wantsPlayback && launched.volume == 0.31)
        await waitForRequest(resolver)
        precondition(resolver.stations == [.musicRadio])
        settings.defaultStation = .station(.guangdong)
        settings.autoPlayOnLaunch = false
        precondition(launched.station == .musicRadio && launched.wantsPlayback && resolver.calls == 1)
        precondition(defaults.string(forKey: "station") == Station.musicRadio.rawValue)

        // A manual station switch supersedes the automatic startup request.
        let oldRequest = resolver.continuation!
        resolver.continuation = nil
        launched.select(.bcc)
        await waitForRequest(resolver)
        oldRequest.resume(throwing: CancellationError())
        await Task.yield()
        precondition(resolver.stations == [.musicRadio, .bcc])
        precondition(launched.station == .bcc && launched.wantsPlayback)
        launched.pause()
        resolver.continuation?.resume(throwing: CancellationError())
        resolver.continuation = nil
        await Task.yield()
        precondition(!launched.wantsPlayback && launched.status == "已暂停")
        print("PASS: autoplay requests the configured station once without opening a menu; settings changes preserve playback; switch and pause cancel startup")

        let manualResolver = PendingResolver()
        let manual = RadioPlayer(resolver: manualResolver, defaults: defaults)
        precondition(manual.station == .guangdong && !manual.wantsPlayback && manualResolver.calls == 0)
        manual.play()
        await waitForRequest(manualResolver)
        precondition(manualResolver.stations == [.guangdong])
        manual.pause()
        manualResolver.continuation?.resume(throwing: CancellationError())
        manualResolver.continuation = nil
        settings.defaultStation = .lastListened
        precondition(defaults.object(forKey: PlaybackPreferences.defaultStationKey) == nil)
        let last = RadioPlayer(resolver: PendingResolver(), defaults: defaults)
        precondition(last.station == .guangdong && !last.wantsPlayback)
        defaults.set("removed-station", forKey: PlaybackPreferences.defaultStationKey)
        precondition(RadioPlayer(resolver: PendingResolver(), defaults: defaults).station == .guangdong)
        defaults.set("removed-station", forKey: "station")
        precondition(RadioPlayer(resolver: PendingResolver(), defaults: defaults).station == .kiss)
        print("PASS: default selection applies next launch with autoplay off; manual Play updates last station; missing/invalid stations safely fall back")

        settings.defaultStation = .lastListened
        settings.autoPlayOnLaunch = true
        defaults.set(Station.ufo.rawValue, forKey: "station")
        let lastResolver = PendingResolver()
        let resume = RadioPlayer(resolver: lastResolver, defaults: defaults)
        await waitForRequest(lastResolver)
        precondition(resume.station == .ufo && lastResolver.stations == [.ufo])
        resume.pause()
        lastResolver.continuation?.resume(throwing: CancellationError())
        lastResolver.continuation = nil
        print("PASS: autoplay also supports the last listened station; all startup tests use injected resolvers without network or audio")
    }
}

@MainActor
private final class PendingResolver: StreamURLResolving {
    var calls = 0
    var stations: [Station] = []
    var continuation: CheckedContinuation<StreamAddress, Error>?
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        calls += 1
        stations.append(station)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
