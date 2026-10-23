import Foundation

enum DefaultStationChoice: Hashable {
    case lastListened, random, station(Station)

    init(storedValue: String?) {
        if storedValue == "random" { self = .random }
        else if let station = storedValue.flatMap(Station.init(rawValue:)) { self = .station(station) }
        else { self = .lastListened }
    }

    var storedValue: String? {
        switch self {
        case .lastListened: return nil
        case .random: return "random"
        case .station(let station): return station.rawValue
        }
    }
}

/// Preserve known stable IDs once each and append new/missing stations in factory order.
enum StationOrder {
    static let preferenceKey = "stationOrderIDs"
    static func preservingUnknownIDs(_ order: [Station], defaults: UserDefaults) -> [String] {
        let known = Set(order.map(\.id))
        var remaining = ArraySlice(order.map(\.id))
        var seen = Set<String>()
        let saved = defaults.stringArray(forKey: preferenceKey) ?? []
        let result = saved.compactMap { id -> String? in
            guard seen.insert(id).inserted else { return nil }
            return known.contains(id) ? remaining.popFirst() : id
        }
        return result + remaining
    }
    static func stations(defaults: UserDefaults) -> [Station] {
        StationIDMigration.apply(to: defaults)
        var seen = Set<Station>()
        let saved = (defaults.stringArray(forKey: preferenceKey) ?? []).compactMap(Station.init(rawValue:))
        return (saved + Station.allCases).filter { seen.insert($0).inserted }
    }
}

/// Visibility is keyed by stable station IDs, never localized names or row numbers.
enum StationVisibility {
    static let preferenceKey = "hiddenStationIDs"
    static let overridesKey = "stationVisibilityOverrides"
    static func hiddenStations(defaults: UserDefaults) -> Set<Station> {
        StationIDMigration.apply(to: defaults)
        let legacyHidden = Set(defaults.stringArray(forKey: preferenceKey) ?? [])
        let overrides = defaults.dictionary(forKey: overridesKey) as? [String: Bool] ?? [:]
        var hidden = Set(Station.allCases.filter { station in
            if let visible = overrides[station.id] { return !visible }
            return legacyHidden.contains(station.id) || !station.defaultVisible
        })
        // Recover from corrupt/imported preferences without leaving an empty menu.
        if hidden.count == Station.allCases.count { hidden.remove(StationOrder.stations(defaults: defaults)[0]) }
        return hidden
    }
    static func visibleStations(defaults: UserDefaults) -> [Station] {
        let hidden = hiddenStations(defaults: defaults)
        return StationOrder.stations(defaults: defaults).filter { !hidden.contains($0) }
    }
    static func setVisible(_ visible: Bool, station: Station, defaults: UserDefaults) {
        var overrides = defaults.dictionary(forKey: overridesKey) as? [String: Bool] ?? [:]
        overrides[station.id] = visible
        defaults.set(overrides, forKey: overridesKey)
        // Keep the legacy key meaningful without persisting JSON defaults as user choices.
        var hidden = Set(defaults.stringArray(forKey: preferenceKey) ?? [])
        if visible { hidden.remove(station.id) } else { hidden.insert(station.id) }
        defaults.set(hidden.sorted(), forKey: preferenceKey)
    }
}

/// A launch-time snapshot. Settings changes affect the next launch, not the live session.
struct PlaybackPreferences {
    static let defaultStationKey = "defaultStation"
    static let autoPlayOnLaunchKey = "autoPlayOnLaunch"

    let station: Station
    let autoPlayOnLaunch: Bool

    init(defaults: UserDefaults, chooseRandom: ([Station]) -> Station? = { $0.randomElement() }) {
        StationIDMigration.apply(to: defaults)
        let lastStation = Station(rawValue: defaults.string(forKey: "station") ?? "")
        let visible = StationVisibility.visibleStations(defaults: defaults)
        let fallback = lastStation.flatMap { visible.contains($0) ? $0 : nil } ?? visible[0]
        switch DefaultStationChoice(storedValue: defaults.string(forKey: Self.defaultStationKey)) {
        case .lastListened: station = fallback
        case .random:
            let selected = chooseRandom(visible)
            station = selected.flatMap { visible.contains($0) ? $0 : nil } ?? fallback
        case .station(let selected): station = visible.contains(selected) ? selected : fallback
        }
        autoPlayOnLaunch = defaults.bool(forKey: Self.autoPlayOnLaunchKey)
    }
}
