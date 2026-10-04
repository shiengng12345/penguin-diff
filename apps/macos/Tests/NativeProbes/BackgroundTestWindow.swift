import AppKit

@MainActor class BackgroundTestWindow: NSWindow {
    static var presentationAttempts = 0
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isReleasedWhenClosed = false; animationBehavior = .none
    }
    // NSApplication drops mouse events for ordered-out windows. This owned
    // test surface is transparent before ordering below all normal windows,
    // refuses focus, and is excluded from real mouse hit testing.
    func prepareForNativeEventDispatch() {
        alphaValue = 0; ignoresMouseEvents = true
        super.order(.below, relativeTo: 0)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func blockedPresentation() { Self.presentationAttempts += 1 }
    override func orderFront(_ sender: Any?) { blockedPresentation() }
    override func makeKeyAndOrderFront(_ sender: Any?) { blockedPresentation() }
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        if place == .out { super.order(place, relativeTo: otherWin) }
        else { blockedPresentation() }
    }
}
