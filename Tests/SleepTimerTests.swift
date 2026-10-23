import Foundation
import AppKit

@MainActor
private final class PendingSleepResolver: StreamURLResolving {
    var requests: [Station: CheckedContinuation<StreamAddress, Error>] = [:]
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        try await withCheckedThrowingContinuation { requests[station] = $0 }
    }
    func finish(_ station: Station) {
        requests.removeValue(forKey: station)?.resume(returning: StreamAddress(
            url: URL(string: "https://fixture.invalid/live.m3u8")!))
    }
}

@main
struct SleepTimerTests {
    @MainActor static func main() async {
        timerChecks()
        frequencyChecks()
        await playerChecks()
    }

    @MainActor private static func timerChecks() {
        let suite = "RadioBar.SleepTimerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var instant = ContinuousClock().now
        var expirations = 0
        let timer = SleepTimer(defaults: defaults, now: { instant }) { expirations += 1 }
        precondition(timer.minutesInput == "30" && !timer.isRunning)
        for invalid in ["", "0", "-1", "721", "1.5", "abc", "999999999999999999999999"] {
            timer.minutesInput = invalid
            precondition(!timer.start() && !timer.isRunning && expirations == 0)
        }
        timer.minutesInput = " 1 "
        precondition(timer.start() && timer.remainingSeconds == 60 && timer.remainingText == "01:00")
        timer.minutesInput = "2" // Editing the next duration cannot reset the active timer.
        instant = instant.advanced(by: .milliseconds(59_100))
        timer.refresh()
        precondition(timer.isRunning && timer.remainingSeconds == 1 && expirations == 0)
        instant = instant.advanced(by: .milliseconds(900))
        timer.refresh()
        timer.refresh()
        precondition(!timer.isRunning && timer.hasExpired && timer.remainingSeconds == 0 && expirations == 1)
        print("PASS: countdown validates minutes, rounds up and expires exactly once; editing input preserves the active deadline")

        timer.minutesInput = "2"
        timer.start()
        instant = instant.advanced(by: .seconds(30))
        timer.refresh()
        precondition(timer.remainingSeconds == 90)
        timer.minutesInput = "1"
        timer.start()
        instant = instant.advanced(by: .seconds(31))
        timer.refresh()
        precondition(timer.remainingSeconds == 29 && expirations == 1)
        timer.cancel()
        instant = instant.advanced(by: .seconds(3600))
        timer.refresh()
        precondition(!timer.isRunning && !timer.hasExpired && expirations == 1)
        timer.start()
        instant = instant.advanced(by: .seconds(10_800)) // Missed ticks, such as during system sleep.
        timer.refresh()
        timer.refresh()
        precondition(expirations == 2 && !timer.isRunning)
        print("PASS: restart replaces the old countdown, cancellation prevents expiry, and elapsed time is honored after missed ticks")

        timer.minutesInput = "120"
        timer.start()
        precondition(timer.remainingText == "2:00:00")
        instant = instant.advanced(by: .seconds(3601))
        timer.refresh()
        precondition(timer.remainingText == "59:59")
        let restored = SleepTimer(defaults: defaults, now: { instant }) {}
        precondition(restored.minutesInput == "120" && !restored.isRunning && restored.remainingSeconds == 0)
        timer.cancel()
        timer.minutesInput = "1"
        timer.start()
        instant = instant.advanced(by: .seconds(61))
        // Exercise the real run-loop ticker with no menu, settings view or manual refresh.
        RunLoop.main.run(until: Date().addingTimeInterval(1.15))
        precondition(expirations == 3 && !timer.isRunning)
        print("PASS: duration preference persists without restoring an active timer; real ticker fires without any visible UI")
    }

    @MainActor private static func frequencyChecks() {
        let expected: [Station: String] = [.kiss: "FM 99.9", .bcc: "FM 96.3", .ufo: "FM 92.1",
                                           .guangdong: "FM 99.3", .musicRadio: "FM 90.0", .shanghai: "FM 101.7", .loveRadio: "FM 103.7", .classic947: "FM 94.7", .asiaFM: "", .radioParadise: "", .grooveSalad: "", .swissJazz: ""]
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        for station in Station.allCases {
            precondition(station.frequencyLabel == expected[station])
            for language in [AppLanguage.chinese, .english] {
                let title = station.menuName.value(language)
                if station.frequencyMHz != nil {
                    precondition(!title.contains("FM ") && station.displayName.value(language).hasSuffix(station.frequencyLabel))
                } else {
                    precondition(station.displayName.value(language) == title)
                }
                precondition((title as NSString).size(withAttributes: attributes).width <= (station.frequencyMHz == nil ? 203 : 136))
            }
        }
        let frequencyAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)]
        precondition((Station.shanghai.frequencyLabel as NSString).size(withAttributes: frequencyAttributes).width <= 64)
        precondition((Station.loveRadio.frequencyLabel as NSString).size(withAttributes: frequencyAttributes).width <= 64)
        precondition((Station.classic947.frequencyLabel as NSString).size(withAttributes: frequencyAttributes).width <= 64)
        print("PASS: eight spaced FM labels plus four internet-only names, bilingual titles fit the available menu width, and full station names retain frequencies")
    }

    @MainActor private static func waitFor(_ station: Station, in resolver: PendingSleepResolver) async {
        for _ in 0..<100 {
            if resolver.requests[station] != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Expected a pending station request")
    }

    @MainActor private static func playerChecks() async {
        let suite = "RadioBar.SleepPlayerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var instant = ContinuousClock().now
        let resolver = PendingSleepResolver()
        let radio = RadioPlayer(resolver: resolver, defaults: defaults, sleepClockNow: { instant })
        let timer = radio.sleepTimer
        timer.minutesInput = "1"
        timer.start()
        precondition(!radio.wantsPlayback && resolver.requests.isEmpty)
        radio.select(.musicRadio)
        await waitFor(.musicRadio, in: resolver)
        instant = instant.advanced(by: .seconds(10))
        radio.select(.bcc)
        await waitFor(.bcc, in: resolver)
        timer.refresh()
        precondition(timer.remainingSeconds == 50 && radio.wantsPlayback)
        let volume = radio.volume
        instant = instant.advanced(by: .seconds(51))
        timer.refresh()
        precondition(!radio.wantsPlayback && !radio.isPlaying && radio.station == .bcc && radio.volume == volume)
        precondition(radio.statusText.en == "Sleep timer ended")
        resolver.finish(.musicRadio)
        resolver.finish(.bcc)
        try? await Task.sleep(nanoseconds: 50_000_000)
        precondition(!radio.wantsPlayback && !radio.isPlaying && radio.statusText.en == "Sleep timer ended")
        print("PASS: starting a timer does not start music; switching stations preserves countdown; expiry cancels playback and ignores late requests")

        timer.start()
        radio.play()
        await waitFor(.bcc, in: resolver)
        timer.cancel()
        precondition(radio.wantsPlayback) // Cancel timer alone must not pause music.
        radio.pause()
        resolver.finish(.bcc)
        timer.start()
        instant = instant.advanced(by: .seconds(30))
        radio.pause()
        timer.refresh()
        precondition(timer.isRunning && timer.remainingSeconds == 30)
        timer.cancel()
        precondition(!radio.wantsPlayback)
        print("PASS: cancelling a timer leaves playback alone; manual pause does not reset the countdown")
    }
}
