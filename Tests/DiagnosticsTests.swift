import Foundation

private actor PendingResolver: StreamURLResolving {
    var pending: [Station: CheckedContinuation<StreamAddress, Error>] = [:]
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        try await withCheckedThrowingContinuation { pending[station] = $0 }
    }
    func contains(_ station: Station) -> Bool { pending[station] != nil }
    func fail(_ station: Station) { pending.removeValue(forKey: station)?.resume(throwing: NSError(domain: NSURLErrorDomain, code: -1004)) }
}

@main
struct DiagnosticsTests {
    @MainActor static func main() async throws {
        let store = RadioDiagnostics()
        for i in 0..<200 { store.record("event", "index=\(i)") }
        precondition(store.snapshot().lines.count == 100 && store.snapshot().dropped == 100)
        for _ in 0..<200 { store.record("event", String(repeating: "音", count: 1000)) }
        precondition(store.snapshot().bytes <= 65536 && store.report().utf8.count <= 65536)
        precondition(store.snapshot().lines.count < 100)
        store.clear()
        precondition(store.snapshot().lines.isEmpty && store.snapshot().bytes == 0 && store.snapshot().dropped == 0)
        DispatchQueue.concurrentPerform(iterations: 500) { i in store.record("parallel", "\(i)") }
        precondition(store.snapshot().lines.count == 100)
        store.clear()
        let secret = "https://fixture.invalid/SECRET_PATH/music.m3u8?token=SECRET_TOKEN&key=SECRET_SIGNATURE&time=SECRET_TIME"
        let connection = store.begin(station: .musicRadio)
        let trace = DiagnosticTrace(store: store, connection: connection, attempt: 1, station: Station.musicRadio.rawValue)
        // Fingerprint comparisons remain useful for every fixed source; never store its URL.
        store.stream(URL(string: secret)!, trace: trace)
        store.stream(URL(string: secret)!, trace: trace)
        store.stream(URL(string: secret + "CHANGED")!, trace: trace)
        let report = store.report()
        for value in ["first", "same", "changed", "c1/a1"] { precondition(report.contains(value)) }
        for value in ["SECRET", "fixture.invalid", "https://", "secret_key"] { precondition(!report.contains(value)) }
        let unsafe = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: secret,
            NSUnderlyingErrorKey: NSError(domain: "CoreMediaErrorDomain", code: -9405, userInfo: ["url": secret])])
        precondition(RadioDiagnostics.error(unsafe) == "NSURLErrorDomain/-1001 <- CoreMediaErrorDomain/-9405")
        precondition(!unsafe.radioDisplayText.zh.contains("SECRET") && !unsafe.radioDisplayText.en.contains("SECRET"))
        let clean = RadioDiagnostics.clean("failed \(secret) token=SECRET_TOKEN key=SECRET_KEY\nnext")
        precondition(!clean.contains("SECRET") && !clean.contains("https://") && !clean.contains("\n"))
        let newer = store.begin(station: .bcc)
        store.state(DiagnosticTrace(store: store, connection: newer, attempt: 1, station: "bcc"), phase: "Playing")
        store.state(trace, phase: "Error")
        precondition(store.snapshot().phase == "Playing" && store.snapshot().station == "bcc")
        store.clear()
        precondition(!store.report().contains("stream.address"))
        print("PASS: count/UTF-8 byte/report bounds, concurrent writes, clear, safe errors, address comparison without private paths/URLs/tokens and stale-state guard")

        // Diagnostics observe failures/cancellation without starting audio or altering retries.
        let suite = "RadioBar.DiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Station.musicRadio.rawValue, forKey: "station")
        let pending = PendingResolver()
        let player = RadioPlayer(resolver: pending, defaults: defaults, diagnostics: store)
        player.play()
        for _ in 0..<100 { if await pending.contains(.musicRadio) { break }; await Task.yield() }
        let isPending = await pending.contains(.musicRadio)
        precondition(isPending)
        await pending.fail(.musicRadio)
        for _ in 0..<100 { if store.snapshot().phase == "Retrying" { break }; await Task.yield() }
        precondition(store.report().contains("retry.scheduled") && store.report().contains("NSURLErrorDomain/-1004"))
        precondition(store.snapshot().retries == 1 && player.wantsPlayback)
        player.pause()
        precondition(store.snapshot().phase == "Paused")
        print("PASS: real player records resolver failure, original 2s retry and pause; no network/audio")
    }
}
