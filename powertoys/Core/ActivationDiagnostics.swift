import AppKit

// Records why the app became active, so a focus change during background checks names its cause.
@MainActor
enum ActivationDiagnostics {
    private static let maximumBytes = 256 * 1024
    private static var lastURL = ""
    private static var lastURLTime = Date.distantPast
    private static var observer: NSObjectProtocol?

    private static var fileURL: URL {
        AppDataLocation.directory
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("activations.log")
    }

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { record() }
        }
    }

    static func noteURL(_ url: URL) {
        lastURL = url.absoluteString
        lastURLTime = Date()
    }

    private static func record() {
        let event = NSApp.currentEvent
        let eventText = event.map { "type=\($0.type.rawValue) window=\($0.window?.identifier?.rawValue ?? "-")" } ?? "none"
        let key = NSApp.keyWindow?.identifier?.rawValue ?? "-"
        let sinceURL = String(format: "%.2f", Date().timeIntervalSince(lastURLTime))
        let line = "\(Date().timeIntervalSince1970) event[\(eventText)] key=\(key) lastURL=\(lastURL) sinceURL=\(sinceURL)s\n"
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            try? FileManager.default.removeItem(at: url)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
