import AppKit

/// AppKit refuses every quit (menu, Apple Event, our permission reopen) while a window shows a sheet,
/// before the delegate's shutdown steps run, and tells no one. SwiftUI ignores NSPrincipalClass, so
/// `terminate:` is swapped once at launch to end the sheets first.
extension NSApplication {
    private static let sheetWaitTries = 20
    /// The quit Apple Event, kept for its logout or shutdown reason while sheets close.
    static var pendingQuitEvent: NSAppleEventDescriptor?

    static func endSheetsBeforeQuit() {
        guard let original = class_getInstanceMethod(NSApplication.self, #selector(terminate(_:))),
              let replacement = class_getInstanceMethod(NSApplication.self, #selector(mptTerminate(_:)))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    /// AppKit's own quit Apple Event handler checks for sheets before `terminate:`, so it never reaches the swap.
    static func handleQuitAppleEvent() {
        NSAppleEventManager.shared().setEventHandler(
            QuitAppleEventHandler.shared, andSelector: #selector(QuitAppleEventHandler.handle(_:reply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    /// After the swap, calling `mptTerminate` runs AppKit's own terminate. `dynamic` keeps the call on objc_msgSend.
    @objc dynamic private func mptTerminate(_ sender: Any?) {
        guard hasSheets else { return mptTerminate(sender) }
        windows.forEach(Self.endSheets(on:))
        terminateWhenSheetsClose(sender, tries: Self.sheetWaitTries)
    }

    private var hasSheets: Bool { windows.contains { $0.attachedSheet != nil } }

    // A sheet stays attached until its close animation ends, and AppKit still refuses until then.
    private func terminateWhenSheetsClose(_ sender: Any?, tries: Int) {
        guard tries > 0, hasSheets else { return mptTerminate(sender) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            terminateWhenSheetsClose(sender, tries: tries - 1)
        }
    }

    static func endSheets(on window: NSWindow) {
        guard let sheet = window.attachedSheet else { return }
        endSheets(on: sheet)
        window.endSheet(sheet, returnCode: .cancel)
    }
}

@MainActor
final class QuitAppleEventHandler: NSObject {
    static let shared = QuitAppleEventHandler()

    @objc func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        NSApplication.pendingQuitEvent = event
        NSApp.terminate(nil)
    }
}
