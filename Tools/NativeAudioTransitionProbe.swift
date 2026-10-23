import Foundation
import AppKit

@MainActor
private final class CapturedNativeAudio: AudioPlayback {
    let native = NativeAudioPlayback()
    var onVolumeChange: (() -> Void)?
    private(set) var isLoaded = false
    var volume: Float {
        get { native.volume }
        set { native.volume = newValue; onVolumeChange?() }
    }
    var state: AudioPlaybackState { native.state }
    func load(_ url: URL) { native.load(url); isLoaded = true }
    func play() { native.play() }
    func pause() { native.pause() }
    func clear() { native.clear(); isLoaded = false }
    func recordErrors(trace: DiagnosticTrace) { native.recordErrors(trace: trace) }
}
private struct FileResolver: StreamURLResolving {
    let file: URL
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        StreamAddress(url: file)
    }
}

@main
struct NativeTransitionProbe {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("RadioBar-native-fade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appendingPathComponent("silence.wav")
        let length: UInt32 = 16_000 * 2 * 20
        var wav = Data()
        func text(_ s: String) { wav.append(contentsOf: s.utf8) }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        text("RIFF"); u32(36 + length); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(16_000); u32(32_000); u16(2); u16(16); text("data"); u32(length)
        wav.append(Data(repeating: 0, count: Int(length))) // Real decoded PCM silence; no audible sound.
        try wav.write(to: file)
        let suite = "RadioBar.NativeTransitionProbe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var instant = ContinuousClock().now
        var decks: [CapturedNativeAudio] = []
        var observeVolumes: (() -> Void)?
        let radio = RadioPlayer(resolver: FileResolver(file: file), defaults: defaults,
                                sleepClockNow: { instant }, makeAudio: {
            let audio = CapturedNativeAudio(); decks.append(audio)
            audio.onVolumeChange = { observeVolumes?() }
            return audio
        })
        defer { radio.pause(); radio.sleepTimer.cancel(); observeVolumes = nil }
        radio.select(.bcc)
        guard await wait(seconds: 10, { radio.isPlaying && radio.statusText.en == "Playing" }) else {
            print("UNAVAILABLE: local native AVPlayer did not start: \(decks.last!.state)"); return
        }
        let old = decks.last!
        var observations: [(time: TimeInterval, old: Float, new: Float)] = []
        observeVolumes = {
            precondition(decks.filter { $0.isLoaded && $0.volume > 0 }.count <= 1,
                         "Native volume writes made two stations audible")
            precondition(decks.filter { $0.isLoaded }.count <= 2)
            if let new = decks.last, new !== old {
                observations.append((ProcessInfo.processInfo.systemUptime, old.volume, new.volume))
            }
        }
        radio.select(.ufo)
        guard await wait(seconds: 10, { radio.statusText.en == "Playing" }) else {
            print("UNAVAILABLE: second native player did not start: \(decks.last!.state)"); return
        }
        let new = decks.last!
        let fadeStart = ProcessInfo.processInfo.systemUptime
        guard await wait(seconds: 5, { !old.isLoaded && new.volume == Float(radio.volume) }) else {
            print("FAIL: native sequential fade endpoint old=\(old.volume), new=\(new.volume)"); return
        }
        let fadeElapsed = ProcessInfo.processInfo.systemUptime - fadeStart
        guard fadeElapsed >= 2.4 && fadeElapsed <= 3.0,
              let firstSilent = observations.first(where: { $0.old == 0 && $0.new == 0 }),
              let firstIncoming = observations.first(where: { $0.new > 0 }),
              firstSilent.time - fadeStart >= 0.7 && firstSilent.time - fadeStart <= 1.0,
              firstIncoming.time - fadeStart >= 1.2 && firstIncoming.time - fadeStart <= 1.5,
              firstIncoming.time - firstSilent.time >= 0.4 && firstIncoming.time - firstSilent.time <= 0.65,
              observations.contains(where: { $0.time - fadeStart >= 0.95 && $0.time - fadeStart <= 1.15 && $0.old == 0 && $0.new == 0 }),
              observations.contains(where: { $0.old > 0 && $0.old < Float(radio.volume) && $0.new == 0 }),
              observations.contains(where: { $0.old == 0 && $0.new > 0 && $0.new < Float(radio.volume) }),
              observations.allSatisfy({ $0.old == 0 || $0.new == 0 }) else {
            print("FAIL: native sequential phase timing or non-overlap, elapsed=\(fadeElapsed)s"); return
        }
        print("PASS: native sequential timing total=\(fadeElapsed)s, incoming begins=\(firstIncoming.time - fadeStart)s, silent interval=\(firstIncoming.time - firstSilent.time)s; every volume write keeps at most one audible deck")
        radio.sleepTimer.minutesInput = "1"; radio.sleepTimer.start()
        instant = instant.advanced(by: .seconds(61)); radio.sleepTimer.refresh()
        let sleepFadeStart = ProcessInfo.processInfo.systemUptime
        guard await wait(seconds: 8, { radio.statusText.en == "Sleep timer ended" }) else {
            print("FAIL: native sleep fade did not stop"); return
        }
        precondition(ProcessInfo.processInfo.systemUptime - sleepFadeStart >= 5.8)
        precondition(new.volume == 0 && !radio.isPlaying && !radio.wantsPlayback && radio.volume == 0.65)
        print("PASS: real native AVPlayer decoded local silent WAV on two decks, completed 0.8s fade-out + 0.5s silence + 1.2s fade-in without overlap and 6s smooth sleep fade, restored no persistent volume changes")
    }
    @MainActor static func wait(seconds: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}
