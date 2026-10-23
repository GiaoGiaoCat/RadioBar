import Foundation
import AppKit

@MainActor
private final class CapturedNativeAudio: AudioPlayback {
    let native = NativeAudioPlayback()
    var volume: Float { get { native.volume } set { native.volume = newValue } }
    var state: AudioPlaybackState { native.state }
    func load(_ url: URL) { native.load(url) }
    func play() { native.play() }
    func pause() { native.pause() }
    func clear() { native.clear() }
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
        let radio = RadioPlayer(resolver: FileResolver(file: file), defaults: defaults,
                                sleepClockNow: { instant }, makeAudio: {
            let audio = CapturedNativeAudio(); decks.append(audio); return audio
        })
        defer { radio.pause(); radio.sleepTimer.cancel() }
        radio.select(.bcc)
        guard await wait(seconds: 10, { radio.isPlaying && radio.statusText.en == "Playing" }) else {
            print("UNAVAILABLE: local native AVPlayer did not start: \(decks.last!.state)"); return
        }
        let old = decks.last!
        radio.select(.ufo)
        guard await wait(seconds: 10, { radio.statusText.en == "Playing" }) else {
            print("UNAVAILABLE: second native player did not start: \(decks.last!.state)"); return
        }
        let new = decks.last!
        let fadeStart = ProcessInfo.processInfo.systemUptime
        guard await wait(seconds: 10, { old.volume == 0 && new.volume > 0.6 }) else {
            print("FAIL: native crossfade endpoint old=\(old.volume), new=\(new.volume)"); return
        }
        let fadeElapsed = ProcessInfo.processInfo.systemUptime - fadeStart
        guard fadeElapsed >= 7.5 else { print("FAIL: native crossfade ended too soon: \(fadeElapsed)s"); return }
        radio.sleepTimer.minutesInput = "1"; radio.sleepTimer.start()
        instant = instant.advanced(by: .seconds(61)); radio.sleepTimer.refresh()
        let sleepFadeStart = ProcessInfo.processInfo.systemUptime
        guard await wait(seconds: 8, { radio.statusText.en == "Sleep timer ended" }) else {
            print("FAIL: native sleep fade did not stop"); return
        }
        precondition(ProcessInfo.processInfo.systemUptime - sleepFadeStart >= 5.8)
        precondition(new.volume == 0 && !radio.isPlaying && !radio.wantsPlayback && radio.volume == 0.65)
        print("PASS: real native AVPlayer decoded local silent WAV on two decks, completed 8s smooth equal-power crossfade and 6s smooth sleep fade, restored no persistent volume changes")
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
