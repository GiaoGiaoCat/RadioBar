import Foundation
import AVFoundation

@MainActor
private final class TestAudio: AudioPlayback {
    var volume: Float = 0 { didSet { volumeHistory.append(volume) } }
    var volumeHistory: [Float] = []
    var url: URL?
    var ready = false
    var advancing = true
    var control: AVPlayer.TimeControlStatus = .paused
    var failed = false
    var failOnLoad = false
    var time: Double = 0
    var clearCount = 0
    var state: AudioPlaybackState {
        if ready && advancing && control == .playing { time += 0.1 }
        return AudioPlaybackState(itemStatus: failed ? .failed : ready ? .readyToPlay : .unknown,
                                  control: control, time: time,
                                  bufferEmpty: !ready, likelyToKeepUp: ready)
    }
    func load(_ url: URL) {
        self.url = url; ready = false; failed = failOnLoad; time = 0
    }
    func play() { control = ready ? .playing : .waitingToPlayAtSpecifiedRate }
    func pause() { control = .paused }
    func clear() {
        clearCount += 1; volume = 0; url = nil; ready = false; control = .paused
    }
    func connect() { ready = true; control = .playing; advancing = true }
    func recordErrors(trace: DiagnosticTrace) { trace.event("fixture.audio.failed") }
}

@MainActor
private final class TestResolver: StreamURLResolving {
    var failures: Set<Station> = []
    var held: Set<Station> = []
    var calls: [Station] = []
    var attempts: [Int] = []
    var pending: [Station: [CheckedContinuation<StreamAddress, Error>]] = [:]
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        calls.append(station)
        attempts.append(attempt)
        if failures.contains(station) { throw NSError(domain: NSURLErrorDomain, code: -1004) }
        if held.contains(station) {
            return try await withCheckedThrowingContinuation { pending[station, default: []].append($0) }
        }
        return try await StreamResolver().resolve(station, attempt: attempt)
    }
    static func address(_ station: Station) -> StreamAddress {
        StreamAddress(url: URL(string: "https://fixture.invalid/\(station.rawValue).mp3")!)
    }
    func release(_ station: Station) {
        pending.removeValue(forKey: station)?.forEach { $0.resume(returning: Self.address(station)) }
    }
    func releaseAll() { for station in Array(pending.keys) { release(station) } }
}

@MainActor
private final class Harness {
    let suite = "RadioBar.AudioTransitions.\(UUID().uuidString)"
    let defaults: UserDefaults
    let resolver = TestResolver()
    var decks: [TestAudio] = []
    var clock: TimeInterval = 100
    var retryDelays: [Int] = []
    var retryDetails: [RadioText] = []
    var playbackClock = Date(timeIntervalSince1970: 1_700_000_000)
    var sleepInstant = ContinuousClock().now
    var radio: RadioPlayer!
    init(realTicker: Bool = false) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(0.8, forKey: "volume")
        radio = RadioPlayer(resolver: resolver, defaults: defaults,
                            sleepClockNow: { [unowned self] in sleepInstant },
                            diagnostics: RadioDiagnostics(),
                            makeAudio: { [unowned self] in
                                let deck = TestAudio(); decks.append(deck); return deck
                            },
                            fadeNow: { [unowned self] in realTicker ? ProcessInfo.processInfo.systemUptime : clock },
                            automaticFadeTicks: realTicker, playbackNow: { [unowned self] in playbackClock }, pollNanoseconds: 2_000_000,
                            waitForRetry: { [unowned self] seconds in
                                retryDelays.append(seconds); retryDetails.append(radio.detailText)
                                try await Task.sleep(nanoseconds: 1_000_000)
                            })
    }
    func close() {
        radio.pause(); radio.sleepTimer.cancel(); resolver.releaseAll()
        defaults.removePersistentDomain(forName: suite)
    }
    func initial() async -> TestAudio {
        radio.select(.bcc)
        await wait { self.decks.last?.url != nil }
        let audio = decks.last!
        audio.connect()
        await wait { self.radio.isPlaying && self.radio.statusText.en == "Playing" }
        return audio
    }
    func candidate(_ station: Station) async -> TestAudio {
        let count = decks.count
        radio.select(station)
        await wait { self.decks.count > count && self.decks.last?.url != nil }
        return decks.last!
    }
    func expire() {
        radio.sleepTimer.minutesInput = "1"
        radio.sleepTimer.start()
        sleepInstant = sleepInstant.advanced(by: .seconds(61))
        radio.sleepTimer.refresh()
    }
}

@MainActor
private func wait(_ condition: () -> Bool) async {
    for _ in 0..<500 {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    preconditionFailure("Timed out waiting for playback transition")
}
private func near(_ value: Float, _ expected: Float) {
    precondition(abs(value - expected) < 0.015, "Volume \(value), expected \(expected)")
}

@main
struct AudioTransitionTests {
    @MainActor static func main() async {
        await lateResolveAfterSwitchAndPause()
        await fixedSourceRecoveryAndNoRefresh()
        await boundedFixedSourceRetries()
        await pendingSourceSnapshotAfterReload()
        await catalogueReloadDuringPlayback()
        await catalogueReloadDuringTransitionAndRetry()
        await muteAndRestore()
        await muteDuringTransitions()
        await smoothEqualPowerCurve()
        await successfulSwitch()
        await failedSwitch()
        await failedMediaLoad()
        await stalledSwitch()
        await rapidSwitchAndPause()
        await rapidSwitchKeepingNewerAudio()
        await lateResolveAndSleep()
        await sleepDuringCrossfade()
        await sleepOverride()
        await realSleepTicker()
        await realCrossfadeTicker()
    }

    /// Migrated from the removed provider tests: cancellation must also guard uncooperative results.
    @MainActor private static func lateResolveAfterSwitchAndPause() async {
        let h = Harness(); defer { h.close() }
        h.resolver.held = [.musicRadio, .bcc]
        h.radio.select(.musicRadio)
        await wait { h.resolver.pending[.musicRadio]?.isEmpty == false }
        precondition(h.radio.statusText.en == "Connecting…")
        h.radio.select(.bcc)
        await wait { h.resolver.pending[.bcc]?.isEmpty == false }
        h.resolver.release(.musicRadio)
        try? await Task.sleep(nanoseconds: 10_000_000)
        precondition(h.radio.station == .bcc && h.radio.detailText == Station.bcc.resolutionText)
        precondition(h.decks.allSatisfy { $0.url == nil })
        h.radio.pause(); h.resolver.release(.bcc)
        try? await Task.sleep(nanoseconds: 10_000_000)
        precondition(h.radio.statusText.en == "Paused" && !h.radio.wantsPlayback && !h.radio.isPlaying)
        precondition(h.decks.allSatisfy { $0.url == nil })
        print("PASS: late resolve after switch/pause cannot load or revive audio (migrated provider coverage)")
    }

    @MainActor private static func fixedSourceRecoveryAndNoRefresh() async {
        let original = Station.allCases
        defer { StationCatalog.apply(original) }
        // Use built-in identities with fictional address data to catch accidental identity branches.
        for identity in ["builtin.kiss", "builtin.music-radio", "bcc"] {
            let urls = (0..<3).map { URL(string: "https://fixture.invalid/PRIVATE_PATH/\($0).m3u8?expires=1&token=SECRET")! }
            let station = Station(id: identity, title: RadioText("测试电台", "Test station"),
                                  category: RadioText("测试", "Test"), urls: urls)
            StationCatalog.apply(original.map { $0.id == identity ? station : $0 })
            let h = Harness(); defer { h.close() }
            h.radio.select(station); if !h.radio.wantsPlayback { h.radio.play() }
            await wait { h.decks.last?.url == urls[0] }
            let deck = h.decks.last!
            deck.failed = true
            await wait { h.resolver.attempts == [0, 1] && deck.url == urls[1] }
            deck.connect()
            await wait { h.radio.statusText.en == "Playing" }
            precondition(h.radio.detailText.en.contains("Backup stream") && h.radio.diagnostics.snapshot().source == "backup")
            let clearCount = deck.clearCount
            // Poll with progressing fake media while crossing 60s health and both old KISS refresh points.
            for delta in [61.0, 1801.0, 1801.0] {
                h.playbackClock += delta
                try? await Task.sleep(nanoseconds: 10_000_000)
                precondition(h.resolver.attempts == [0, 1] && deck.clearCount == clearCount)
                precondition(h.radio.statusText.en == "Playing" && deck.url == urls[1])
            }
            precondition(h.radio.diagnostics.snapshot().retries == 0)
            let report = h.radio.diagnostics.report()
            precondition(report.contains("retry.budgetReset") && !report.contains("stream.renew"))
            for value in ["PRIVATE_PATH", "SECRET", "https://"] { precondition(!report.contains(value)) }
            // Stable backup fails: continue to third source with a reset 2s budget, not back to primary.
            deck.failed = true
            await wait { h.resolver.attempts == [0, 1, 2] && deck.url == urls[2] }
            precondition(h.radio.diagnostics.snapshot().retries == 1 && h.radio.diagnostics.snapshot().source == "backup")
            deck.connect(); await wait { h.radio.statusText.en == "Playing" }
            precondition(h.radio.detailText.en.contains("Backup stream"))
            deck.advancing = false
            try? await Task.sleep(nanoseconds: 10_000_000)
            h.playbackClock += 26
            await wait { h.resolver.attempts == [0, 1, 2, 3] && deck.url == urls[0] }
            precondition(h.radio.diagnostics.snapshot().source == "primary")
            precondition(h.radio.diagnostics.report().contains("app.noProgressTimeout"))
            deck.connect(); await wait { h.radio.statusText.en == "Playing" }
            precondition(h.radio.detailText.en.contains("Primary stream"))
        }
        print("PASS: built-in/ordinary players share A→B→C→A recovery, health reset without source reset, no-progress recovery, opaque expiry parameters and no scheduled refresh across >60 minutes")
    }

    @MainActor private static func boundedFixedSourceRetries() async {
        let original = Station.allCases
        defer { StationCatalog.apply(original) }
        for count in 1...3 {
            let station = Station(id: "builtin.kiss", title: RadioText("测试电台", "Test station"),
                                  category: RadioText("测试", "Test"),
                                  urls: (0..<count).map { URL(string: "https://fixture.invalid/\($0).mp3")! })
            StationCatalog.apply(original.map { $0.id == station.id ? station : $0 })
            let h = Harness(); defer { h.close() }
            h.resolver.failures.insert(station)
            h.radio.play()
            await wait { h.radio.statusText.en == "Connection failed" }
            precondition(h.resolver.attempts == [0, 1, 2, 3, 4])
            precondition(h.retryDelays == [2, 4, 8, 16])
            precondition(h.retryDetails.allSatisfy { $0.en.contains(count == 1 ? "Retry connection" : "Switch stream") })
            precondition(h.radio.diagnostics.snapshot().source == station.sourceName(attempt: 4))
            precondition(!h.radio.wantsPlayback && !h.radio.isPlaying)
        }
        print("PASS: player keeps exactly 5 attempts / 2,4,8,16s backoff for 1/2/3 sources; single-source retry never claims a backup")
    }

    @MainActor private static func pendingSourceSnapshotAfterReload() async {
        let original = Station.allCases
        let urls = (0..<3).map { URL(string: "https://fixture.invalid/\($0).mp3")! }
        let before = Station(id: "bcc", title: RadioText("原台", "Original"), category: RadioText("测试", "Test"), urls: urls)
        StationCatalog.apply(original.map { $0.id == before.id ? before : $0 })
        let h = Harness(); defer { h.close(); StationCatalog.apply(original) }
        h.radio.select(before)
        await wait { h.decks.last?.url == urls[0] }
        h.resolver.held.insert(before)
        h.decks.last!.failed = true
        await wait { h.resolver.pending[before]?.isEmpty == false }
        precondition(h.radio.detailText.en.contains("Backup stream"))
        let after = Station(id: "bcc", title: RadioText("重载", "Reloaded"), category: RadioText("测试", "Test"), urls: [urls[0]])
        StationCatalog.apply(original.map { $0.id == before.id ? after : $0 })
        precondition(h.radio.detailText.en.contains("Reloaded") && h.radio.detailText.en.contains("Backup stream"))
        precondition(h.radio.diagnostics.snapshot().source == "backup")
        h.radio.pause(); h.resolver.release(before)
        try? await Task.sleep(nanoseconds: 10_000_000)
        precondition(h.decks.allSatisfy { $0.url == nil })
        print("PASS: pending backup keeps its source snapshot and diagnostic label when a one-source configuration reloads; late completion after pause is ignored")
    }

    @MainActor private static func catalogueReloadDuringPlayback() async {
        let original = Station.allCases
        let h = Harness()
        defer { h.close(); StationCatalog.apply(original) }
        let audio = await h.initial()
        h.radio.toggleMute()
        h.radio.sleepTimer.minutesInput = "30"
        h.radio.sleepTimer.start()
        let calls = h.resolver.calls.count
        let clears = audio.clearCount
        let renamed = Station(id: "bcc", title: RadioText("新名字", "Renamed"), category: RadioText("测试", "Test"),
                              urls: [URL(string: "https://fixture.invalid/new-address.mp3")!])
        StationCatalog.apply(original.map { $0.id == renamed.id ? renamed : $0 })
        precondition(h.radio.station.menuName.en == "Renamed" && !h.radio.stationIsRemoved)
        precondition(audio.clearCount == clears && h.resolver.calls.count == calls)
        precondition(h.radio.isMuted && h.radio.volume == 0.8 && h.radio.sleepTimer.isRunning)
        h.radio.play()
        await wait { h.resolver.calls.count > calls }
        precondition(h.resolver.calls.last?.urls == renamed.urls)
        h.decks.last!.connect()
        await wait { h.radio.isPlaying }
        let live = h.decks.last!
        let beforeRemoval = live.clearCount
        StationCatalog.apply(original.filter { $0.id != "bcc" })
        precondition(h.radio.stationIsRemoved && h.radio.wantsPlayback && live.clearCount == beforeRemoval)
        h.radio.pause()
        h.radio.play()
        precondition(h.radio.station == .kiss && !h.radio.stationIsRemoved)
        h.radio.pause()
        StationCatalog.apply(original)
        h.resolver.held = [.ufo]
        h.radio.select(.ufo)
        await wait { h.resolver.pending[.ufo]?.isEmpty == false }
        let changed = Station(id: "ufo", title: RadioText("新飞碟", "New UFO"), category: RadioText("测试", "Test"),
                              urls: [URL(string: "https://fixture.invalid/ufo-new.mp3")!])
        StationCatalog.apply(original.map { $0.id == "ufo" ? changed : $0 })
        h.radio.pause()
        h.resolver.release(.ufo)
        try? await Task.sleep(nanoseconds: 10_000_000)
        precondition(!h.radio.wantsPlayback && h.radio.station.menuName.en == "New UFO")
        precondition(h.decks.allSatisfy { $0.url == nil })
        print("PASS: catalogue reload refreshes active metadata without reconnecting or changing mute/volume/sleep, next connection uses new addresses, removed audio continues until switching, and late results cannot revive paused audio")
    }

    @MainActor private static func catalogueReloadDuringTransitionAndRetry() async {
        let original = Station.allCases
        let changed = Station(id: "ufo", title: RadioText("新飞碟", "New UFO"), category: RadioText("测试", "Test"),
                              urls: [URL(string: "https://fixture.invalid/new-ufo.mp3")!])
        let h = Harness()
        defer { h.close(); StationCatalog.apply(original) }
        let outgoing = await h.initial()
        let incoming = await h.candidate(.ufo)
        let calls = h.resolver.calls.count
        StationCatalog.apply(original.map { $0.id == "ufo" ? changed : $0 })
        precondition(h.resolver.calls.count == calls && outgoing.url != nil && incoming.url != nil)
        incoming.connect()
        await wait { h.radio.statusText.en == "Playing" }
        h.clock += 4; h.radio.advanceAudioFade()
        near(outgoing.volume, 0.5656854); near(incoming.volume, 0.5656854)
        h.clock += 4; h.radio.advanceAudioFade()
        near(incoming.volume, 0.8)
        precondition(outgoing.url == nil && h.radio.station.menuName.en == "New UFO")
        h.radio.pause()
        StationCatalog.apply(original)
        h.resolver.failures = [.bcc]
        h.radio.select(.bcc)
        let retryBaseline = h.resolver.calls.count
        await wait { h.resolver.calls.count > retryBaseline }
        let newBCC = Station(id: "bcc", title: RadioText("新中广", "New BCC"), category: RadioText("测试", "Test"),
                             urls: [URL(string: "https://fixture.invalid/new-bcc.mp3")!])
        StationCatalog.apply(original.map { $0.id == "bcc" ? newBCC : $0 })
        await wait { h.resolver.calls.contains { $0.id == "bcc" && $0.urls == newBCC.urls } }
        print("PASS: reloading during a pending switch preserves both decks and the 8s equal-power fade; subsequent automatic retries use updated addresses")
    }

    @MainActor private static func muteAndRestore() async {
        let h = Harness(); defer { h.close() }
        let audio = await h.initial()
        let calls = h.resolver.calls
        h.radio.toggleMute()
        precondition(h.radio.isMuted && h.radio.isSilent && h.radio.volume == 0.8)
        near(audio.volume, 0)
        precondition(h.defaults.double(forKey: "volume") == 0.8)
        precondition(h.radio.isPlaying && h.radio.wantsPlayback && h.resolver.calls == calls)
        h.radio.toggleMute()
        near(audio.volume, 0.8)
        precondition(!h.radio.isMuted && !h.radio.isSilent)
        h.radio.volume = 0.27
        h.radio.toggleMute()
        near(audio.volume, 0)
        h.radio.volume = 0.42
        precondition(!h.radio.isMuted)
        near(audio.volume, 0.42)
        h.radio.volume = 0
        precondition(h.radio.isSilent)
        h.radio.toggleMute()
        near(audio.volume, 0.42)
        precondition(h.radio.volume == 0.42 && !h.radio.isSilent)
        h.radio.toggleMute()
        let restored = RadioPlayer(resolver: h.resolver, defaults: h.defaults, makeAudio: { TestAudio() })
        precondition(restored.volume == 0.42 && !restored.isMuted && !restored.wantsPlayback)
        h.radio.pause()
        h.radio.toggleMute()
        precondition(!h.radio.wantsPlayback && !h.radio.isPlaying && h.resolver.calls == calls)
        print("PASS: mute/unmute restores saved slider volume without pausing or reloading; slider unmutes, zero restores last positive value, restart is not silently muted")
    }

    @MainActor private static func muteDuringTransitions() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial()
        h.radio.toggleMute()
        let new = await h.candidate(.ufo)
        new.connect()
        await wait { h.radio.statusText.en == "Playing" }
        h.clock += 4; h.radio.advanceAudioFade()
        near(old.volume, 0); near(new.volume, 0)
        h.radio.toggleMute()
        near(old.volume, 0.5656854); near(new.volume, 0.5656854)
        h.radio.toggleMute()
        h.expire()
        h.clock += 3; h.radio.advanceAudioFade()
        near(old.volume, 0); near(new.volume, 0)
        h.radio.toggleMute()
        near(old.volume, 0.2828427); near(new.volume, 0.2828427)
        h.clock += 3; h.radio.advanceAudioFade()
        near(old.volume, 0); near(new.volume, 0)
        precondition(old.url == nil && new.url == nil && !h.radio.wantsPlayback)
        precondition(h.radio.volume == 0.8 && h.defaults.double(forKey: "volume") == 0.8)
        print("PASS: mute gates both crossfade decks and newly connected audio; unmute honors current fade gains; sleep fade still finishes with volume preference intact")
    }

    @MainActor private static func smoothEqualPowerCurve() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial()
        h.radio.volume = 1
        let new = await h.candidate(.ufo)
        new.connect(); await wait { h.radio.statusText.en == "Playing" }
        let start = h.clock
        let checkpoints: [(Double, Float, Float)] = [
            (0, 1, 0), (0.08, 0.9999999, 0.0004681),
            (2, 0.9700313, 0.2429802), (4, 0.7071068, 0.7071068),
            (6, 0.2429802, 0.9700313), (7.92, 0.0004681, 0.9999999), (8, 0, 1)
        ]
        var previousOld: Float = 1
        var previousNew: Float = 0
        for (elapsed, expectedOld, expectedNew) in checkpoints {
            h.clock = start + elapsed; h.radio.advanceAudioFade()
            precondition(abs(old.volume - expectedOld) < 0.0001 && abs(new.volume - expectedNew) < 0.0001)
            precondition(abs(old.volume * old.volume + new.volume * new.volume - 1) < 0.00001)
            precondition(old.volume <= previousOld && new.volume >= previousNew)
            precondition(h.decks.filter { $0.url != nil }.count == (elapsed < 8 ? 2 : 1))
            previousOld = old.volume; previousNew = new.volume
        }
        print("PASS: 8s smooth equal-power envelope has gentle endpoints, monotonic gains, unit summed power and exact final deck release")
    }

    @MainActor private static func successfulSwitch() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial()
        let new = await h.candidate(.ufo)
        near(old.volume, 0.8); near(new.volume, 0)
        // Ready alone, or even a playing flag without timeline progress, is insufficient.
        new.ready = true; new.advancing = false
        try? await Task.sleep(nanoseconds: 12_000_000)
        near(old.volume, 0.8); near(new.volume, 0)
        new.control = .playing
        try? await Task.sleep(nanoseconds: 12_000_000)
        near(old.volume, 0.8); near(new.volume, 0)
        new.advancing = true
        await wait { h.radio.statusText.en == "Playing" }
        h.clock += 4; h.radio.advanceAudioFade()
        near(old.volume, 0.5656854); near(new.volume, 0.5656854)
        h.radio.volume = 0.6
        near(old.volume, 0.4242641); near(new.volume, 0.4242641)
        h.clock += 4; h.radio.advanceAudioFade()
        near(old.volume, 0); near(new.volume, 0.6)
        precondition(old.url == nil && new.url != nil && h.radio.station == .ufo)
        precondition(h.defaults.double(forKey: "volume") == 0.6)
        print("PASS: new stream must be ready, playing and progressing; 8s smooth equal-power crossfade endpoints/midpoint and live volume changes; old deck released")
    }

    @MainActor private static func failedSwitch() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial()
        old.volumeHistory.removeAll()
        h.resolver.failures.insert(.ufo)
        h.radio.select(.ufo)
        await wait { h.resolver.calls.filter { $0 == .ufo }.count == 5 && h.radio.station == .bcc && h.radio.statusText.en == "Playing" }
        near(old.volume, 0.8)
        precondition(old.url != nil && old.clearCount == 0)
        precondition(old.volumeHistory.allSatisfy { abs($0 - 0.8) < 0.01 })
        precondition(h.resolver.calls.filter { $0 == .bcc }.count == 1)
        precondition(h.radio.detailText.en.contains("Could not connect"))
        print("PASS: failed new station never fades old audio; bounded retry exhaustion returns to old deck without reload and resumes monitoring")
    }

    @MainActor private static func stalledSwitch() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial(); let new = await h.candidate(.ufo)
        new.connect(); await wait { h.radio.statusText.en == "Playing" }
        h.clock += 2; h.radio.advanceAudioFade()
        near(old.volume, 0.776025); near(new.volume, 0.194384)
        new.control = .waitingToPlayAtSpecifiedRate
        await wait { h.radio.statusText.en == "Buffering…" }
        near(old.volume, 0.8); near(new.volume, 0)
        h.clock += 8; h.radio.advanceAudioFade()
        near(old.volume, 0.8); near(new.volume, 0)
        new.connect(); await wait { h.radio.statusText.en == "Playing" }
        h.clock += 8; h.radio.advanceAudioFade()
        near(old.volume, 0); near(new.volume, 0.8)
        print("PASS: buffering aborts an in-progress crossfade, restores old audio, and only restarts after new playback recovers")
    }

    @MainActor private static func failedMediaLoad() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial()
        let new = await h.candidate(.ufo)
        old.volumeHistory.removeAll()
        new.failOnLoad = true; new.failed = true
        await wait { h.resolver.calls.filter { $0 == .ufo }.count == 5 && h.radio.station == .bcc && h.radio.statusText.en == "Playing" }
        near(old.volume, 0.8); near(new.volume, 0)
        precondition(old.volumeHistory.allSatisfy { abs($0 - 0.8) < 0.01 })
        precondition(old.clearCount == 0 && new.url == nil)
        print("PASS: a resolved URL whose media player fails also causes no fade and retains the old playing station")
    }

    @MainActor private static func rapidSwitchAndPause() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial(); let second = await h.candidate(.ufo)
        second.connect(); await wait { h.radio.statusText.en == "Playing" }
        h.clock += 1; h.radio.advanceAudioFade()
        let third = await h.candidate(.guangdong)
        near(old.volume, 0.8); near(second.volume, 0); near(third.volume, 0)
        precondition(second.url == nil)
        third.connect(); await wait { h.radio.statusText.en == "Playing" }
        h.clock += 2; h.radio.advanceAudioFade()
        h.radio.pause()
        h.clock += 20; h.radio.advanceAudioFade()
        precondition(h.decks.allSatisfy { $0.url == nil && $0.volume == 0 })
        precondition(!h.radio.wantsPlayback && !h.radio.isPlaying)
        print("PASS: rapid switching retains only one audible outgoing deck; pause cancels both decks and stale fade completion")
    }

    @MainActor private static func lateResolveAndSleep() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial()
        h.resolver.held.insert(.ufo)
        h.radio.select(.ufo)
        await wait { h.resolver.pending[.ufo] != nil }
        h.expire()
        precondition(!h.radio.wantsPlayback && h.radio.statusText.en == "Fading out…")
        let calls = h.resolver.calls.count
        h.resolver.release(.ufo)
        try? await Task.sleep(nanoseconds: 10_000_000)
        precondition(h.radio.sleepTimer.isFadingOut)
        h.clock += 0.6; h.radio.advanceAudioFade()
        near(old.volume, 0.8 * 0.972)
        h.clock += 2.4; h.radio.advanceAudioFade()
        near(old.volume, 0.4)
        precondition(h.decks.filter { $0.url != nil }.count == 1)
        h.radio.sleepTimer.minutesInput = "30"
        h.radio.sleepTimer.start() // New countdown must not undo an already expired timer's fade.
        precondition(h.radio.sleepTimer.isRunning && h.radio.sleepTimer.isFadingOut)
        h.clock += 2.4; h.radio.advanceAudioFade()
        near(old.volume, 0.8 * 0.028)
        h.clock += 0.6; h.radio.advanceAudioFade()
        precondition(h.radio.statusText.en == "Sleep timer ended" && !h.radio.isPlaying && !h.radio.sleepTimer.isFadingOut)
        precondition(h.radio.sleepTimer.isRunning && h.radio.sleepTimer.remainingSeconds == 1800)
        precondition(h.decks.allSatisfy { $0.url == nil && $0.volume == 0 })
        precondition(h.radio.volume == 0.8 && h.defaults.double(forKey: "volume") == 0.8 && h.resolver.calls.count == calls)
        print("PASS: sleep expiry cancels pending connections immediately, ignores late resolves, fades old audio for 6s and never persists faded volume")
    }

    @MainActor private static func rapidSwitchKeepingNewerAudio() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial(); let newer = await h.candidate(.ufo)
        newer.connect(); await wait { h.radio.statusText.en == "Playing" }
        h.clock += 6; h.radio.advanceAudioFade()
        let pending = await h.candidate(.guangdong)
        near(old.volume, 0); near(newer.volume, 0.8); near(pending.volume, 0)
        precondition(old.url == nil && newer.url != nil)
        print("PASS: rapid switching late in a crossfade retains the newer louder station and releases the earlier one")
    }

    @MainActor private static func sleepDuringCrossfade() async {
        let h = Harness(); defer { h.close() }
        let old = await h.initial(); let new = await h.candidate(.ufo)
        new.connect(); await wait { h.radio.statusText.en == "Playing" }
        h.clock += 4; h.radio.advanceAudioFade()
        h.expire()
        h.clock += 3; h.radio.advanceAudioFade()
        near(old.volume, 0.2828427); near(new.volume, 0.2828427)
        h.clock += 3; h.radio.advanceAudioFade()
        precondition(old.url == nil && new.url == nil && !h.radio.isPlaying)
        precondition(h.radio.volume == 0.8)
        print("PASS: sleep countdown during a crossfade fades both currently audible gains to silence over 6s")
    }

    @MainActor private static func sleepOverride() async {
        let h = Harness(); defer { h.close() }
        _ = await h.initial(); h.expire()
        h.clock += 1; h.radio.advanceAudioFade()
        let new = await h.candidate(.guangdong)
        near(new.volume, 0.8)
        new.connect(); await wait { h.radio.statusText.en == "Playing" }
        h.clock += 10; h.radio.advanceAudioFade()
        near(new.volume, 0.8)
        precondition(h.radio.station == .guangdong && h.radio.wantsPlayback && !h.radio.sleepTimer.isFadingOut)
        print("PASS: explicit station selection overrides an active sleep fade; an old fade cannot stop the new playback")
    }

    @MainActor private static func realSleepTicker() async {
        let h = Harness(realTicker: true); defer { h.close() }
        let audio = await h.initial(); h.expire()
        pumpRunLoop(1.2)
        precondition(audio.volume > 0 && audio.volume < 0.75)
        pumpRunLoop(5.0)
        precondition(audio.url == nil && audio.volume == 0 && h.radio.statusText.en == "Sleep timer ended")
        print("PASS: actual main-run-loop fade timer runs without an open UI and stops after 6s")
    }

    @MainActor private static func realCrossfadeTicker() async {
        let h = Harness(realTicker: true); defer { h.close() }
        let old = await h.initial(); let new = await h.candidate(.ufo)
        new.connect(); await wait { h.radio.statusText.en == "Playing" }
        pumpRunLoop(0.6)
        precondition(old.volume > 0 && old.volume < 0.8 && new.volume > 0 && new.volume < 0.8)
        pumpRunLoop(7.6)
        precondition(old.url == nil && old.volume == 0 && new.url != nil)
        near(new.volume, 0.8)
        print("PASS: actual main-run-loop crossfade timer completes in 8s without an open menu")
    }

    @MainActor private static func pumpRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
