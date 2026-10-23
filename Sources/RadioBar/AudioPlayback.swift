import Foundation
import AVFoundation

struct AudioPlaybackState {
    var itemStatus: AVPlayerItem.Status = .unknown
    var control: AVPlayer.TimeControlStatus = .paused
    var time: Double = 0
    var waiting: String? = nil
    var bufferEmpty = true
    var likelyToKeepUp = false

    var isPlaying: Bool { itemStatus == .readyToPlay && control == .playing }
}

/// The same transport contract is exercised by deterministic, silent test decks.
@MainActor
protocol AudioPlayback: AnyObject {
    var volume: Float { get set }
    var state: AudioPlaybackState { get }
    func load(_ url: URL)
    func play()
    func pause()
    func clear()
    func recordErrors(trace: DiagnosticTrace)
}

@MainActor
final class NativeAudioPlayback: AudioPlayback {
    private let player = AVPlayer()

    init() { player.automaticallyWaitsToMinimizeStalling = true }
    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    var state: AudioPlaybackState {
        AudioPlaybackState(itemStatus: player.currentItem?.status ?? .unknown,
                           control: player.timeControlStatus,
                           time: player.currentTime().seconds,
                           waiting: player.reasonForWaitingToPlay?.rawValue,
                           bufferEmpty: player.currentItem?.isPlaybackBufferEmpty ?? true,
                           likelyToKeepUp: player.currentItem?.isPlaybackLikelyToKeepUp ?? false)
    }
    func load(_ url: URL) { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
    func play() { player.play() }
    func pause() { player.pause() }
    func clear() {
        player.volume = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
    func recordErrors(trace: DiagnosticTrace) {
        if let underlying = player.currentItem?.error ?? player.error {
            trace.event("avplayer.error", RadioDiagnostics.error(underlying))
        }
        for event in player.currentItem?.errorLog()?.events.suffix(3) ?? [] {
            let knownDomains = ["CoreMediaErrorDomain", "NSURLErrorDomain", "AVFoundationErrorDomain"]
            trace.event("avplayer.errorLog", "statusCode=\(event.errorStatusCode); domain=\(knownDomains.contains(event.errorDomain) ? event.errorDomain : "OtherErrorDomain")")
        }
        if let event = player.currentItem?.accessLog()?.events.last {
            trace.event("avplayer.accessSummary", "stalls=\(event.numberOfStalls); mediaRequests=\(event.numberOfMediaRequests)")
        }
    }
}
