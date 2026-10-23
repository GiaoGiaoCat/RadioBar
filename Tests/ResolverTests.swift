import Foundation

@main
struct ResolverTests {
    static func main() async throws {
        try await configurationChecks()
        let resolver = StreamResolver()
        // Identity and built-in management status must never dispatch a different resolver.
        var checks = 0
        for identity in ["builtin.kiss", "builtin.music-radio", "custom.routing"] {
            for count in 1...3 {
                let urls = (0..<count).map { URL(string: "https://fixture.invalid/private-path/\($0).m3u8?expires=1&time=0&token=FAKE%2Bvalue")! }
                let station = Station(id: identity, title: RadioText("测试电台", "Test station"),
                                      category: RadioText("测试", "Test"), urls: urls)
                for attempt in [Int.min, -1, 0, 1, 2, 3, 4, 5, 6, Int.max] {
                    let result = try await resolver.resolve(station, attempt: attempt)
                    let index = max(0, attempt) % count
                    precondition(result.url == urls[index]) // Parameters are opaque; expired-looking values stay intact.
                    precondition(station.sourceIndex(attempt: attempt) == index)
                    precondition(station.sourceName(attempt: attempt) == (index == 0 ? "primary" : "backup"))
                    precondition(station.sourceText(attempt: attempt).en == (index == 0 ? "Primary stream" : "Backup stream"))
                    precondition(station.resolutionText(attempt: attempt).en.contains(station.sourceText(attempt: attempt).en))
                    checks += 1
                }
            }
            let empty = Station(id: identity, title: RadioText("空", "Empty"), category: RadioText("测试", "Test"))
            precondition(empty.sourceIndex(attempt: -1) == nil && empty.sourceName(attempt: 0) == "—")
            do { _ = try await resolver.resolve(empty, attempt: 0); fatalError("Empty sources accepted") }
            catch { precondition(error is RadioError) }
        }
        for builtin in [Station.kiss, .musicRadio] {
            precondition(builtin.isBuiltIn && builtin.urls.count == 1 && builtin.urls[0].scheme == "https")
            for attempt in -1...5 {
                let address = try await resolver.resolve(builtin, attempt: attempt)
                precondition(address.url == builtin.urls[0])
            }
        }
        precondition(Station.allCases.count == 12)
        precondition(StreamResolver.directURLs(for: .bcc).count == 2)
        precondition(Station(rawValue: "ufo") == .ufo)
        precondition(Station(rawValue: "guangdong") == .guangdong)
        precondition(Station(rawValue: "shanghai") == .shanghai)
        precondition(Station(rawValue: "loveRadio") == .loveRadio)
        precondition(Station(rawValue: "classic947") == .classic947)
        precondition(Array(Station.allCases.prefix(4)) == [.kiss, .musicRadio, .bcc, .ufo])
        var routeChecks = 0
        for (station, primary, backup) in [
            (Station.bcc, "https://stream.rcs.revma.com/ks4vsmg3qtzuv", "https://stream.rcs.revma.com/ndk05tyy2tzuv"),
            (.ufo, "https://stream.rcs.revma.com/em90w4aeewzuv", "https://ls.qingting.fm/live/4847.m3u8"),
            (.guangdong, "https://ls.qingting.fm/live/1260.m3u8", "https://satellitepull.cnr.cn/live/wxgdyyzs/playlist.m3u8"),
            (.shanghai, "https://lhttp-hw.qtfm.cn/live/274/64k.mp3", "http://live.xmcdn.com/live/53/64.m3u8"),
            (.loveRadio, "https://lhttp.qingting.fm/live/273/64k.mp3", "http://live.xmcdn.com/live/55/64.m3u8"),
            (.classic947, "https://lhttp.qingting.fm/live/267/64k.mp3", "http://live.xmcdn.com/live/54/64.m3u8"),
            (.asiaFM, "http://yyt.asiafm.net:8000/asiafm", "https://lhttp.qtfm.cn/live/15318569/64k.mp3"),
            (.radioParadise, "http://stream-tx3.radioparadise.com/mp3-192", "http://stream-tx1.radioparadise.com/mp3-128"),
            (.grooveSalad, "https://ice5.somafm.com/groovesalad-256-mp3", "https://ice5.somafm.com/groovesalad-128-mp3"),
            (.swissJazz, "https://stream.srg-ssr.ch/srgssr/rsj/mp3/128", "https://stream.srg-ssr.ch/srgssr/rsj/aac/96")
        ] {
            for attempt in 0...4 {
                let address = try await StreamResolver().resolve(station, attempt: attempt)
                precondition(address.url.absoluteString == (attempt % 2 == 0 ? primary : backup))
                routeChecks += 1
            }
        }
        var recovery = PlaybackRecovery()
        for delay in [2, 4, 8, 16] { precondition(recovery.retryAfterFailure() == delay) }
        precondition(recovery.retryAfterFailure() == nil)
        precondition(recovery.sourceAttempt == 4)

        // A healthy backup must still switch to primary on its next failure.
        var healthyBackup = PlaybackRecovery()
        precondition(healthyBackup.retryAfterFailure() == 2)
        precondition(healthyBackup.sourceAttempt == 1)
        healthyBackup.recordHealthyPlayback()
        precondition(healthyBackup.retryCount == 0 && healthyBackup.sourceAttempt == 1)
        precondition(healthyBackup.retryAfterFailure() == 2)
        let next = try await StreamResolver().resolve(.guangdong, attempt: healthyBackup.sourceAttempt)
        precondition(next.url == StreamResolver.directURLs(for: .guangdong)[0])
        print("PASS: \(checks) resolver cases + \(routeChecks) primary/backup routes + 12 stations")
        print("PASS: bounded retry delays, healthy-budget reset, backup failure switches to primary")
    }
    static func configurationChecks() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RadioBar-ConfigTests-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let file = StationCatalog.userFile(in: root)
        let factory = try StationCatalog.defaultData()
        let initial = try StationCatalog.load(userFile: file, defaultData: factory)
        precondition(initial.count == 12 && initial.map(\.id) == Station.allCases.map(\.id))
        let seeded = try Data(contentsOf: file)
        precondition(seeded == factory)
        let entry: [String: Any] = ["id": "custom.example.music", "name": ["zh": "测试电台", "en": "Test station"],
                                     "urls": ["https://example.invalid/a.mp3?key=preserve&time=123",
                                              "https://example.invalid/b.m3u8", "https://example.invalid/c.aac"]]
        func payload(_ entries: [[String: Any]], version: Int = 1) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["schemaVersion": version, "stations": entries])
        }
        func rejects(_ data: Data) {
            do { _ = try StationConfiguration.decode(data); fatalError("Invalid configuration accepted") }
            catch let error as StationConfigurationError { precondition(!error.text.en.contains("key=preserve")) }
            catch { fatalError("Expected safe configuration error") }
        }
        var visibilityEntry = entry
        visibilityEntry["defaultVisible"] = false
        let hiddenByDefault = try StationConfiguration.decode(payload([visibilityEntry]))
        precondition(hiddenByDefault.first?.defaultVisible == false)
        visibilityEntry["defaultVisible"] = "false"
        rejects(try payload([visibilityEntry]))
        let customData = try payload([entry])
        try customData.write(to: file, options: .atomic)
        let custom = try StationCatalog.load(userFile: file, defaultData: factory)
        precondition(custom.map(\.id) == ["builtin.kiss", "builtin.music-radio", "custom.example.music"])
        let station = custom[2]
        precondition(station.menuName.en == "Test station" && station.frequencyMHz == nil)
        precondition(station.listeningStyle.en == "Custom station")
        for attempt in 0...6 {
            let result = try await StreamResolver().resolve(station, attempt: attempt)
            precondition(result.url == station.urls[attempt % 3])
        }
        let preserved = try Data(contentsOf: file)
        precondition(preserved == customData)
        rejects(Data("{ invalid".utf8))
        rejects(try payload([entry], version: 2))
        rejects(try payload([entry, entry]))
        for id in ["builtin.kiss", "builtin.other", "kiss", "musicRadio", "random", "Custom.Music", "bad id", ""] {
            var changed = entry; changed["id"] = id; rejects(try payload([changed]))
        }
        for urls in [[], ["file:///tmp/audio.mp3"], ["https://user:pass@example.invalid/a.mp3"],
                     ["https:///missing-host"], ["https://example.invalid/a mp3"]] {
            var changed = entry; changed["urls"] = urls; rejects(try payload([changed]))
        }
        var changed = entry; changed["name"] = ["zh": "", "en": "Test"]; rejects(try payload([changed]))
        changed = entry; changed["frequencyMHz"] = "NaN"; rejects(try payload([changed]))
        rejects(Data(repeating: 32, count: 1_048_577))
        let empty = try StationCatalog.merge(StationConfiguration.decode(payload([])))
        precondition(empty == [.kiss, .musicRadio])

        let suite = "RadioBar.ConfigTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("kiss", forKey: "station")
        defaults.set("musicRadio", forKey: "defaultStation")
        defaults.set(["musicRadio", "bcc", "kiss", "builtin.kiss"], forKey: "stationOrderIDs")
        defaults.set(["kiss"], forKey: "hiddenStationIDs")
        precondition(StationCatalog.start(defaults: defaults, supportDirectory: root) == nil)
        precondition(Station(rawValue: station.id) == station && Station(rawValue: "bcc") == nil)
        precondition(defaults.string(forKey: "station") == "builtin.kiss")
        precondition(defaults.string(forKey: "defaultStation") == "builtin.music-radio")
        precondition(defaults.stringArray(forKey: "stationOrderIDs") == ["builtin.music-radio", "bcc", "builtin.kiss"])
        precondition(defaults.stringArray(forKey: "hiddenStationIDs") == ["builtin.kiss"])
        let migrated = defaults.dictionaryRepresentation()
        StationIDMigration.apply(to: defaults)
        precondition(NSDictionary(dictionary: migrated).isEqual(to: defaults.dictionaryRepresentation()))
        let invalid = Data("broken JSON".utf8)
        try invalid.write(to: file, options: .atomic)
        precondition(StationCatalog.start(defaults: defaults, supportDirectory: root) != nil)
        let brokenPreserved = try Data(contentsOf: file)
        precondition(Station.allCases.count == 12 && brokenPreserved == invalid)
        // Restore default catalogue without touching the real user's config/preferences.
        try factory.write(to: file, options: .atomic)
        precondition(StationCatalog.start(defaults: defaults, supportDirectory: root) == nil)
        print("PASS: default JSON seeding, custom identity/three routes, empty catalogue, validation, protected invalid file, startup fallback and four-key ID migration")
    }

}
