import Foundation
import AVFoundation

/// Bounded, muted live validation through the production player and fixed resolver.
/// Every case uses independent preferences; never launch or configure the installed App.
@main
struct PlaybackProbe {
    @MainActor static func main() async {
        let targets: [(Station, Int)] = CommandLine.arguments.contains("--network-fixed")
            ? [(.kiss, 0), (.musicRadio, 0)]
            : CommandLine.arguments.contains("--network-guangdong")
            ? [(.guangdong, 0), (.guangdong, 1)]
            : CommandLine.arguments.contains("--network-ufo")
            ? [(.ufo, 0), (.ufo, 1)]
            : [(.kiss, 0), (.musicRadio, 0), (.bcc, 0), (.bcc, 1), (.ufo, 0), (.ufo, 1),
               (.guangdong, 0), (.guangdong, 1)]
        var failures = 0
        for (station, attempt) in targets {
            let suite = "RadioBar.PlaybackProbe.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(station.id, forKey: "station")
            defaults.set(0.0, forKey: "volume")
            let audio = NativeAudioPlayback()
            let store = RadioDiagnostics()
            // Explicit probe attempts use the same resolver; production recovery stays bounded as usual.
            let model = RadioPlayer(resolver: ProbeResolver(offset: attempt), defaults: defaults,
                                    diagnostics: store, makeAudio: { audio })
            model.play()
            var lastTime = 0.0
            let clock = ContinuousClock()
            var progressingSince: ContinuousClock.Instant?
            var passed = false
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let state = audio.state
                if state.isPlaying && state.time.isFinite && state.time > lastTime + 0.05 {
                    if progressingSince == nil { progressingSince = clock.now }
                } else {
                    progressingSince = nil
                }
                lastTime = state.time.isFinite ? state.time : 0
                if let progressingSince, clock.now - progressingSince >= .seconds(5), model.statusText.en == "Playing" {
                    passed = true; break
                }
                if !model.wantsPlayback || store.snapshot().retries > 0 { break }
            }
            let label = "\(station.menuName.en) · \(station.sourceText(attempt: attempt).en)"
            print("\(passed ? "PASS" : "FAIL"): \(label), production RadioPlayer / muted native AVPlayer / 5s continuous time progression")
            if !passed { failures += 1; print(store.report()) }
            model.pause()
        }
        let suite = "RadioBar.PlaybackProbe.Cancel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.0, forKey: "volume")
        let model = RadioPlayer(defaults: defaults, diagnostics: RadioDiagnostics())
        model.play(); model.select(model.station == .kiss ? .musicRadio : .kiss); model.pause()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let cancelled = !model.wantsPlayback && !model.isPlaying && model.statusText.en == "Paused"
        print("\(cancelled ? "PASS" : "FAIL"): rapid switch then pause cancels stale work with isolated preferences")
        if !cancelled { failures += 1 }
        if failures > 0 { exit(1) }
    }
}

private struct ProbeResolver: StreamURLResolving {
    let offset: Int
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        try await StreamResolver().resolve(station, attempt: offset + attempt)
    }
}
