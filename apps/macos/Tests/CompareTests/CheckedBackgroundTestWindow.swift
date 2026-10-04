import AppKit
import Testing

@MainActor class CheckedBackgroundTestWindow: BackgroundTestWindow {
    override func blockedPresentation() {
        super.blockedPresentation()
        Issue.record("Native unit tests must not present or focus windows")
    }
}
