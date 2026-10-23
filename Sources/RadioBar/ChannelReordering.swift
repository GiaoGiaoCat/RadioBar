import SwiftUI
import AppKit
import Combine

/// A local drag only previews a destination. Preferences change once, on a valid drop.
@MainActor
final class ChannelReorderSession: ObservableObject {
    static let pasteboardType = "local.victor.RadioBar.station-order"
    struct Target: Equatable {
        let station: Station
        let after: Bool
    }
    @Published private(set) var source: Station?
    @Published private(set) var target: Target?
    weak var activitySettings: AppSettings?

    func begin(_ station: Station) { source = station; target = nil; activitySettings?.setStationReordering(true) }
    @discardableResult
    func hover(_ station: Station, after: Bool) -> Bool {
        guard let source, source != station else { target = nil; return false }
        let next = Target(station: station, after: after)
        if target != next { target = next }
        return true
    }
    func leave(_ station: Station) {
        if target?.station == station { target = nil }
    }
    @discardableResult
    func commit(settings: AppSettings) -> Bool {
        guard !settings.stationChangesBlocked, let source, let target else { cancel(); return false }
        settings.moveStation(source, relativeTo: target.station, after: target.after)
        cancel()
        return true
    }
    func cancel() { source = nil; target = nil; activitySettings?.setStationReordering(false) }
}

/// Both ends use AppKit's exact pasteboard type. No UTI-to-NSItemProvider bridge.
@MainActor
struct ChannelDropRow<Content: View>: NSViewRepresentable {
    let station: Station
    let session: ChannelReorderSession
    let settings: AppSettings
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    func makeNSView(context: Context) -> ChannelDropDestinationView { ChannelDropDestinationView() }
    func updateNSView(_ view: ChannelDropDestinationView, context: Context) {
        view.station = station
        view.reorderSession = session
        view.settings = settings
        view.host.rootView = AnyView(content.environment(\.colorScheme, colorScheme)
                                        .environment(\.controlActiveState, controlActiveState))
    }
}

@MainActor
final class ChannelDropDestinationView: NSView {
    var station: Station = .kiss
    var reorderSession: ChannelReorderSession?
    var settings: AppSettings?
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    // Injectable only to exercise native callbacks where the test host cannot access pboard.
    var readStationID: (NSDraggingInfo) -> String? = { sender in
        sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(ChannelReorderSession.pasteboardType))
    }
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSPasteboard.PasteboardType(ChannelReorderSession.pasteboardType)])
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); host.frame = bounds }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let session = reorderSession, let source = session.source,
              let handle = sender.draggingSource as? ChannelDragHandle.HandleView,
              handle.reorderSession === session, handle.station == source,
              source != station, let settings, !settings.stationChangesBlocked,
              sender.draggingSourceOperationMask.contains(.move) else { return false }
        return readStationID(sender) == source.id
    }
    @discardableResult private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender), let session = reorderSession else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        guard bounds.contains(point) else { session.leave(station); return [] }
        return session.hover(station, after: point.y >= bounds.midY) ? .move : []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { reorderSession?.leave(station) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { update(sender) == .move }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard update(sender) == .move, let session = reorderSession, let settings else { return false }
        return session.commit(settings: settings)
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
}

/// NSDraggingSource provides a reliable end callback for Escape, external drops,
/// and cancelled drags; SwiftUI's onDrag alone has no matching cancellation hook.
@MainActor
struct ChannelDragHandle: NSViewRepresentable {
    let station: Station
    let title: String
    let help: String
    let session: ChannelReorderSession
    var isEnabled = true
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.station = station
        view.title = title
        view.toolTip = help
        view.reorderSession = session
        view.isEnabled = isEnabled
        view.setAccessibilityLabel(help + ": " + title)
        view.setAccessibilityIdentifier("stationReorder-" + station.id)
    }

    final class HandleView: NSView, NSDraggingSource {
        var station: Station = .kiss
        var title = ""
        var reorderSession: ChannelReorderSession?
        var isEnabled = true
        private var mouseDownEvent: NSEvent?
        // Settings allows background window dragging. A handle must retain the
        // mouse-down so AppKit delivers mouseDragged to this station source.
        override var mouseDownCanMoveWindow: Bool { false }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.tertiaryLabelColor.setStroke()
            let lines = NSBezierPath()
            lines.lineWidth = 0.75
            lines.lineCapStyle = .round
            for offset: CGFloat in [-2.5, 0, 2.5] {
                lines.move(to: NSPoint(x: bounds.midX - 4.5, y: bounds.midY + offset))
                lines.line(to: NSPoint(x: bounds.midX + 4.5, y: bounds.midY + offset))
            }
            lines.stroke()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) { mouseDownEvent = isEnabled ? event : nil }
        override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }
        static func pasteboardItem(for station: Station) -> NSPasteboardItem {
            let item = NSPasteboardItem()
            item.setString(station.id, forType: NSPasteboard.PasteboardType(ChannelReorderSession.pasteboardType))
            return item
        }
        override func mouseDragged(with event: NSEvent) {
            guard isEnabled, let initial = mouseDownEvent, let reorderSession else { return }
            let dx = event.locationInWindow.x - initial.locationInWindow.x
            let dy = event.locationInWindow.y - initial.locationInWindow.y
            guard hypot(dx, dy) >= 3 else { return }
            mouseDownEvent = nil
            let item = NSDraggingItem(pasteboardWriter: Self.pasteboardItem(for: station))
            let title = self.title
            let image = NSImage(size: NSSize(width: 224, height: 38), flipped: false) { rect in
                NSColor.controlBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
                (title as NSString).draw(at: NSPoint(x: 14, y: 11), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor
                ])
                return true
            }
            item.setDraggingFrame(NSRect(x: 0, y: -5, width: 224, height: 38), contents: image)
            reorderSession.begin(station)
            let drag = beginDraggingSession(with: [item], event: event, source: self)
            drag.animatesToStartingPositionsOnCancelOrFail = true
            drag.draggingFormation = .none
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            reorderSession?.cancel()
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    }
}

