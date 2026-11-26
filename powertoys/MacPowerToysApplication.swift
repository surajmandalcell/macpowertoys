import AppKit

/// AppKit refuses every quit (menu, Apple Event, our permission reopen) while a window shows a sheet,
/// before the delegate's shutdown steps run, and tells no one. Ending the sheets first lets quit go on.
@objc(MacPowerToysApplication)
final class MacPowerToysApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        windows.forEach(Self.endSheets(on:))
        super.terminate(sender)
    }

    static func endSheets(on window: NSWindow) {
        guard let sheet = window.attachedSheet else { return }
        endSheets(on: sheet)
        window.endSheet(sheet, returnCode: .cancel)
    }
}
