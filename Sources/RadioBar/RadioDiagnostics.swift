import Foundation
import CryptoKit

struct DiagnosticTrace: Sendable {
    let store: RadioDiagnostics
    let connection: Int
    let attempt: Int
    let station: String
    func event(_ stage: String, _ detail: String = "") {
        store.record(stage, detail, trace: self)
    }
}

struct DiagnosticSnapshot {
    let station: String
    let phase: String
    let source: String
    let retries: Int
    let lastError: String
    let lines: [String]
    let bytes: Int
    let dropped: Int
}

/// Bounded, process-local text only. No files, preferences, headers or response bodies.
final class RadioDiagnostics: @unchecked Sendable {
    static let shared = RadioDiagnostics()
    static let maximumEvents = 100
    static let maximumBytes = 64 * 1024
    private let lock = NSLock()
    private let started = ProcessInfo.processInfo.systemUptime
    private var lines: [String] = []
    private var bytes = 0
    private var dropped = 0
    private var connection = 0
    private var station = "—", phase = "Stopped", source = "—", lastError = "—"
    private var retries = 0
    private var fingerprints: [String: Data] = [:]

    func begin(station: Station) -> Int {
        lock.lock(); defer { lock.unlock() }
        connection += 1
        self.station = station.rawValue
        phase = "Connecting"
        source = "—"
        retries = 0
        return connection
    }

    func state(_ trace: DiagnosticTrace?, phase: String, source: String? = nil,
               retries: Int? = nil, error: String? = nil, station: Station? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let trace, trace.connection != connection { return }
        if let station { self.station = station.rawValue }
        self.phase = Self.clean(phase)
        if let source { self.source = Self.clean(source) }
        if let retries { self.retries = retries }
        if let error { lastError = Self.clean(error) }
    }

    func record(_ stage: String, _ detail: String = "", trace: DiagnosticTrace? = nil) {
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let context = trace.map { "c\($0.connection)/a\($0.attempt) \($0.station) " } ?? ""
        let line = String(format: "+%.3fs ", elapsed) + context + Self.clean(stage + " " + detail)
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
        bytes += line.utf8.count + 1
        while lines.count > Self.maximumEvents || bytes > Self.maximumBytes {
            bytes -= lines.removeFirst().utf8.count + 1
            dropped += 1
        }
    }

    func stream(_ url: URL, trace: DiagnosticTrace) {
        streams([url], trace: trace)
    }

    func streams(_ urls: [URL], trace: DiagnosticTrace) {
        guard Station(rawValue: trace.station) != nil else { return }
        var hash = SHA256()
        for url in urls {
            hash.update(data: Data(url.absoluteString.utf8))
            hash.update(data: Data([0]))
        }
        let digest = Data(hash.finalize())
        lock.lock()
        let previous = fingerprints[trace.station]
        fingerprints[trace.station] = digest
        lock.unlock()
        trace.event("stream.address", "comparedToPrevious=\(previous == nil ? "first" : previous == digest ? "same" : "changed"); candidates=\(urls.count)")
    }

    func snapshot() -> DiagnosticSnapshot {
        lock.lock(); defer { lock.unlock() }
        return DiagnosticSnapshot(station: station, phase: phase, source: source, retries: retries,
                                  lastError: lastError, lines: lines, bytes: bytes, dropped: dropped)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        lines.removeAll(keepingCapacity: false)
        bytes = 0; dropped = 0
        fingerprints.removeAll(keepingCapacity: false)
        lastError = "—"
    }

    func report() -> String {
        let s = snapshot()
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let header = """
        RadioBar diagnostics v1
        App: \(Self.clean(version)) (\(Self.clean(build)))
        macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion); arch: arm64
        Captured UTC: \(ISO8601DateFormatter().string(from: Date()))
        Station: \(s.station); phase: \(s.phase); source: \(s.source); retries: \(s.retries)/4
        Last error: \(s.lastError)
        Memory-only; max 100 events / 64 KiB; discarded: \(s.dropped)
        c=connection; a=attempt; timestamps=elapsed since app launch
        AVPlayer item: 0=unknown, 1=ready, 2=failed; control: 0=paused, 1=waiting, 2=playing
        Full URLs, tokens, headers and response bodies are omitted.
        Recent events:
        """
        var events = s.lines
        while (header + "\n" + events.joined(separator: "\n")).utf8.count > Self.maximumBytes && !events.isEmpty {
            events.removeFirst()
        }
        return header + "\n" + events.joined(separator: "\n")
    }

    // Defense in depth. Call sites pass only controlled labels, numbers and error codes.
    static func clean(_ input: String) -> String {
        var value = input.replacingOccurrences(of: #"(?i)https?://[^\s<>\"']+"#, with: "[URL omitted]", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)\b(stream-token|token|token_key|key|signature|authorization)\s*[:=]\s*[^\s,;]+"#,
                                          with: "$1=[omitted]", options: .regularExpression)
        value = value.components(separatedBy: .newlines).joined(separator: " ")
        return String(value.prefix(400))
    }

    static func error(_ error: Error) -> String {
        if let error = error as? RadioError {
            switch error {
            case .timeout: return "app.noProgressTimeout"
            case .invalidResponse: return "app.invalidResponse"
            case .playback: return "app.playbackFailed"
            }
        }
        var result: [String] = []
        var current: NSError? = error as NSError
        for _ in 0..<3 {
            guard let e = current else { break }
            // Never include localizedDescription/userInfo: they may embed signed URLs.
            let known = [NSURLErrorDomain, "AVFoundationErrorDomain", "CoreMediaErrorDomain", NSCocoaErrorDomain, NSPOSIXErrorDomain]
            result.append("\(known.contains(e.domain) ? e.domain : "OtherErrorDomain")/\(e.code)")
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return result.joined(separator: " <- ")
    }
}
