import Foundation

@main @MainActor struct StationSyncTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { fatalError(message) }; checks += 1
    }
    static func rejects(_ message: String, _ action: () throws -> Void) throws {
        do { try action() } catch { checks += 1; return }; fatalError(message)
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RadioBar-V2-" + UUID().uuidString)
        let suite = "RadioBar.V2." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let fixture = try Data(contentsOf: URL(fileURLWithPath: "docs/examples/station-current-v2.json"))
        let first = try StationPublication.decode(fixture)
        try check(first.schemaVersion == 2 && first.sequence == 1, "v2 fixture")
        try check(first.publishedAt == 1792627200, "Unix seconds, not reference date")
        try check(first.configuration.document.data == Data("{\"schemaVersion\":1,\"stations\":[]}".utf8), "raw JSON survives")
        try check(first.configuration.document.stations.isEmpty, "valid empty ordinary list")
        try check(StationCatalog.merge(first.configuration.document.stations).count == 2, "built-ins remain")
        try check(StationPublication.decode(first.encoded()) == first, "round trip")
        var object = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
        for (key, bad): (String, Any) in [("schemaVersion", 1), ("schemaVersion", 3), ("schemaVersion", true), ("sequence", true), ("sequence", 0), ("sequence", -1), ("sequence", 1.5), ("sequence", 9_007_199_254_740_992 as Int64), ("libraryID", "not-uuid"), ("publishedAt", -1), ("publishedAt", true)] {
            var changed = object; changed[key] = bad
            try rejects("invalid \(key): \(bad)") { _ = try StationPublication.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        for field in ["schemaVersion", "sequence", "libraryID", "configuration", "publishedAt"] {
            var changed = object; changed.removeValue(forKey: field)
            try rejects("missing \(field)") { _ = try StationPublication.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        try rejects("size limit") { _ = try StationPublication.decode(Data(repeating: 32, count: StationPublication.maximumBytes + 1)) }
        try rejects("finite date") { _ = try StationPublication(libraryID: first.libraryID, sequence: 1, configuration: first.configuration, publishedAt: .infinity) }
        try rejects("bad prefs") {
            var changed = object
            changed["configuration"] = ["document": object["configuration"].flatMap { ($0 as? [String: Any])?["document"] }!, "preferences": ["orderIDs": ["builtin.kiss", "builtin.kiss"], "visibilityOverrides": [:]]]
            _ = try StationPublication.decode(JSONSerialization.data(withJSONObject: changed))
        }
        object["configuration"] = ["document": "not-base64", "preferences": ["orderIDs": [], "visibilityOverrides": [:]]]
        try rejects("invalid document") { _ = try StationPublication.decode(JSONSerialization.data(withJSONObject: object)) }
        let file = root.appendingPathComponent("stations.json")
        try first.configuration.document.data.write(to: file)
        try check(StationSyncFiles.read(file, maximumBytes: 100) == first.configuration.document.data, "bounded read")
        try rejects("bounded file read") { _ = try StationSyncFiles.read(file, maximumBytes: 3) }
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try rejects("reject symlink read") { _ = try StationSyncFiles.read(link, maximumBytes: 100) }
        try rejects("reject symlink replacement") { try StationSyncFiles.replace(Data(), at: link) }
        try check(Data(contentsOf: file) == first.configuration.document.data, "link target preserved")
        defaults.set(0.37, forKey: "volume"); defaults.set("english", forKey: "appLanguage")
        let original = try SharedStationConfiguration(document: first.configuration.document, preferences: .capture(from: defaults))
        let target = SharedStationConfiguration(document: first.configuration.document, preferences: .init(orderIDs: ["builtin.music-radio", "builtin.kiss"], visibilityOverrides: [:], defaultStation: "random"))
        let transaction = StationConfigurationTransaction(file: file, defaults: defaults)
        try transaction.prepare(target, expecting: original)
        try check(FileManager.default.fileExists(atPath: transaction.journalFile.path), "old durable transaction exists")
        try check(transaction.recover() == target, "old interrupted transaction recovery")
        try check(!FileManager.default.fileExists(atPath: transaction.journalFile.path), "journal removed only after success")
        try check(defaults.double(forKey: "volume") == 0.37 && defaults.string(forKey: "appLanguage") == "english", "device prefs survive recovery")
        try transaction.prepare(original, expecting: target)
        try Data("external".utf8).write(to: file, options: .atomic)
        try rejects("old recovery rejects intervening edits") { _ = try transaction.recover() }
        try check(FileManager.default.fileExists(atPath: transaction.journalFile.path), "failed recovery material retained")
        try check(Data(contentsOf: file) == Data("external".utf8), "external bytes preserved")
        print("PASS: \(checks) v2 protocol / safe I/O / legacy recovery checks")
    }
}
