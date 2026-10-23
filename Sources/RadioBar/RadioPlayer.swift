import Foundation
import AVFoundation
import Combine

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var station: Station
    var stationIsRemoved: Bool { !Station.allCases.contains(station) }
    private var catalogueObservation: AnyCancellable?
    private func displayStation(_ snapshot: Station) -> Station {
        Station(rawValue: snapshot.id) ?? snapshot
    }
    private func refreshStationMetadata() {
        // Publishing the selection refreshes names and removal notices without touching decks or tasks.
        station = displayStation(station)
        if statusText.en == "Playing", currentDeck.failureNote == nil {
            detailText = sourceDescription(currentDeck.station, attempt: currentDeck.sourceAttempt)
        } else if statusText.en == "Connecting…" {
            detailText = connectionDescription(currentDeck.station, attempt: currentDeck.sourceAttempt)
        } else if statusText.en == "Buffering…" {
            detailText = RadioText("正在等待直播数据", "Waiting for live stream data")
        }
    }
    private func sourceDescription(_ snapshot: Station, attempt: Int) -> RadioText {
        let display = displayStation(snapshot)
        let source = snapshot.sourceText(attempt: attempt)
        return RadioText("\(display.menuName.zh) · \(source.zh)", "\(display.menuName.en) · \(source.en)")
    }
    private func connectionDescription(_ snapshot: Station, attempt: Int) -> RadioText {
        let display = displayStation(snapshot)
        let source = snapshot.sourceText(attempt: attempt)
        return RadioText("正在连接\(display.menuName.zh)\(source.zh)", "Connecting to \(display.menuName.en) · \(source.en)")
    }
    @Published private(set) var statusText = RadioText("已停止", "Stopped")
    var status: String { statusText.zh }
    @Published private(set) var detailText = RadioText("选择电台，然后点击播放", "Choose a station, then click Play")
    var detail: String { detailText.zh }
    var needsAttention: Bool { status == "连接失败" || status.hasPrefix("等待重试") }
    @Published private(set) var wantsPlayback = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isMuted = false
    var isSilent: Bool { isMuted || volume <= 0 }
    private var lastAudibleVolume: Double = 0.65
    @Published var volume: Double {
        didSet {
            if volume > 0 {
                lastAudibleVolume = volume
                if isMuted { isMuted = false }
            }
            applyVolumes()
            preferences.set(volume, forKey: "volume")
        }
    }
    let diagnostics: RadioDiagnostics
    private var diagnosticTrace: DiagnosticTrace?

    private final class Deck {
        let audio: any AudioPlayback
        var station: Station
        var address: StreamAddress?
        var sourceAttempt = 0
        var gain: Float = 1
        var failureNote: RadioText?
        init(audio: any AudioPlayback, station: Station) {
            self.audio = audio
            self.station = station
        }
    }
    private struct Fade {
        enum Kind { case crossfade, sleep }
        let kind: Kind
        let start: TimeInterval
        let duration: TimeInterval
        let incomingGain: Float
        let outgoingGain: Float
    }
    private var currentDeck: Deck
    private var outgoingDeck: Deck?
    private var player: any AudioPlayback { currentDeck.audio }
    private var fade: Fade?
    private var fadeTicker: Timer?
    private let makeAudio: @MainActor () -> any AudioPlayback
    private let fadeNow: () -> TimeInterval
    private let automaticFadeTicks: Bool
    private let playbackNow: () -> Date
    private let pollNanoseconds: UInt64
    private let waitForRetry: (Int) async throws -> Void
    private let resolver: any StreamURLResolving
    private let preferences: UserDefaults
    private let sleepClockNow: () -> ContinuousClock.Instant
    lazy var sleepTimer = SleepTimer(defaults: preferences, now: sleepClockNow) { [weak self] in
        self?.stopForSleepTimer()
    }
    private var session: Task<Void, Never>?
    private var generation = UUID()

    init(resolver: any StreamURLResolving = StreamResolver(), defaults: UserDefaults = .standard,
         sleepClockNow: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now },
         diagnostics: RadioDiagnostics = .shared,
         makeAudio: @escaping @MainActor () -> any AudioPlayback = { NativeAudioPlayback() },
         fadeNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticFadeTicks: Bool = true, playbackNow: @escaping () -> Date = Date.init, pollNanoseconds: UInt64 = 500_000_000,
         waitForRetry: @escaping (Int) async throws -> Void = { seconds in
             try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
         }) {
        self.diagnostics = diagnostics
        self.resolver = resolver
        self.preferences = defaults
        self.sleepClockNow = sleepClockNow
        self.makeAudio = makeAudio
        self.fadeNow = fadeNow
        self.automaticFadeTicks = automaticFadeTicks
        self.playbackNow = playbackNow
        self.pollNanoseconds = pollNanoseconds
        self.waitForRetry = waitForRetry
        let startup = PlaybackPreferences(defaults: defaults)
        station = startup.station
        currentDeck = Deck(audio: makeAudio(), station: startup.station)
        diagnostics.state(nil, phase: "Stopped", station: startup.station)
        volume = defaults.object(forKey: "volume") as? Double ?? 0.65
        if volume > 0 { lastAudibleVolume = volume }
        applyVolumes()
        catalogueObservation = NotificationCenter.default.publisher(for: StationCatalog.didChange).sink { [weak self] _ in
            self?.refreshStationMetadata()
        }
        if startup.autoPlayOnLaunch { play() }
    }

    func select(_ newStation: Station) {
        guard let newStation = Station(rawValue: newStation.id) else { return }
        guard station != newStation || currentDeck.station.urls != newStation.urls else { return }
        // Retain the louder *actually playing* deck, including during a rapid
        // switch in the middle of another crossfade. Never retain a pending load.
        var retained: Deck?
        if wantsPlayback {
            let decks: [Deck?] = [currentDeck, outgoingDeck]
            let playingDecks: [Deck] = decks.compactMap { $0 }.filter {
                $0.audio.state.isPlaying && $0.gain > 0 && $0.address != nil
            }
            retained = playingDecks.max(by: { $0.gain < $1.gain })
        }
        diagnostics.record("station.select", newStation.rawValue)
        station = newStation
        beginPlayback(retaining: retained)
    }

    func toggle() { wantsPlayback ? pause() : play() }

    /// Mute gates both decks without touching playback or the saved slider setting.
    func toggleMute() {
        if volume <= 0 { volume = lastAudibleVolume }
        else { isMuted.toggle() }
        applyVolumes()
    }

    func pause() {
        diagnosticTrace?.event("user.pause")
        diagnostics.state(diagnosticTrace, phase: "Paused")
        cancelSession()
        wantsPlayback = false
        statusText = RadioText("已暂停", "Paused")
        detailText = RadioText("恢复播放时将连接最新直播", "Resuming connects to the latest live stream")
    }

    private func applyVolumes() {
        let base: Float = isMuted ? 0 : Float(min(1, max(0, volume)))
        currentDeck.audio.volume = base * currentDeck.gain
        if let outgoingDeck { outgoingDeck.audio.volume = base * outgoingDeck.gain }
    }

    private func cancelRequests() {
        if session != nil { diagnosticTrace?.event("session.cancel", "superseded, paused or stopped") }
        generation = UUID()
        session?.cancel()
        session = nil
    }

    private func cancelFade() {
        if fade?.kind == .sleep { sleepTimer.setFadingOut(false) }
        fadeTicker?.invalidate()
        fadeTicker = nil
        fade = nil
    }

    private func cancelSession(preserving retained: Deck? = nil) {
        cancelRequests()
        cancelFade()
        for deck in [currentDeck, outgoingDeck].compactMap({ $0 }) where deck !== retained {
            deck.audio.clear()
        }
        outgoingDeck = nil
        isPlaying = retained?.audio.state.isPlaying ?? false
    }

    private func startFade(_ kind: Fade.Kind, seconds: TimeInterval) {
        cancelFade()
        fade = Fade(kind: kind, start: fadeNow(), duration: seconds,
                    incomingGain: currentDeck.gain, outgoingGain: outgoingDeck?.gain ?? 0)
        diagnosticTrace?.event(kind == .crossfade ? "audio.crossfade.begin" : "audio.sleepFade.begin", "durationSeconds=\(Int(seconds))" + (kind == .crossfade ? "; curve=smoothstep-equal-power" : "; curve=smoothstep"))
        guard automaticFadeTicks else { return }
        let ticker = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceAudioFade() }
        }
        fadeTicker = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }

    /// Monotonic-time envelope; tests drive the same update with a virtual clock.
    func advanceAudioFade() {
        guard let fade else { return }
        let progress = Float(min(1, max(0, (fadeNow() - fade.start) / fade.duration)))
        if fade.kind == .crossfade {
            // Smoothstep gives zero slope at both ends; the sine/cosine pair
            // preserves summed power for unrelated streams with matching levels.
            let eased = progress * progress * (3 - 2 * progress)
            let angle = Double(eased) * .pi / 2
            currentDeck.gain = Float(sin(angle))
            outgoingDeck?.gain = fade.outgoingGain * Float(cos(angle))
        } else {
            let eased = progress * progress * (3 - 2 * progress)
            currentDeck.gain = fade.incomingGain * (1 - eased)
            outgoingDeck?.gain = fade.outgoingGain * (1 - eased)
        }
        applyVolumes()
        guard progress >= 1 else { return }
        cancelFade()
        if fade.kind == .crossfade {
            outgoingDeck?.audio.clear()
            outgoingDeck = nil
            currentDeck.gain = 1
            applyVolumes()
            diagnosticTrace?.event("audio.crossfade.complete")
        } else {
            finishSleepStop()
        }
    }

    private func startCrossfadeIfNeeded() {
        guard fade == nil, let outgoingDeck else { return }
        guard outgoingDeck.audio.state.isPlaying else {
            outgoingDeck.audio.clear()
            self.outgoingDeck = nil
            currentDeck.gain = 1
            applyVolumes()
            return
        }
        // Called only after the new deck is ready, playing and advancing time.
        currentDeck.gain = 0
        applyVolumes()
        startFade(.crossfade, seconds: 8)
    }

    private func suspendCrossfade() {
        guard let outgoingDeck else { return }
        if fade?.kind == .crossfade {
            diagnosticTrace?.event("audio.crossfade.cancel", "incoming stalled or failed; keep old station")
            cancelFade()
        }
        currentDeck.gain = 0
        outgoingDeck.gain = 1
        applyVolumes()
    }

    private func stopForSleepTimer() {
        diagnostics.record("sleepTimer.expired")
        cancelRequests() // Late resolves/retries must not start audio during the fade.
        cancelFade()
        wantsPlayback = false
        let audible = [currentDeck, outgoingDeck].compactMap { $0 }
            .contains { $0.gain > 0 && $0.audio.state.isPlaying }
        guard audible else { finishSleepStop(); return }
        statusText = RadioText("正在渐弱停止…", "Fading out…")
        detailText = RadioText("睡眠倒计时结束，声音将在 6 秒内平缓渐弱停止", "Sleep timer ended. Fading gently to silence over 6 seconds")
        startFade(.sleep, seconds: 6)
        sleepTimer.setFadingOut(true)
    }

    private func finishSleepStop() {
        cancelSession()
        wantsPlayback = false
        diagnostics.state(diagnosticTrace, phase: "Sleep timer ended")
        diagnosticTrace?.event("audio.sleepFade.complete")
        statusText = RadioText("定时已停止", "Sleep timer ended")
        detailText = RadioText("睡眠倒计时结束，点击播放可重新收听", "The sleep countdown ended. Click Play to listen again")
    }

    private func restoreOutgoing(after failedStation: Station) -> Bool {
        guard let retained = outgoingDeck, retained.audio.state.isPlaying, retained.address != nil else { return false }
        diagnosticTrace?.event("station.fallback", "new station failed; retained old playing deck")
        let failedDisplay = displayStation(failedStation)
        let retainedDisplay = displayStation(retained.station)
        retained.failureNote = RadioText("无法连接\(failedDisplay.menuName.zh)，继续播放\(retainedDisplay.menuName.zh)",
                                         "Could not connect to \(failedDisplay.menuName.en); keeping \(retainedDisplay.menuName.en)")
        station = displayStation(retained.station)
        beginPlayback(reusing: retained)
        return true
    }

    func play() { beginPlayback() }

    private func beginPlayback(retaining retained: Deck? = nil, reusing: Deck? = nil) {
        if reusing == nil {
            station = Station(rawValue: station.id) ?? StationVisibility.visibleStations(defaults: preferences)[0]
        }
        cancelSession(preserving: reusing ?? retained)
        currentDeck = reusing ?? Deck(audio: makeAudio(), station: station)
        outgoingDeck = retained
        currentDeck.gain = retained == nil ? 1 : 0
        outgoingDeck?.gain = 1
        applyVolumes()
        let sourceOffset = reusing?.sourceAttempt ?? 0
        // A configured default can be played without first selecting a menu row.
        preferences.set(station.rawValue, forKey: "station")
        wantsPlayback = true
        statusText = RadioText("连接中…", "Connecting…")
        detailText = connectionDescription(station, attempt: sourceOffset)
        let id = generation
        let sessionStation = station
        let connection = diagnostics.begin(station: sessionStation)
        diagnostics.record("connection.begin", sessionStation.rawValue)
        session = Task { [weak self] in
            guard let self else { return }
            var recovery = PlaybackRecovery()
            var reuseAddress = reusing?.address
            while !Task.isCancelled && self.generation == id {
                // An in-flight resolve keeps its snapshot; the next retry can use newly saved addresses.
                let selected = reuseAddress != nil ? self.currentDeck.station : self.displayStation(sessionStation)
                let trace = DiagnosticTrace(store: self.diagnostics, connection: connection,
                                            attempt: recovery.sourceAttempt + 1, station: selected.rawValue)
                self.diagnosticTrace = trace
                let sourceAttempt = sourceOffset + recovery.sourceAttempt
                let route = selected.sourceName(attempt: sourceAttempt)
                self.diagnostics.state(trace, phase: "Connecting", source: route, retries: recovery.retryCount)
                let attemptBegan = ProcessInfo.processInfo.systemUptime
                trace.event("attempt.begin", "route=\(route); source=\(selected.sourceIndex(attempt: sourceAttempt).map { $0 + 1 } ?? 0)/\(selected.urls.count); retry=\(recovery.retryCount)/4")
                do {
                    self.statusText = RadioText("连接中…", "Connecting…")
                    self.detailText = self.connectionDescription(selected, attempt: sourceAttempt)
                    let address: StreamAddress
                    let isReusing = reuseAddress != nil
                    // Metadata can reload while resolution is pending; labels retain this source snapshot.
                    self.currentDeck.station = selected
                    self.currentDeck.sourceAttempt = sourceAttempt
                    if let existing = reuseAddress {
                        address = existing
                        reuseAddress = nil
                        trace.event("avplayer.reuse", "retain old audio and resume monitoring")
                    } else {
                        address = try await self.resolver.resolve(selected, attempt: sourceAttempt)
                    }
                    try Task.checkCancellation()
                    guard self.generation == id else { return }
                    trace.event("resolve.complete", "elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - attemptBegan) * 1000))")
                    self.diagnostics.stream(address.url, trace: trace)
                    self.diagnostics.state(trace, phase: "Buffering")
                    var sourceInfo: RadioText {
                        self.sourceDescription(selected, attempt: sourceAttempt)
                    }
                    self.statusText = RadioText("缓冲中…", "Buffering…")
                    let display = self.displayStation(selected)
                    self.detailText = RadioText("正在等待\(display.menuName.zh)直播数据", "Waiting for \(display.menuName.en) live data")
                    self.currentDeck.address = address
                    self.currentDeck.sourceAttempt = sourceAttempt
                    if !isReusing {
                        self.currentDeck.station = selected
                        self.player.load(address.url)
                        self.applyVolumes()
                        self.player.play()
                    }
                    trace.event("avplayer.load", "play requested; no-progress timeout=25s; automaticWaiting=true")
                    let connectedAt = self.playbackNow()
                    var lastPlayerObservation = ""
                    var lastProgress = connectedAt
                    var healthySince: Date?
                    var lastTime = self.player.state.time
                    if !lastTime.isFinite { lastTime = 0 }
                    var hasProgressed = isReusing
                    while !Task.isCancelled && self.generation == id {
                        try await Task.sleep(nanoseconds: self.pollNanoseconds)
                        guard self.generation == id else { return }
                        let snapshot = self.player.state
                        let waiting = snapshot.waiting ?? "none"
                        let knownWaiting = ["AVPlayerWaitingToMinimizeStallsReason", "AVPlayerWaitingWhileEvaluatingBufferingRateReason", "AVPlayerWaitingWithNoItemToPlayReason"]
                        let safeWaiting = waiting == "none" || knownWaiting.contains(waiting) ? waiting : "other"
                        let observation = "item=\(snapshot.itemStatus.rawValue); control=\(snapshot.control.rawValue); waiting=\(safeWaiting); empty=\(snapshot.bufferEmpty); likelyToKeepUp=\(snapshot.likelyToKeepUp)"
                        if observation != lastPlayerObservation {
                            trace.event("avplayer.state", observation)
                            lastPlayerObservation = observation
                        }
                        if snapshot.itemStatus == .failed {
                            self.player.recordErrors(trace: trace)
                            // Do not surface signed URLs / tokens in user-facing errors.
                            throw RadioError.playback
                        }
                        let time = snapshot.time
                        self.isPlaying = snapshot.isPlaying || (self.outgoingDeck?.audio.state.isPlaying ?? false)
                        if snapshot.isPlaying && time.isFinite && time > lastTime + 0.05 {
                            self.startCrossfadeIfNeeded()
                            hasProgressed = true
                            lastTime = time
                            lastProgress = self.playbackNow()
                            if healthySince == nil { healthySince = self.playbackNow() }
                            if let healthySince, self.playbackNow().timeIntervalSince(healthySince) > 60 {
                                let previousRetries = recovery.retryCount
                                recovery.recordHealthyPlayback()
                                if previousRetries > 0 {
                                    trace.event("retry.budgetReset", "healthy playback >60s")
                                    self.diagnostics.state(trace, phase: "Playing", retries: 0)
                                }
                            }
                            if self.statusText.en != "Playing" {
                                trace.event("avplayer.playing", "loadMs=\(Int(self.playbackNow().timeIntervalSince(connectedAt) * 1000)); attemptMs=\(Int((ProcessInfo.processInfo.systemUptime - attemptBegan) * 1000))")
                                self.diagnostics.state(trace, phase: "Playing", retries: recovery.retryCount)
                            }
                            self.statusText = RadioText("播放中", "Playing")
                            self.detailText = self.currentDeck.failureNote ?? sourceInfo
                        } else {
                            self.suspendCrossfade()
                            healthySince = nil
                            if self.statusText.en != "Buffering…" {
                                trace.event("avplayer.buffering")
                                self.diagnostics.state(trace, phase: "Buffering")
                            }
                            self.statusText = RadioText("缓冲中…", "Buffering…")
                            self.detailText = RadioText("正在等待直播数据", "Waiting for live stream data")
                        }
                        if self.playbackNow().timeIntervalSince(lastProgress) > 25 {
                            self.player.recordErrors(trace: trace)
                            trace.event("app.timeout", "noProgressMs=\(Int(self.playbackNow().timeIntervalSince(lastProgress) * 1000)); loadMs=\(Int(self.playbackNow().timeIntervalSince(connectedAt) * 1000)); everProgressed=\(hasProgressed)")
                            throw RadioError.timeout
                        }
                    }
                    try Task.checkCancellation()
                    return
                } catch {
                    guard !Task.isCancelled && self.generation == id else {
                        trace.event("attempt.cancelled", "late result ignored")
                        return
                    }
                    let safeError = RadioDiagnostics.error(error)
                    trace.event("attempt.failed", "elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - attemptBegan) * 1000)); \(safeError)")
                    self.diagnostics.state(trace, phase: "Failed", error: safeError)
                    self.suspendCrossfade()
                    self.player.clear()
                    self.isPlaying = self.outgoingDeck?.audio.state.isPlaying ?? false
                    guard let delay = recovery.retryAfterFailure() else {
                        trace.event("retry.exhausted", "budget=4")
                        self.diagnostics.state(trace, phase: "Error", retries: recovery.retryCount)
                        if self.restoreOutgoing(after: selected) { return }
                        self.outgoingDeck?.audio.clear()
                        self.outgoingDeck = nil
                        self.isPlaying = false
                        self.wantsPlayback = false
                        self.statusText = RadioText("连接失败", "Connection failed")
                        self.detailText = RadioText("\(error.radioDisplayText.zh)；点击播放可重新连接", "\(error.radioDisplayText.en). Click Play to reconnect")
                        return
                    }
                    trace.event("retry.scheduled", "retry=\(recovery.retryCount)/4; delaySeconds=\(delay)")
                    self.diagnostics.state(trace, phase: "Retrying", retries: recovery.retryCount)
                    self.statusText = RadioText("等待重试（\(recovery.retryCount)/4）", "Retrying (\(recovery.retryCount)/4)")
                    let rotating = selected.urls.count > 1
                    self.detailText = RadioText("\(error.radioDisplayText.zh) · \(delay) 秒后\(rotating ? "切换线路" : "重试连接")", "\(error.radioDisplayText.en) · \(rotating ? "Switch stream" : "Retry connection") in \(delay)s")
                    do { try await self.waitForRetry(delay) }
                    catch { return }
                    guard self.generation == id else { return }
                    self.statusText = RadioText("重新连接…", "Reconnecting…")
                }
            }
        }
    }

    deinit { fadeTicker?.invalidate() }
}
