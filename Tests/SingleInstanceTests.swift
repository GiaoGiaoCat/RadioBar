import Foundation
import Darwin

@main
struct SingleInstanceTests {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 3 {
            guard let lock = try SingleInstanceLock.acquire(at: URL(fileURLWithPath: args[2])) else { exit(75) }
            withExtendedLifetime(lock) {
                if args[1] == "hold" {
                    print("ready"); fflush(stdout)
                    Thread.sleep(forTimeInterval: 30)
                }
            }
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("instance.lock")
        func child(_ mode: String) throws -> (Process, Pipe) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = [mode, file.path]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            return (process, output)
        }
        var first = try SingleInstanceLock.acquire(at: file)
        precondition(first != nil)
        let (duplicate, _) = try child("try")
        duplicate.waitUntilExit()
        precondition(duplicate.terminationStatus == 75, "Second process must be rejected")
        withExtendedLifetime(first) {}
        first = nil
        let (restarted, _) = try child("try")
        restarted.waitUntilExit()
        precondition(restarted.terminationStatus == 0, "Normal exit must release lock")
        let (crashed, output) = try child("hold")
        let ready = output.fileHandleForReading.availableData
        precondition(String(data: ready, encoding: .utf8)?.contains("ready") == true)
        kill(crashed.processIdentifier, SIGKILL)
        crashed.waitUntilExit()
        let recovered = try SingleInstanceLock.acquire(at: file)
        precondition(recovered != nil, "Forced quit must release lock without removing the file")
        withExtendedLifetime(recovered) {}
        print("PASS: duplicate rejected; restart allowed; forced quit releases lock")
    }
}
