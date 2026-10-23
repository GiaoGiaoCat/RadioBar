import Foundation

/// Errors shown by future sync/share adapters never include document contents or URLs.
enum StationSharingError: Error {
    case invalidDocument, unsupportedVersion, invalidPreferences, differentLibrary, changedLocally, unavailable

    var text: RadioText {
        switch self {
        case .unsupportedVersion:
            return RadioText("配置格式较新，请升级 App 后重试。", "This configuration requires a newer app. Update and retry.")
        case .invalidPreferences:
            return RadioText("共享电台偏好无效，当前配置保持不变。", "Invalid shared station preferences. The current configuration is unchanged.")
        case .differentLibrary:
            return RadioText("配置属于另一配置库，请重新选择同步文件夹。", "This configuration belongs to a different library. Select the sync folder again.")
        case .changedLocally:
            return RadioText("本机配置已变化，请保留现有内容并重新检查。", "The local configuration changed. Keep its contents and check again.")
        case .unavailable:
            return RadioText("无法访问配置文件，请检查权限后重试。", "Unable to access the configuration. Check permissions and retry.")
        case .invalidDocument:
            return RadioText("电台配置无效，当前配置保持不变。", "Invalid station configuration. The current configuration is unchanged.")
        }
    }
}

/// Keep the original bytes, including unknown fields and signed URL spelling.
/// Codable wraps these bytes as base64; it does not establish a public sharing format.
struct StationDocument: Codable, Equatable {
    let data: Data
    var stations: [Station] { get throws { try StationConfiguration.decode(data) } }

    init(data: Data) throws {
        _ = try StationConfiguration.decode(data)
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(data: container.decode(Data.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }

    fileprivate var object: [String: Any] {
        // All construction paths validated this JSON and its root type.
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    fileprivate var entries: [[String: Any]] { object["stations"] as? [[String: Any]] ?? [] }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data == rhs.data || NSDictionary(dictionary: lhs.object).isEqual(to: rhs.object)
    }


}

struct SharedStationPreferences: Codable, Equatable {
    static let managedKeys = ["stationOrderIDs", "hiddenStationIDs", "stationVisibilityOverrides", "defaultStation"]
    var orderIDs: [String]
    var visibilityOverrides: [String: Bool]
    /// nil = this device's last listened station; "random" is a mode, not a Station ID.
    var defaultStation: String?

    static func validID(_ id: String) -> Bool {
        let legacy = ["asiaFM", "loveRadio", "classic947", "radioParadise", "grooveSalad", "swissJazz"]
        return id.utf8.count <= 128 && !["builtin", "random", "kiss", "musicRadio"].contains(id)
            && (legacy.contains(id) || id.range(of: "^[a-z0-9]+(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil)
    }

    func validate() throws {
        guard orderIDs.count <= 10_000, Set(orderIDs).count == orderIDs.count,
              orderIDs.allSatisfy(Self.validID), visibilityOverrides.count <= 10_000,
              visibilityOverrides.keys.allSatisfy(Self.validID),
              defaultStation == nil || defaultStation == "random" || Self.validID(defaultStation!) else {
            throw StationSharingError.invalidPreferences
        }
    }

    /// Read-only migration; explicit canonical overrides win over aliases and legacy hides.
    static func capture(from defaults: UserDefaults) throws -> Self {
        try capture(values: Dictionary(uniqueKeysWithValues: managedKeys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        }))
    }

    /// Decode only shared preference values, including old backup aliases, without changing defaults.
    static func capture(values: [String: Any]) throws -> Self {
        for key in ["stationOrderIDs", "hiddenStationIDs"] {
            if let value = values[key], !(value is [String]) { throw StationSharingError.invalidPreferences }
        }
        if let value = values["stationVisibilityOverrides"], !(value is [String: Bool]) {
            throw StationSharingError.invalidPreferences
        }
        if let value = values["defaultStation"], !(value is String) { throw StationSharingError.invalidPreferences }
        let canonical = StationIDMigration.canonical
        var seen = Set<String>()
        let order = ((values["stationOrderIDs"] as? [String]) ?? []).map(canonical).filter { seen.insert($0).inserted }
        let saved = (values["stationVisibilityOverrides"] as? [String: Any]) as? [String: Bool] ?? [:]
        var visible = saved.filter { canonical($0.key) == $0.key }
        for (id, value) in saved where visible[canonical(id)] == nil { visible[canonical(id)] = value }
        for id in (values["hiddenStationIDs"] as? [String]) ?? [] where visible[canonical(id)] == nil {
            visible[canonical(id)] = false
        }
        let result = Self(orderIDs: order, visibilityOverrides: visible,
                          defaultStation: (values["defaultStation"] as? String).map(canonical))
        try result.validate()
        return result
    }

    /// Preserve unknown/removed IDs, while recovering a usable visible list and default.
    func normalized(for document: StationDocument) throws -> Self {
        try validate()
        let stations = StationCatalog.merge(try document.stations)
        let lookup = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        var seen = Set<String>()
        let ordered = (orderIDs.compactMap { lookup[$0] } + stations).filter { seen.insert($0.id).inserted }
        var result = self
        func isVisible(_ station: Station) -> Bool { result.visibilityOverrides[station.id] ?? station.defaultVisible }
        if !ordered.contains(where: isVisible), let first = ordered.first { result.visibilityOverrides[first.id] = true }
        if let id = result.defaultStation, id != "random", lookup[id].map(isVisible) != true { result.defaultStation = nil }
        return result
    }

    /// Only these four legacy keys are written; playback, volume, language, etc. stay local.
    func apply(to defaults: UserDefaults) throws {
        try validate()
        defaults.set(orderIDs, forKey: "stationOrderIDs")
        defaults.set(visibilityOverrides, forKey: "stationVisibilityOverrides")
        defaults.set(visibilityOverrides.filter { !$0.value }.keys.sorted(), forKey: "hiddenStationIDs")
        if let defaultStation { defaults.set(defaultStation, forKey: "defaultStation") }
        else { defaults.removeObject(forKey: "defaultStation") }
    }
}

struct SharedStationConfiguration: Codable, Equatable {
    let document: StationDocument
    let preferences: SharedStationPreferences

    func validate() throws { _ = try document.stations; try preferences.validate() }
    func normalized() throws -> Self { try Self(document: document, preferences: preferences.normalized(for: document)) }
}
