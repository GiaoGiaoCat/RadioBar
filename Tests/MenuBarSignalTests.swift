import AppKit
import Combine

@main
struct MenuBarSignalTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let staticSignal = MenuBarSignal(reducedMotion: false)
        precondition(staticSignal.frameIndex == 2 && !staticSignal.isAnimating)
        staticSignal.setPlaying(true)
        precondition(staticSignal.frameIndex == 2 && !staticSignal.isAnimating)
        staticSignal.setPlaying(false)
        precondition(staticSignal.frameIndex == 2 && !staticSignal.isAnimating)
        let signal = MenuBarSignal(reducedMotion: false, animationEnabled: true)
        precondition(signal.frameIndex == 0 && !signal.isAnimating)
        let images = MenuBarAntenna.frames
        precondition(images.count == 3 && images.allSatisfy { $0.size == NSSize(width: 18, height: 18) && $0.isTemplate })
        precondition(Set(images.map { $0.tiffRepresentation! }).count == 3)
        var frames: [Int] = []
        let observation = signal.$frameIndex.sink { frames.append($0) }
        signal.setPlaying(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.55))
        precondition(signal.frameIndex == 0, "The first frame must not advance at the old 0.4 second speed")
        let deadline = Date().addingTimeInterval(4.0)
        while frames.count < 6 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(Array(frames.prefix(6)) == [0, 0, 1, 2, 0, 1], "Real runloop must cycle 0/1/2")
        signal.setPlaying(false)
        precondition(signal.frameIndex == 0 && !signal.isAnimating)
        let stoppedCount = frames.count
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        precondition(frames.count == stoppedCount)
        signal.setReducedMotion(true)
        signal.setPlaying(true)
        precondition(signal.frameIndex == 2 && !signal.isAnimating)
        signal.setPlaying(false)
        precondition(signal.frameIndex == 0 && !signal.isAnimating)
        signal.setPlaying(true)
        signal.setReducedMotion(false)
        precondition(signal.frameIndex == 0 && signal.isAnimating)
        signal.setReducedMotion(true)
        precondition(signal.frameIndex == 2 && !signal.isAnimating)
        signal.setReducedMotion(false)
        signal.setAnimationEnabled(false)
        precondition(signal.frameIndex == 2 && !signal.isAnimating)
        let disabledCount = frames.count
        RunLoop.current.run(until: Date().addingTimeInterval(0.95))
        precondition(frames.count == disabledCount)
        signal.setAnimationEnabled(true)
        precondition(signal.frameIndex == 0 && signal.isAnimating)
        signal.setPlaying(false)
        observation.cancel()
        let suite = "RadioBar.SignalBindingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppSettings(defaults: defaults)
        let player = RadioPlayer(defaults: defaults)
        let bound = MenuBarSignal(radio: player, settings: preferences)
        precondition(bound.frameIndex == 2 && !bound.isAnimating)
        preferences.animateMenuBarIcon = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(bound.frameIndex == 0 && !bound.isAnimating)
        preferences.animateMenuBarIcon = false
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(bound.frameIndex == 2 && !bound.isAnimating)
        precondition(MenuBarTitle.text(stationName: nil, countdown: nil).isEmpty)
        precondition(MenuBarTitle.text(stationName: "广东音乐之声", countdown: nil) == "\u{2002}广东音乐之声")
        let attrs: [NSAttributedString.Key: Any] = [.font: MenuBarTitle.clockFont]
        let digitWidths = (0...9).map { (String($0) as NSString).size(withAttributes: attrs).width }
        precondition(digitWidths.max()! - digitWidths.min()! < 0.01)
        let clockGroups = [["10:44", "10:41", "09:59", "59:59"], ["1:29:42", "1:29:41", "1:00:00"], ["12:00:00", "11:59:59"]]
        for name in [String?.none, "Music", "SomaFM Groove Salad"] {
            var previousWidth: CGFloat = 0
            for clocks in clockGroups {
                let images = clocks.map { MenuBarTitle.image(antenna: MenuBarAntenna.frames[2], stationName: name, countdown: $0) }
                precondition(images.allSatisfy { $0.isTemplate && $0.size == images[0].size })
                precondition(images[0].size.width > previousWidth, "Only visible hour digits may add width")
                previousWidth = images[0].size.width
                for image in images {
                    // Inspect the rendered alpha, so a fixed canvas with invisible
                    // hour slots cannot pass just by keeping its total width stable.
                    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                    let scale = CGFloat(bitmap.pixelsWide) / image.size.width
                    let inkRight = stride(from: bitmap.pixelsWide - 1, through: 0, by: -1).first { x in
                        (0..<bitmap.pixelsHigh).contains { y in bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.1 }
                    }!
                    let trailingBlank = CGFloat(bitmap.pixelsWide - 1 - inkRight) / scale
                    precondition(trailingBlank <= 3, "Countdown image must end next to its last digit, got \(trailingBlank) pt")
                }
            }
        }
        precondition(MenuBarTitle.text(stationName: "Music", countdown: "10:44") == "\u{2002}Music · 10:44")
        precondition(MenuBarTitle.text(stationName: nil, countdown: "10:44") == "\u{2002}10:44")
        let longName = String(repeating: "长电台名称 Station ", count: 15)
        let shortened = MenuBarTitle.abbreviated(longName)
        precondition(shortened.hasSuffix("…"))
        precondition(MenuBarTitle.image(antenna: images[2], stationName: longName, countdown: "29:58")
            .accessibilityDescription == longName + " · 29:58")
        precondition((shortened as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width <= MenuBarTitle.stationWidth)
        precondition(MenuBarTitle.text(stationName: longName, countdown: "29:58").hasSuffix("29:58"))
        precondition(MenuBarTitle.text(stationName: nil, countdown: "29:58").contains("29:58"))
        print("PASS: independent station/countdown titles, long names truncate without losing time, and native template clock stays stable within each format and has no reserved hour slots on the right")
        print("PASS: static two-ring default; real slower 0.8s cycle; setting changes apply immediately and stop timer; reduce-motion and pause behavior")
    }
}
