import Foundation

/// Exercise the production Bundle.main loader with a separately compiled generated key.
@main
struct BuiltinStreamsBundleProbe {
    static func main() {
        let streams = BuiltinStreams.bundled
        if CommandLine.arguments[1] == "--empty" {
            precondition(streams.isEmpty)
        } else {
            precondition(streams["builtin.kiss"]?.map(\.absoluteString) == [CommandLine.arguments[1]])
            precondition(streams["builtin.music-radio"]?.map(\.absoluteString) == [CommandLine.arguments[2]])
        }
        print("PASS: production bundle decryption / safe failure")
    }
}
