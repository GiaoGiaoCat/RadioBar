import Foundation

/// Private build input and bundled resource share this format. Never expose decoding errors or URLs.
enum BuiltinStreams {
    static let ids: Set<String> = ["builtin.kiss", "builtin.music-radio"]
    enum ConfigurationError: Error { case invalid }

    static func decode(_ data: Data) throws -> [String: [URL]] {
        guard data.count <= 65_536,
              let entries = try? JSONDecoder().decode([String: [String]].self, from: data),
              Set(entries.keys) == ids else { throw ConfigurationError.invalid }
        var result: [String: [URL]] = [:]
        for (id, strings) in entries {
            guard (1...20).contains(strings.count) else { throw ConfigurationError.invalid }
            result[id] = try strings.map { string in
                guard string.utf8.count <= 8192,
                      !string.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
                      let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, !host.isEmpty,
                      url.user == nil, url.password == nil, url.fragment == nil else {
                    throw ConfigurationError.invalid
                }
                return url
            }
        }
        return result
    }

    static func load(from file: URL?) -> [String: [URL]] {
        guard let file, let data = try? Data(contentsOf: file), let streams = try? decode(data) else { return [:] }
        return streams
    }

    static let bundled: [String: [URL]] = {
        #if RADIOBAR_TESTING && !RADIOBAR_LIVE_STREAMS
        // Offline tests and previews must neither need private inputs nor play real built-in streams.
        return ["builtin.kiss": [URL(string: "https://fixture.invalid/kiss.m3u8")!],
                "builtin.music-radio": [URL(string: "https://fixture.invalid/cnr.m3u8")!]]
        #else
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return load(from: bundle.url(forResource: "builtin-streams", withExtension: "json"))
        #endif
    }()
}
