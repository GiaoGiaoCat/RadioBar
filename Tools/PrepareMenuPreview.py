"""Copy the production menu views and helpers for isolated offscreen rendering."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/RadioBar/RadioBarApp.swift').read_text()
start = source.index('/// A stable scene child')
views = source[start:]
views = views.replace('private struct RadioMenuView:', 'struct CapturedMenuView:')
views = views.replace('private struct RadioMenuBarLabel:', 'struct CapturedMenuBarLabel:')
# Measure both content edges without adding layout constraints in the preview.
views = views.replace('Text("RadioBar")', 'Text("RadioBar").background(MenuBoundsProbe(name: "menuHeaderProbe")).background(MenuColorSchemeProbe().allowsHitTesting(false))')
views = views.replace('.keyboardShortcut("q")', '.keyboardShortcut("q").background(MenuBoundsProbe(name: "menuBottomProbe"))')
views = views.replace('.buttonStyle(.plain)\n        .onHover', '.buttonStyle(.plain)\n        .background(MenuBoundsProbe(name: "menuRow:" + title).allowsHitTesting(false))\n        .onHover')
views = views.replace('.accessibilityIdentifier("muteButton")', '.accessibilityIdentifier("muteButton").background(MenuBoundsProbe(name: "menuMuteProbe").allowsHitTesting(false))')
views = views.replace('.controlSize(.small).accessibilityLabel(settings.text("音量", "Volume"))', '.controlSize(.small).accessibilityLabel(settings.text("音量", "Volume")).background(MenuBoundsProbe(name: "menuSliderProbe").allowsHitTesting(false))')
hover_property = '@MenuState private var hovered = false'
assert views.count(hover_property) == 1
views = views.replace(hover_property, hover_property + '''
    init(title: String, symbol: String?, shortcut: String? = nil, trailingText: String? = nil, isFrequency: Bool = false,
         previewHovered: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.trailingText = trailingText
        self.isFrequency = isFrequency
        self.action = action
        self._hovered = MenuState(initialValue: previewHovered)
    }
''')
# Fixtures can set existing values in this test-only copy.
player = (root / 'Sources/RadioBar/RadioPlayer.swift').read_text()
Path(sys.argv[1]).with_name('PreviewRadioPlayer.swift').write_text(player.replace('@Published private(set)', '@Published'))
preview = 'import SwiftUI\nimport AppKit\n' + views
preview += '\nprivate typealias NativeCapturedMenuView = CapturedMenuView\n'
if '--native-tests' in sys.argv:
    preview += '\n' + (root / 'Tests/NativeMenuTests.swift').read_text()
else:
    preview += '\n' + (root / 'Tools/MenuSurfacePreview.swift').read_text()
    preview += '\n' + (root / 'Tools/RenderMenu.swift').read_text()
Path(sys.argv[1]).write_text(preview)
