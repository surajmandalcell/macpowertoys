import AppKit
import os

private let quitLog = Logger(subsystem: "com.surajmandal.macpowertoys", category: "quit")

/// AppKit refuses every quit (menu, Apple Event, our permission reopen) while a window shows a sheet,
/// before the delegate's shutdown steps run, and tells no one. SwiftUI ignores NSPrincipalClass, so
/// `terminate:` is swapped once at launch to end the sheets first.
extension NSApplication {
    private static let sheetWaitTries = 20
    /// The quit Apple Event, kept for its logout or shutdown reason while sheets close.
    static var pendingQuitEvent: NSAppleEventDescriptor?

    /// Swaps on the live class: SwiftUI's `AppKitApplication` overrides `terminate:`, so a swap on NSApplication never runs.
    static func endSheetsBeforeQuit() {
        guard let app = NSApp, let appClass = object_getClass(app),
              let original = class_getInstanceMethod(appClass, #selector(terminate(_:))),
              let replacement = class_getInstanceMethod(appClass, #selector(mptTerminate(_:)))
        else { return }
        if class_addMethod(appClass, #selector(terminate(_:)), method_getImplementation(replacement),
                           method_getTypeEncoding(replacement)) {
            class_replaceMethod(appClass, #selector(mptTerminate(_:)), method_getImplementation(original),
                                method_getTypeEncoding(original))
        } else {
            method_exchangeImplementations(original, replacement)
        }
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
        quitLog.notice("quit: ending open sheets first")
        windows.forEach(Self.endSheets(on:))
        terminateWhenSheetsClose(sender, tries: Self.sheetWaitTries)
    }

    // `endSheet` detaches at once, but the sheet window stays visible while it animates out and AppKit still refuses.
    private var hasSheets: Bool { windows.contains { $0.attachedSheet != nil || ($0.isSheet && $0.isVisible) } }

    private func terminateWhenSheetsClose(_ sender: Any?, tries: Int) {
        guard tries > 0, hasSheets else {
            if tries == 0 { quitLog.error("quit: a sheet still shows after 2 s") }
            return mptTerminate(sender)
        }
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
