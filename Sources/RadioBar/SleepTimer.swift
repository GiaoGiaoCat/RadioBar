import Foundation
import Combine
import AppKit

/// A one-shot countdown owned by the player, independent of any visible window.
@MainActor
final class SleepTimer: ObservableObject {
    static let durationKey = "sleepTimerMinutes"
    static let validMinutes = 1...720

    @Published var minutesInput: String {
        didSet {
            if let minutes = configuredMinutes { defaults.set(minutes, forKey: Self.durationKey) }
        }
    }
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var isRunning = false
    @Published private(set) var hasExpired = false
    @Published private(set) var isFadingOut = false

    // Playback owns this phase; starting/cancelling a countdown never cancels audio fading.
    func setFadingOut(_ active: Bool) { isFadingOut = active }
    private var deadline: ContinuousClock.Instant?
    private var ticker: Timer?
    private var wakeSubscription: AnyCancellable?
    private let defaults: UserDefaults
    private let now: () -> ContinuousClock.Instant
    private let onExpire: () -> Void

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now },
         onExpire: @escaping () -> Void) {
        self.defaults = defaults
        self.now = now
        self.onExpire = onExpire
        let saved = defaults.integer(forKey: Self.durationKey)
        minutesInput = String(Self.validMinutes.contains(saved) ? saved : 30)
        wakeSubscription = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    var configuredMinutes: Int? {
        guard let value = Int(minutesInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              Self.validMinutes.contains(value) else { return nil }
        return value
    }
    var remainingText: String {
        let seconds = max(0, remainingSeconds)
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    @discardableResult
    func start() -> Bool {
        guard let minutes = configuredMinutes else { return false }
        ticker?.invalidate()
        remainingSeconds = minutes * 60
        deadline = now().advanced(by: .seconds(remainingSeconds))
        hasExpired = false
        isRunning = true
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            // This timer is registered exclusively on the main run loop below.
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.ticker = ticker
        RunLoop.main.add(ticker, forMode: .common)
        return true
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        remainingSeconds = 0
        isRunning = false
        hasExpired = false
    }

    func refresh() {
        guard let deadline else { return }
        let remaining = now().duration(to: deadline)
        if remaining <= .zero {
            // Clear first: queued ticks, wake events and reentrant callbacks cannot fire twice.
            cancel()
            hasExpired = true
            onExpire()
        } else {
            let parts = remaining.components
            remainingSeconds = Int(parts.seconds) + (parts.attoseconds > 0 ? 1 : 0)
        }
    }

    deinit { ticker?.invalidate() }
}
