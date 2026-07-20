import SwiftUI
import AppKit

// NSHostingView triggers NSPerformVisuallyAtomicChange re-entrantly by calling
// invalidateIntrinsicContentSize() during SwiftUI layout passes, which AppKit
// responds to by crashing. Overriding both properties breaks that chain: the
// window frame determines the view's size; SwiftUI lays out inside it freely.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder)  { super.init(coder: coder) }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    override func invalidateIntrinsicContentSize() { /* intentionally empty */ }
}

class IslandWindow: NSPanel {
    init(contentView: AnyView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isOpaque = false

        self.contentView = IslandHostingView(rootView: contentView)
    }

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}
