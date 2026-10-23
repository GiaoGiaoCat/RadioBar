import Foundation

@main
struct BuiltinStreamsTests {
    static func main() throws {
        func check(_ condition: Bool) { precondition(condition) }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RadioBar-BuiltinStreamsTests-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let input = root.appendingPathComponent("input.json")
        let output = root.appendingPathComponent("output.json")
        let kiss = "https://fixture.invalid/kiss.m3u8?token=FAKE%2Bvalue&x=a+b&x=%2F&expires=1"
        let cnr = "https://fixture.invalid/cnr.m3u8?empty=&encoded=%26%3D"
        let payload = ["builtin.kiss": [kiss], "builtin.music-radio": [cnr]]
        func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) }
        let valid = try data(payload)
        let decoded = try BuiltinStreams.decode(valid)
        check(decoded["builtin.kiss"]?.first?.absoluteString == kiss)
        check(decoded["builtin.music-radio"]?.first?.absoluteString == cnr)
        var ordered = payload
        ordered["builtin.kiss"] = [kiss, cnr]
        check(try BuiltinStreams.decode(data(ordered))["builtin.kiss"]?.map(\.absoluteString) == [kiss, cnr])
        var rejected = 0
        func rejects(_ bytes: Data) {
            do { _ = try BuiltinStreams.decode(bytes); fatalError("Invalid built-in streams accepted") }
            catch { check(error is BuiltinStreams.ConfigurationError); rejected += 1 }
        }
        rejects(Data("{ broken".utf8))
        rejects(Data(repeating: 32, count: 65_537))
        rejects(try data(["builtin.kiss": [kiss]]))
        rejects(try data(payload.merging(["unknown": [cnr]]) { _, new in new }))
        for urls in [[], Array(repeating: kiss, count: 21), ["file:///tmp/a"], ["https:///missing"],
                     ["https://user:pass@fixture.invalid/a"], ["https://fixture.invalid/a#fragment"],
                     ["https://fixture.invalid/a b"], ["https://fixture.invalid/a\n"],
                     ["https://fixture.invalid/a\u{0}"], [String(repeating: "a", count: 8193)]] {
            rejects(try data(["builtin.kiss": urls, "builtin.music-radio": [cnr]]))
        }
        try valid.write(to: input)
        check(BuiltinStreams.load(from: input)["builtin.kiss"]?.first?.absoluteString == kiss)
        check(BuiltinStreams.load(from: nil).isEmpty)
        check(BuiltinStreams.load(from: root.appendingPathComponent("missing")).isEmpty)
        // Build input selection is exercised through the real helper executable, without touching private/.
        let helper = CommandLine.arguments[1]
        var base = ProcessInfo.processInfo.environment
        for key in ["KISS_STREAM_URL", "CNR_STREAM_URL", "GITHUB_ACTIONS"] { base.removeValue(forKey: key) }
        var runs = 0
        func prepare(_ overrides: [String: String] = [:], succeeds: Bool) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: helper)
            process.arguments = [input.path, output.path]
            process.environment = base.merging(overrides) { _, new in new }
            let log = root.appendingPathComponent("log")
            manager.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            process.standardOutput = handle; process.standardError = handle
            try process.run(); process.waitUntilExit(); try handle.close()
            check((process.terminationStatus == 0) == succeeds)
            let text = try String(contentsOf: log, encoding: .utf8)
            check(!text.contains("fixture.invalid") && !text.contains("PRIVATE_SENTINEL"))
            runs += 1
        }
        try prepare(succeeds: true)
        check(try Data(contentsOf: output) == valid)
        let attrs = try manager.attributesOfItem(atPath: output.path)
        check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        // Environment wins as a complete pair; never combine a partial Secret with the local file.
        try prepare(["KISS_STREAM_URL": cnr, "CNR_STREAM_URL": kiss], succeeds: true)
        let swapped = try Data(contentsOf: output)
        check(try BuiltinStreams.decode(swapped)["builtin.kiss"]?.first?.absoluteString == cnr)
        for overrides in [["KISS_STREAM_URL": kiss], ["KISS_STREAM_URL": "", "CNR_STREAM_URL": cnr],
                          ["KISS_STREAM_URL": "PRIVATE_SENTINEL invalid", "CNR_STREAM_URL": cnr],
                          ["GITHUB_ACTIONS": "true"], ["GITHUB_ACTIONS": "true", "CNR_STREAM_URL": cnr]] {
            try prepare(overrides, succeeds: false)
            check(try Data(contentsOf: output) == swapped)
        }
        try prepare(["GITHUB_ACTIONS": "true", "KISS_STREAM_URL": kiss, "CNR_STREAM_URL": cnr], succeeds: true)
        check(try BuiltinStreams.decode(Data(contentsOf: output)) == decoded)
        try Data("PRIVATE_SENTINEL broken JSON".utf8).write(to: input)
        try prepare(succeeds: false)
        check(BuiltinStreams.load(from: input).isEmpty)
        try manager.removeItem(at: input)
        try prepare(succeeds: false)
        print("PASS: built-in streams: exact queries/order, \(rejected) invalid payloads, safe resource loading, \(runs) input selection/log/atomic output cases")
    }
}
