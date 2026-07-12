import AppKit
import CoreGraphics
import Observation
import ScreenCaptureKit
import Vision

@Observable
@MainActor
final class TextExtractorService {
    static let shared = TextExtractorService()

    private(set) var state: TextExtractorState = .idle
    private(set) var lastText = ""
    var settings: TextExtractorSettings { didSet { saveSettings() } }

    private let settingsKey = "text-extractor.settings.v1"
    private var selector: TextRegionSelector?

    private init() {
        settings = UserDefaults.standard.data(forKey: settingsKey)
            .flatMap { try? JSONDecoder().decode(TextExtractorSettings.self, from: $0) }
            ?? TextExtractorSettings()
        NotificationCenter.default.addObserver(forName: .toolActionRequested, object: nil, queue: .main) { [weak self] note in
            guard let action = note.object as? ToolActionID, action == .textExtractorCapture else { return }
            Task { @MainActor in self?.begin() }
        }
    }

    func begin() {
        guard requestPermissionIfNeeded() else { return }
        state = .selecting
        let selector = TextRegionSelector()
        self.selector = selector
        selector.begin { [weak self] selection, screen in
            guard let self else { return }
            self.selector = nil
            Task { await self.captureAndRecognize(selection: selection, screen: screen) }
        } cancellation: { [weak self] in
            self?.selector = nil
            self?.state = .idle
        }
    }

    func reset() { state = .idle }

    private func requestPermissionIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission"
        alert.informativeText = "Text Extractor needs access to capture the region you select. Recognition stays on this Mac and captured pixels are discarded immediately."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            state = .idle
            return false
        }
        guard CGRequestScreenCaptureAccess() else {
            state = .failed("Allow PowerToys in System Settings > Privacy & Security > Screen & System Audio Recording, then try again.")
            return false
        }
        return true
    }

    private func captureAndRecognize(selection: CGRect, screen: NSScreen) async {
        state = .recognizing
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw ExtractorError.displayUnavailable }

            let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let localRect = CGRect(
                x: selection.minX - screen.frame.minX,
                y: screen.frame.maxY - selection.maxY,
                width: selection.width,
                height: selection.height
            )
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = localRect
            configuration.width = Int(selection.width * screen.backingScaleFactor)
            configuration.height = Int(selection.height * screen.backingScaleFactor)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let text = try await recognize(image)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .failed("No text was found. The clipboard was not changed.")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            lastText = text
            state = .copied(text)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func recognize(_ image: CGImage) async throws -> String {
        let settings = settings
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = settings.speed == .accurate ? .accurate : .fast
            request.usesLanguageCorrection = settings.languageCorrection
            request.automaticallyDetectsLanguage = settings.preferredLanguages.isEmpty
            if !settings.preferredLanguages.isEmpty { request.recognitionLanguages = settings.preferredLanguages }
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let observations = (request.results ?? []).sorted { left, right in
                let verticalDifference = abs(left.boundingBox.midY - right.boundingBox.midY)
                if verticalDifference > 0.025 { return left.boundingBox.midY > right.boundingBox.midY }
                return left.boundingBox.minX < right.boundingBox.minX
            }
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    private func saveSettings() {
        UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: settingsKey)
    }
}

private enum ExtractorError: LocalizedError {
    case displayUnavailable
    var errorDescription: String? { "The selected display is no longer available." }
}

@MainActor
private final class TextRegionSelector {
    private var panels: [NSPanel] = []
    private var completion: ((CGRect, NSScreen) -> Void)?
    private var cancellation: (() -> Void)?

    func begin(completion: @escaping (CGRect, NSScreen) -> Void, cancellation: @escaping () -> Void) {
        self.completion = completion
        self.cancellation = cancellation
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = TextRegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.finish(global, screen: screen)
            } cancellation: { [weak self] in self?.cancel() }
            panel.makeKeyAndOrderFront(nil)
            return panel
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ rect: CGRect, screen: NSScreen) {
        close()
        completion?(rect, screen)
        completion = nil
        cancellation = nil
    }

    private func cancel() {
        close()
        cancellation?()
        completion = nil
        cancellation = nil
    }

    private func close() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}

private final class TextRegionSelectionView: NSView {
    private let completion: (CGRect) -> Void
    private let cancellation: () -> Void
    private var start: CGPoint?
    private var lastPoint: CGPoint?
    private var selection = CGRect.zero

    init(frame: CGRect, completion: @escaping (CGRect) -> Void, cancellation: @escaping () -> Void) {
        self.completion = completion
        self.cancellation = cancellation
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.2).setFill()
        bounds.fill()
        guard !selection.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: selection)
        outline.lineWidth = 2
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        lastPoint = start
        selection = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.shift), !selection.isEmpty, let lastPoint {
            selection = selection.offsetBy(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y)
        } else {
            selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        }
        lastPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        selection.width >= 3 && selection.height >= 3 ? completion(selection) : cancellation()
    }

    override func keyDown(with event: NSEvent) {
        event.keyCode == 53 ? cancellation() : super.keyDown(with: event)
    }
}
