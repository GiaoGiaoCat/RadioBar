import Foundation
import Darwin

/// Identity is stable even when the station's title or addresses change.
struct Station: Identifiable, Hashable {
    let id: String
    let title: RadioText
    let fullName: RadioText?
    let frequencyMHz: String?
    let category: RadioText
    let urls: [URL]
    let defaultVisible: Bool
    var isBuiltIn: Bool { id.hasPrefix("builtin.") }
    var rawValue: String { id }
    var frequencyLabel: String { frequencyMHz.map { "FM \($0)" } ?? "" }
    /// One index rule for playback, connection text and diagnostics; empty lists are safe.
    func sourceIndex(attempt: Int) -> Int? {
        urls.isEmpty ? nil : max(0, attempt) % urls.count
    }
    func sourceName(attempt: Int) -> String {
        guard let index = sourceIndex(attempt: attempt) else { return "—" }
        return index == 0 ? "primary" : "backup"
    }
    static func == (lhs: Station, rhs: Station) -> Bool { lhs.id == rhs.id }
    func hasSameConfiguration(as other: Station) -> Bool {
        id == other.id && title == other.title && fullName == other.fullName && frequencyMHz == other.frequencyMHz
            && category == other.category && urls == other.urls && defaultVisible == other.defaultVisible
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    init(id: String, title: RadioText, fullName: RadioText? = nil, frequencyMHz: String? = nil,
         category: RadioText, urls: [URL] = [], defaultVisible: Bool = true) {
        self.id = id; self.title = title; self.fullName = fullName
        self.frequencyMHz = frequencyMHz; self.category = category; self.urls = urls
        self.defaultVisible = defaultVisible
    }
    init?(rawValue: String) {
        let id = StationIDMigration.canonical(rawValue)
        guard let station = Self.allCases.first(where: { $0.id == id }) else { return nil }
        self = station
    }
    static let kiss = Station(id: "builtin.kiss", title: RadioText("KISS RADIO", "KISS RADIO"),
                              frequencyMHz: "99.9", category: RadioText("音乐 · 流行金曲", "Music · Pop hits"),
                              urls: BuiltinStreams.bundled["builtin.kiss"] ?? [])
    static let musicRadio = Station(id: "builtin.music-radio", title: RadioText("央广音乐之声", "CNR Music Radio"),
                                    fullName: RadioText("央广 Music Radio 音乐之声", "CNR Music Radio"),
                                    frequencyMHz: "90.0", category: RadioText("音乐 · 华语流行", "Music · Mandarin pop"),
                                    urls: BuiltinStreams.bundled["builtin.music-radio"] ?? [])
    static var allCases: [Station] { StationCatalog.stations }

    #if RADIOBAR_TESTING
    // Compatibility conveniences for existing tests/previews; ordinary data lives only in JSON.
    static var bcc: Station { reference("bcc") }
    static var ufo: Station { reference("ufo") }
    static var asiaFM: Station { reference("asiaFM") }
    static var guangdong: Station { reference("guangdong") }
    static var shanghai: Station { reference("shanghai") }
    static var loveRadio: Station { reference("loveRadio") }
    static var classic947: Station { reference("classic947") }
    static var radioParadise: Station { reference("radioParadise") }
    static var grooveSalad: Station { reference("grooveSalad") }
    static var swissJazz: Station { reference("swissJazz") }
    private static func reference(_ id: String) -> Station {
        // A fixture may reference a factory station removed from the user's catalogue.
        (StationCatalog.stations.first { $0.id == id } ?? StationCatalog.factoryStations.first { $0.id == id })!
    }
    #endif
}

enum StationIDMigration {
    static func canonical(_ id: String) -> String {
        switch id {
        case "kiss": return "builtin.kiss"
        case "musicRadio": return "builtin.music-radio"
        default: return id
        }
    }
    static func apply(to defaults: UserDefaults) {
        for key in ["station", "defaultStation"] {
            if let old = defaults.string(forKey: key), canonical(old) != old {
                defaults.set(canonical(old), forKey: key)
            }
        }
        for key in ["stationOrderIDs", "hiddenStationIDs"] {
            if let old = defaults.stringArray(forKey: key) {
                let mapped = old.map(canonical)
                var seen = Set<String>()
                let unique = mapped.filter { seen.insert($0).inserted }
                if unique != old { defaults.set(unique, forKey: key) }
            }
        }
        let key = "stationVisibilityOverrides"
        if let old = defaults.dictionary(forKey: key) as? [String: Bool] {
            var migrated = old.filter { canonical($0.key) == $0.key }
            for (id, visible) in old where migrated[canonical(id)] == nil {
                migrated[canonical(id)] = visible
            }
            if migrated != old { defaults.set(migrated, forKey: key) }
        }
    }
}

struct StationConfigurationError: Error {
    let text: RadioText
    init(_ zh: String, _ en: String) { text = RadioText(zh, en) }
}

enum StationRestoreResult {
    case restored(backup: URL)
    case backupFailed
    case restoreFailed(backup: URL)
    case reloaded
    case unchanged
    case reloadFailed(RadioText)
    case openFailed
    case saved, deleted
    case editFailed(RadioText)

    var succeeded: Bool {
        switch self {
        case .restored, .reloaded, .unchanged, .saved, .deleted: return true
        default: return false
        }
    }
    var text: RadioText {
        switch self {
        case .restored:
            return RadioText("已备份当前配置，并恢复内置电台列表。",
                             "Configuration backed up and bundled stations restored.")
        case .backupFailed:
            return RadioText("备份失败，未恢复电台列表。请检查配置文件及文件夹权限。",
                             "Backup failed. Stations were not restored. Check the configuration file and folder permissions.")
        case .restoreFailed:
            return RadioText("当前配置已备份，但恢复失败。备份保存在配置文件夹中。",
                             "Configuration backed up, but restore failed. The backup is in the configuration folder.")
        case .reloaded: return RadioText("已重新加载电台配置。", "Station configuration reloaded.")
        case .unchanged: return RadioText("配置未变化。", "Configuration unchanged.")
        case .reloadFailed(let reason):
            return RadioText("重新加载失败：\(reason.zh) 当前列表保持不变。",
                             "Reload failed: \(reason.en) The current list is unchanged.")
        case .saved: return RadioText("电台已保存，原配置已备份。", "Station saved. The previous configuration was backed up.")
        case .deleted: return RadioText("电台已删除，原配置已备份。", "Station deleted. The previous configuration was backed up.")
        case .editFailed(let reason): return reason
        case .openFailed:
            return RadioText("无法打开配置文件，请检查文件是否存在、访问权限及默认编辑器。",
                             "Unable to open the configuration file. Check that it exists, its permissions and the default editor.")
        }
    }
}

struct StationConfiguration: Decodable {
    let schemaVersion: Int
    let stations: [Entry]
    struct Entry: Decodable {
        let id: String
        let name: RadioText
        let fullName: RadioText?
        let frequencyMHz: String?
        let category: RadioText?
        let urls: [String]
        let defaultVisible: Bool?
    }
    static func decode(_ data: Data) throws -> [Station] {
        guard data.count <= 1_048_576 else {
            throw StationConfigurationError("配置文件不能超过 1 MiB。", "The configuration must not exceed 1 MiB.")
        }
        let config: StationConfiguration
        do { config = try JSONDecoder().decode(Self.self, from: data) }
        catch {
            // Do not echo decoding descriptions, which may contain stream credentials.
            throw StationConfigurationError("JSON 格式或字段类型错误，请检查 schemaVersion、stations 和各电台字段。",
                                            "Invalid JSON or field types. Check schemaVersion, stations and station fields.")
        }
        guard config.schemaVersion == 1 else {
            throw StationConfigurationError("不支持此 schemaVersion，请使用 1。", "Unsupported schemaVersion. Use 1.")
        }
        guard config.stations.count <= 500 else {
            throw StationConfigurationError("最多配置 500 个普通电台。", "Configure at most 500 direct stations.")
        }
        let legacyIDs = Set(["bcc", "ufo", "asiaFM", "guangdong", "shanghai", "loveRadio", "classic947", "radioParadise", "grooveSalad", "swissJazz"])
        var seen = Set<String>()
        return try config.stations.enumerated().map { index, entry in
            func fail(_ zh: String, _ en: String) -> StationConfigurationError {
                StationConfigurationError("第 \(index + 1) 个电台：\(zh)", "Station \(index + 1): \(en)")
            }
            let pattern = "^[a-z0-9]+(?:[.-][a-z0-9]+)*$"
            guard entry.id.utf8.count <= 128,
                  legacyIDs.contains(entry.id) || entry.id.range(of: pattern, options: .regularExpression) != nil,
                  !entry.id.hasPrefix("builtin."), !["builtin", "kiss", "musicRadio", "random"].contains(entry.id) else {
                throw fail("ID 无效或使用了保留名称。新 ID 请使用小写字母、数字、点和短横线。",
                           "Invalid or reserved ID. Use lowercase letters, digits, dots and hyphens for new IDs.")
            }
            guard seen.insert(entry.id).inserted else { throw fail("ID 重复。", "Duplicate ID.") }
            func validText(_ text: RadioText) -> Bool {
                [text.zh, text.en].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
            }
            guard validText(entry.name), entry.fullName.map(validText) ?? true,
                  entry.category.map(validText) ?? true else {
                throw fail("名称或分类的中英文不能为空、含控制字符或超过 200 字。", "Names and categories require both languages, no control characters and at most 200 characters.")
            }
            if let frequency = entry.frequencyMHz {
                guard frequency.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
                      let number = Double(frequency), number > 0, number <= 1000 else {
                    throw fail("frequencyMHz 必须是有效的正数文本。", "frequencyMHz must be a valid positive numeric string.")
                }
            }
            guard !entry.urls.isEmpty, entry.urls.count <= 20 else { throw fail("urls 需要 1–20 个地址。", "urls requires 1–20 addresses.") }
            let urls = try entry.urls.map { string -> URL in
                guard string.utf8.count <= 8192, !string.contains(where: { $0.isWhitespace }),
                      let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil else {
                    throw fail("urls 仅支持有效的 HTTP/HTTPS 地址，不能含用户名、密码或片段。",
                               "urls requires valid HTTP/HTTPS addresses without user information or fragments.")
                }
                return url
            }
            return Station(id: entry.id, title: entry.name, fullName: entry.fullName,
                           frequencyMHz: entry.frequencyMHz,
                           category: entry.category ?? RadioText("自定义电台", "Custom station"), urls: urls,
                           defaultVisible: entry.defaultVisible ?? true)
        }
    }
}

/// Read and validate off the main thread; publish a complete catalogue on the main actor.
enum StationCatalog {
    static let didChange = Notification.Name("RadioBar.StationCatalog.didChange")
    static let userDirectoryName = "local.victor.RadioBar"
    static var factoryStations: [Station] { merge((try? defaultStations()) ?? []) }
    private(set) static var stations = factoryStations

    @MainActor @discardableResult static func apply(_ candidate: [Station]) -> Bool {
        guard candidate.count != stations.count || zip(candidate, stations).contains(where: { !$0.hasSameConfiguration(as: $1) }) else { return false }
        stations = candidate
        NotificationCenter.default.post(name: didChange, object: nil)
        return true
    }

    /// Manual reload never creates a missing file or falls back to factory data.
    static func read(userFile: URL) throws -> [Station] {
        let size = try FileManager.default.attributesOfItem(atPath: userFile.path)[.size] as? NSNumber
        guard (size?.intValue ?? 0) <= 1_048_576 else {
            throw StationConfigurationError("配置文件不能超过 1 MiB。", "The configuration must not exceed 1 MiB.")
        }
        return merge(try StationConfiguration.decode(Data(contentsOf: userFile)))
    }

    static func prepareUpdate(userFile: URL, restoring: Bool) -> (StationRestoreResult, [Station]?) {
        if restoring {
            var candidate: [Station]?
            let result = restore(userFile: userFile, defaultData: {
                let data = try defaultData()
                candidate = merge(try StationConfiguration.decode(data))
                return data
            })
            return (result, result.succeeded ? candidate : nil)
        }
        do { return (.reloaded, try read(userFile: userFile)) }
        catch {
            let reason = (error as? StationConfigurationError)?.text ?? RadioText(
                "无法读取配置文件，请检查文件是否存在及访问权限。",
                "Unable to read the configuration file. Check that it exists and is readable.")
            return (.reloadFailed(reason), nil)
        }
    }

    static func merge(_ direct: [Station]) -> [Station] {
        [Station.kiss, .musicRadio] + direct
    }
    static func defaultData() throws -> Data {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "stations.default", withExtension: "json")
        #else
        var url = Bundle.main.url(forResource: "stations.default", withExtension: "json")
        #if RADIOBAR_TESTING
        if url == nil { url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/stations.default.json") }
        #endif
        #endif
        guard let url else { throw StationConfigurationError("App 缺少默认电台资源。", "The app is missing its default station resource.") }
        return try Data(contentsOf: url)
    }
    static func defaultStations() throws -> [Station] { try StationConfiguration.decode(defaultData()) }
    static func userFile(in support: URL) -> URL {
        support.appendingPathComponent(userDirectoryName, isDirectory: true).appendingPathComponent("stations.json")
    }
    /// Disk phase only; the caller publishes the validated candidate after a successful write.
    /// Copy first, then atomically replace; even invalid user JSON remains recoverable.
    static func restore(userFile: URL, defaultData: () throws -> Data = { try StationCatalog.defaultData() },
                        write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) -> StationRestoreResult {
        var result: StationRestoreResult = .backupFailed
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: userFile, options: .forReplacing, error: &coordinationError) { file in
            do {
                let original = try StationLocalBackup.read(file)
                let backup = try StationLocalBackup.create(for: file, original: original)
                do {
                    let data = try defaultData()
                    _ = try StationConfiguration.decode(data)
                    guard try StationLocalBackup.read(file) == original else {
                        result = .restoreFailed(backup: backup); return
                    }
                    try write(data, file)
                    result = .restored(backup: StationLocalBackup.completed(backup, for: file))
                } catch { result = .restoreFailed(backup: backup) }
            } catch { result = .backupFailed }
        }
        return coordinationError == nil ? result : .backupFailed
    }
    /// Never overwrites an existing file, including an invalid one.
    static func load(userFile: URL, defaultData: Data) throws -> [Station] {
        _ = try StationConfiguration.decode(defaultData)
        let manager = FileManager.default
        if !manager.fileExists(atPath: userFile.path) {
            try manager.createDirectory(at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            // withoutOverwriting protects a file created concurrently by an editor.
            try defaultData.write(to: userFile, options: .withoutOverwriting)
        }
        let size = try manager.attributesOfItem(atPath: userFile.path)[.size] as? NSNumber
        guard (size?.intValue ?? 0) <= 1_048_576 else {
            throw StationConfigurationError("配置文件不能超过 1 MiB。", "The configuration must not exceed 1 MiB.")
        }
        return merge(try StationConfiguration.decode(Data(contentsOf: userFile)))
    }
    static func start(defaults: UserDefaults = .standard, supportDirectory: URL? = nil) -> RadioText? {
        StationIDMigration.apply(to: defaults)
        do {
            let data = try defaultData()
            let support = try supportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            stations = try load(userFile: userFile(in: support), defaultData: data)
            return nil
        } catch {
            stations = factoryStations
            let reason = (error as? StationConfigurationError)?.text
                ?? RadioText("无法读取或创建用户配置文件，请检查文件权限。", "Unable to read or create the user configuration. Check file permissions.")
            return RadioText(reason.zh + "\n本次使用默认电台，用户文件未被覆盖。",
                             reason.en + "\nUsing default stations for this launch. The user file was not overwritten.")
        }
    }
}

/// Only normalize user-edited input, never stream contents or untouched JSON fields.
enum StationEditorInput {
    static func trimEdges(_ value: String) -> String {
        func isNoise(_ scalar: Unicode.Scalar) -> Bool {
            // Joiners and variation selectors can carry meaning in names/emoji.
            if scalar.value == 0x200C || scalar.value == 0x200D ||
                (0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value) { return false }
            return scalar.properties.isWhitespace || CharacterSet.controlCharacters.contains(scalar) ||
                scalar.properties.isDefaultIgnorableCodePoint
        }
        let scalars = value.unicodeScalars
        var start = scalars.startIndex, end = scalars.endIndex
        while start < end, isNoise(scalars[start]) { start = scalars.index(after: start) }
        while start < end {
            let previous = scalars.index(before: end)
            guard isNoise(scalars[previous]) else { break }
            end = previous
        }
        let trimmed = String(scalars[start..<end])
        // A field containing only invisible characters is still an empty field.
        guard trimmed.unicodeScalars.contains(where: {
            !$0.properties.isWhitespace && !$0.properties.isDefaultIgnorableCodePoint &&
                !CharacterSet.controlCharacters.contains($0)
        }) else { return "" }
        return trimmed
    }

    static func addresses(_ value: String) throws -> [String] {
        // Preserve the user's physical line numbers, including CRLF and blank lines.
        let lines = value.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        return try lines.enumerated().compactMap { index, line in
            let cleaned = trimEdges(line)
            guard !cleaned.isEmpty else { return nil }
            guard !cleaned.unicodeScalars.contains(where: {
                $0.properties.isWhitespace || $0.properties.isDefaultIgnorableCodePoint ||
                    CharacterSet.controlCharacters.contains($0)
            }) else {
                throw StationConfigurationError("播放地址第 \(index + 1) 行包含空白或不可见字符，请删除这些字符后重试。",
                                                "Stream URL line \(index + 1) contains whitespace or invisible characters. Remove them and try again.")
            }
            // Never decode, concatenate or otherwise alter URL paths/query parameters.
            return cleaned
        }
    }
}

/// A disk snapshot owns an edit, so external edits are never silently replaced.
/// Keep unedited and unknown JSON fields, including optional metadata, intact.
struct StationEditorSession: Identifiable {
    let id = UUID()
    let file: URL
    let original: Data
    let stationID: String
    let isNew: Bool
    var nameZH: String
    var nameEN: String
    var categoryZH: String
    var categoryEN: String
    var fullNameZH: String
    var fullNameEN: String
    var frequency: String
    var addresses: String
    private let originalAddresses: String

    init(file: URL, station: Station?) throws {
        guard station?.isBuiltIn != true else {
            throw StationConfigurationError("内置电台只能隐藏和排序。", "Built-in stations can only be hidden or reordered.")
        }
        guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw StationConfigurationError("配置文件是符号链接，请直接编辑原文件后重新加载。", "The configuration is a symbolic link. Edit the original file and reload.")
        }
        _ = try StationCatalog.read(userFile: file)
        original = try Data(contentsOf: file)
        let entries = try StationConfiguration.decode(original)
        let selected = station.flatMap { target in entries.first { $0.id == target.id } }
        guard station == nil || selected != nil else {
            throw StationConfigurationError("此电台已从文件中移除，请重新加载。", "This station was removed from the file. Reload the configuration.")
        }
        self.file = file
        isNew = station == nil
        stationID = selected?.id ?? "user." + UUID().uuidString.lowercased()
        nameZH = selected?.title.zh ?? ""
        nameEN = selected?.title.en ?? ""
        let entry = try JSONDecoder().decode(StationConfiguration.self, from: original).stations.first { $0.id == selected?.id }
        categoryZH = entry?.category?.zh ?? ""
        categoryEN = entry?.category?.en ?? ""
        fullNameZH = selected?.fullName?.zh ?? ""
        fullNameEN = selected?.fullName?.en ?? ""
        frequency = selected?.frequencyMHz ?? ""
        let addressText = selected?.urls.map(\.absoluteString).joined(separator: "\n") ?? ""
        addresses = addressText
        originalAddresses = addressText
    }

    func candidate(deleting: Bool) throws -> Data {
        guard !stationID.hasPrefix("builtin."), !(isNew && deleting),
              var document = try JSONSerialization.jsonObject(with: original) as? [String: Any],
              var entries = document["stations"] as? [[String: Any]] else {
            throw StationConfigurationError("无法编辑此电台配置。", "Unable to edit this station configuration.")
        }
        let index = entries.firstIndex { $0["id"] as? String == stationID }
        guard isNew ? index == nil : index != nil else {
            throw StationConfigurationError("电台记录已变化，请重新打开编辑窗口。", "The station record changed. Reopen the editor.")
        }
        if deleting {
            entries.remove(at: index!)
        } else {
            func trim(_ value: String) -> String { StationEditorInput.trimEdges(value) }
            var entry = index.map { entries[$0] } ?? ["id": stationID]
            func updateText(_ key: String, _ zh: String, _ en: String, optional: Bool = true) {
                var value = entry[key] as? [String: Any] ?? [:]
                guard zh != (value["zh"] as? String ?? "") || en != (value["en"] as? String ?? "") || (!optional && entry[key] == nil) else { return }
                if optional && trim(zh).isEmpty && trim(en).isEmpty { entry[key] = nil; return }
                if zh != (value["zh"] as? String ?? "") || value["zh"] == nil { value["zh"] = trim(zh) }
                if en != (value["en"] as? String ?? "") || value["en"] == nil { value["en"] = trim(en) }
                entry[key] = value
            }
            updateText("name", nameZH, nameEN, optional: false)
            updateText("fullName", fullNameZH, fullNameEN)
            updateText("category", categoryZH, categoryEN)
            if frequency != (entry["frequencyMHz"] as? String ?? "") {
                entry["frequencyMHz"] = trim(frequency).isEmpty ? nil : trim(frequency)
            }
            if isNew || addresses != originalAddresses {
                entry["urls"] = try StationEditorInput.addresses(addresses)
            }
            if let index { entries[index] = entry } else { entries.append(entry) }
        }
        document["stations"] = entries
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        _ = try StationConfiguration.decode(data)
        return data
    }

    /// Coordinate with document editors, and recheck bytes immediately before replacement.
    /// A non-cooperating external writer cannot be locked by NSFileCoordinator.
    func save(deleting: Bool,
              write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws -> [Station] {
        let data = try candidate(deleting: deleting)
        let stations = StationCatalog.merge(try StationConfiguration.decode(data))
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { coordinated in
            do {
                let values = try coordinated.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      try Data(contentsOf: coordinated) == original else {
                    throw StationConfigurationError("配置文件已被外部修改。请取消编辑，重新加载后再试。",
                                                    "The configuration changed outside the app. Cancel editing, reload and try again.")
                }
                let backup = try StationLocalBackup.create(for: coordinated, original: original)
                guard try Data(contentsOf: coordinated) == original else {
                    throw StationConfigurationError("配置文件已被外部修改。请取消编辑，重新加载后再试。",
                                                    "The configuration changed outside the app. Cancel editing, reload and try again.")
                }
                try write(data, coordinated)
                _ = StationLocalBackup.completed(backup, for: coordinated)
            } catch { operationError = error }
        }
        if let error = operationError ?? coordinationError { throw error }
        return stations
    }
}

/// Only completed v2 JSON backups rotate. Old formats, failed writes and recovery records stay untouched.
enum StationLocalBackup {
    static func read(_ file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnknown) }
        // Reset may need to preserve an invalid/oversized original exactly as earlier versions did.
        return try Data(contentsOf: file)
    }
    static func create(for file: URL, original: Data) throws -> URL {
        let backup = file.deletingLastPathComponent().appendingPathComponent("stations.backup-pending-" + UUID().uuidString.lowercased() + ".json")
        try original.write(to: backup, options: .withoutOverwriting)
        return backup
    }
    @discardableResult static func completed(_ backup: URL, for file: URL) -> URL {
        let manager = FileManager.default, directory = file.deletingLastPathComponent()
        // An invalid original remains a recovery backup, outside automatic rotation.
        guard let data = try? read(backup), (try? StationConfiguration.decode(data)) != nil else { return backup }
        let name = backup.lastPathComponent.replacingOccurrences(of: "stations.backup-pending-", with: "stations.backup-v2-")
        let completed = directory.appendingPathComponent(name)
        do {
            try manager.moveItem(at: backup, to: completed)
            try manager.setAttributes([.modificationDate: Date()], ofItemAtPath: completed.path)
            let names = try manager.contentsOfDirectory(atPath: directory.path)
            guard !names.contains("station-sync-transaction.json") else { return completed }
            var candidates: [(URL, Date)] = []
            for name in names where name.hasPrefix("stations.backup-v2-") && name.hasSuffix(".json") {
                let id = String(name.dropFirst("stations.backup-v2-".count).dropLast(5))
                guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else { continue }
                let url = directory.appendingPathComponent(name)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_048_576,
                      let bytes = try? read(url), (try? StationConfiguration.decode(bytes)) != nil else { continue }
                candidates.append((url, values.contentModificationDate ?? .distantFuture))
            }
            candidates.sort { $0.1 == $1.1 ? $0.0.lastPathComponent > $1.0.lastPathComponent : $0.1 > $1.1 }
            // Always retain the backup from this save, even when an older file has a future timestamp.
            let older = candidates.filter { $0.0 != completed }
            for (url, date) in older.dropFirst(4) {
                let latest = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard latest.isRegularFile == true, latest.isSymbolicLink != true, latest.contentModificationDate == date else { continue }
                // unlink never follows a replacement symlink or recursively removes a directory.
                _ = Darwin.unlink(url.path)
            }
            return completed
        } catch { return manager.fileExists(atPath: completed.path) ? completed : backup }
    }
}
