import AppKit
import Combine

/// Three cached template images share exactly the same antenna and canvas.
@MainActor
enum MenuBarAntenna {
    static let size = NSSize(width: 18, height: 18)
    static let frames: [NSImage] = (0...2).map { rings in
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let mast = NSBezierPath()
            mast.lineWidth = 1.4
            mast.lineCapStyle = .round
            mast.move(to: NSPoint(x: 9, y: 2.5))
            mast.line(to: NSPoint(x: 9, y: 8.5))
            mast.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.7, y: 8.7, width: 2.6, height: 2.6)).fill()
            for ring in 0..<rings {
                let radius = CGFloat(4 + ring * 3)
                for angles in [(CGFloat(-42), CGFloat(42)), (CGFloat(138), CGFloat(222))] {
                    let wave = NSBezierPath()
                    wave.lineWidth = 1.3
                    wave.lineCapStyle = .round
                    wave.appendArc(withCenter: NSPoint(x: 9, y: 10), radius: radius,
                                   startAngle: angles.0, endAngle: angles.1)
                    wave.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "RadioBar"
        return image
    }
}

/// Drives real image replacement, rather than a symbol effect inside the menu bar host.
@MainActor
final class MenuBarSignal: ObservableObject {
    @Published private(set) var frameIndex = 2
    var image: NSImage { MenuBarAntenna.frames[frameIndex] }
    var isAnimating: Bool { timer != nil }
    static let frameInterval: TimeInterval = 0.8
    private var animationEnabled = false
    private var playing = false
    private var reducedMotion: Bool
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    init(radio: RadioPlayer, settings: AppSettings, workspace: NSWorkspace = .shared) {
        reducedMotion = workspace.accessibilityDisplayShouldReduceMotion
        animationEnabled = settings.animateMenuBarIcon
        frameIndex = animationEnabled ? 0 : 2
        settings.$animateMenuBarIcon.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.setAnimationEnabled(enabled) }
            .store(in: &subscriptions)
        radio.$isPlaying.combineLatest(radio.$wantsPlayback, radio.$statusText)
            .map { $0 && $1 && $2.en == "Playing" }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in self?.setPlaying(playing) }
            .store(in: &subscriptions)
        workspace.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setReducedMotion(workspace.accessibilityDisplayShouldReduceMotion)
            }
            .store(in: &subscriptions)
    }

    // An isolated state driver also makes the real timer testable without audio/network.
    init(reducedMotion: Bool, animationEnabled: Bool = false) {
        self.reducedMotion = reducedMotion
        self.animationEnabled = animationEnabled
        frameIndex = animationEnabled ? 0 : 2
    }

    func setAnimationEnabled(_ value: Bool) {
        guard animationEnabled != value else { return }
        animationEnabled = value
        updateAnimation()
    }

    func setPlaying(_ value: Bool) {
        guard playing != value else { return }
        playing = value
        updateAnimation()
    }

    func setReducedMotion(_ value: Bool) {
        guard reducedMotion != value else { return }
        reducedMotion = value
        updateAnimation()
    }

    private func updateAnimation() {
        timer?.invalidate()
        timer = nil
        frameIndex = !animationEnabled || (playing && reducedMotion) ? 2 : 0
        guard animationEnabled && playing && !reducedMotion else { return }
        let ticker = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frameIndex = (self.frameIndex + 1) % MenuBarAntenna.frames.count
            }
        }
        ticker.tolerance = 0.08
        timer = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }

    deinit { timer?.invalidate() }
}

/// Shared native title layout for the status item and settings preview.
@MainActor
enum MenuBarTitle {
    static let stationWidth: CGFloat = 140
    static let clockFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    static let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    static func text(stationName: String?, countdown: String?) -> String {
        let name = stationName.map { countdown == nil ? $0 : abbreviated($0) }
        let parts = [name, countdown].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "" : "\u{2002}" + parts.joined(separator: " · ")
    }

    // MenuBarExtra extracts a plain title and drops Text.monospacedDigit().
    // Draw the counting label as one template image so native tinting remains,
    // while glyph advances and the clock's left edge are under our control.
    static func image(antenna: NSImage, stationName: String?, countdown: String) -> NSImage {
        let name = stationName.map(abbreviated).flatMap { $0.isEmpty ? nil : $0 }
        let prefix = "\u{2002}" + (name.map { $0 + " · " } ?? "")
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.black]
        let clockAttributes: [NSAttributedString.Key: Any] = [.font: clockFont, .foregroundColor: NSColor.black]
        let prefixWidth = (prefix as NSString).size(withAttributes: titleAttributes).width
        // Equal digit advances keep seconds stable. Size to the visible format
        // instead of reserving invisible hour digits at the right edge.
        let clockWidth = (countdown as NSString).size(withAttributes: clockAttributes).width
        let clockX = MenuBarAntenna.size.width + prefixWidth
        let height = MenuBarAntenna.size.height
        let image = NSImage(size: NSSize(width: ceil(clockX + clockWidth), height: height), flipped: false) { _ in
            antenna.draw(in: NSRect(origin: .zero, size: MenuBarAntenna.size))
            let lineHeight = titleFont.ascender - titleFont.descender
            let y = (height - lineHeight) / 2
            (prefix as NSString).draw(at: NSPoint(x: MenuBarAntenna.size.width, y: y), withAttributes: titleAttributes)
            (countdown as NSString).draw(at: NSPoint(x: clockX, y: y), withAttributes: clockAttributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = [stationName, countdown].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return image
    }

    static func abbreviated(_ name: String) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: attributes).width }
        guard width(name) > stationWidth else { return name }
        var prefix = ""
        for character in name {
            let candidate = prefix + String(character)
            guard width(candidate + "…") <= stationWidth else { break }
            prefix = candidate
        }
        return prefix + "…"
    }
}
