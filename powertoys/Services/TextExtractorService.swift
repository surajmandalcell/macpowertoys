import AppKit
import CoreGraphics
import Observation
import ScreenCaptureKit
import Vision

enum ScreenCapturePermissionDecision {
    case granted
    case cancelled
    case denied
}

@Observable
@MainActor
final class TextExtractorService {
    static let shared = TextExtractorService()

    private(set) var state: TextExtractorState = .idle
    private(set) var history: [TextExtraction]
    var settings: TextExtractorSettings { didSet { saveSettings() } }

    private let settingsKey = "text-extractor.settings.v1"
    private let historyKey = "text-extractor.history.v1"
    private let maximumHistoryCount = 50
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let playCompletionCue: () -> Void
    private let screenCapturePermission: () -> ScreenCapturePermissionDecision
    private let openTextExtractor: () -> Void
    private var selector: TextRegionSelector?
    private var shareableContentTask: Task<SCShareableContent, Error>?

    init(
        defaults: UserDefaults = .standard,
        pasteboard: NSPasteboard = .general,
        playCompletionCue: @escaping () -> Void = {
            NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)?.play()
        },
        screenCapturePermission: (() -> ScreenCapturePermissionDecision)? = nil,
        openTextExtractor: (() -> Void)? = nil
    ) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.playCompletionCue = playCompletionCue
        self.screenCapturePermission = screenCapturePermission ?? Self.requestScreenCapturePermission
        self.openTextExtractor = openTextExtractor ?? {
            ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorOpen))
        }
        settings = defaults.data(forKey: settingsKey)
            .flatMap { try? JSONDecoder().decode(TextExtractorSettings.self, from: $0) }
            ?? TextExtractorSettings()
        let decodedHistory = defaults.data(forKey: historyKey)
            .flatMap { try? JSONDecoder().decode([TextExtraction].self, from: $0) }
            ?? []
        history = decodedHistory
        NotificationCenter.default.addObserver(forName: .toolActionRequested, object: nil, queue: .main) { [weak self] note in
            guard let self, let action = note.object as? ToolActionID, action == .textExtractorCapture else { return }
            Task { @MainActor [self] in self.begin() }
        }
    }

    func begin() {
        guard state != .selecting, state != .recognizing else { return }
        switch screenCapturePermission() {
        case .granted:
            break
        case .cancelled:
            state = .idle
            return
        case .denied:
            state = .permissionDenied(
                "Allow MacPowerToys in System Settings > Privacy & Security > Screen & System Audio Recording, then try again."
            )
            openTextExtractor()
            return
        }
        state = .selecting
        shareableContentTask = Task {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        let selector = TextRegionSelector()
        self.selector = selector
        selector.begin { [weak self] selection, screen in
            guard let self else { return }
            self.selector = nil
            Task { await self.captureAndRecognize(selection: selection, screen: screen) }
        } cancellation: { [weak self] in
            self?.selector = nil
            self?.shareableContentTask?.cancel()
            self?.shareableContentTask = nil
            self?.state = .idle
        }
    }

    func reset() { state = .idle }

    func record(_ text: String, createdAt: Date = Date()) {
        let extraction = TextExtraction(text: text, createdAt: createdAt)
        history.insert(extraction, at: 0)
        history = Array(history.prefix(maximumHistoryCount))
        saveHistory()
    }

    func copy(_ extraction: TextExtraction) {
        pasteboard.clearContents()
        pasteboard.setString(extraction.text, forType: .string)
        state = .copied(extraction.text)
    }

    func finishRecognition(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        record(text)
        state = .copied(text)
        playCompletionCue()
    }

    func remove(_ id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private static func requestScreenCapturePermission() -> ScreenCapturePermissionDecision {
        if CGPreflightScreenCaptureAccess() { return .granted }
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission"
        alert.informativeText = "Text Extractor needs access to capture the region you select. Recognition stays on this Mac and captured pixels are discarded immediately."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
        return CGRequestScreenCaptureAccess() ? .granted : .denied
    }

    private func captureAndRecognize(selection: CGRect, screen: NSScreen) async {
        state = .recognizing
        do {
            let content: SCShareableContent
            if let task = shareableContentTask {
                shareableContentTask = nil
                do {
                    content = try await task.value
                } catch {
                    content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                }
            } else {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw ExtractorError.displayUnavailable }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let localRect = Self.captureRect(selection: selection, screenFrame: screen.frame)
            guard localRect.width >= 3, localRect.height >= 3 else {
                throw ExtractorError.invalidSelection
            }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = localRect
            configuration.width = max(1, Int((localRect.width * screen.backingScaleFactor).rounded()))
            configuration.height = max(1, Int((localRect.height * screen.backingScaleFactor).rounded()))
            configuration.showsCursor = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let text = try await recognize(image)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("No text was found. The clipboard was not changed.")
                return
            }
            finishRecognition(text)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func recognize(_ image: CGImage) async throws -> String {
        let settings = settings
        return try await Task.detached(priority: .userInitiated) {
            if settings.detectCodes {
                let request = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try? handler.perform([request])
                if let payload = request.results?.compactMap(\.payloadStringValue).first,
                   !payload.isEmpty {
                    return payload
                }
            }

            guard let image = Self.normalizedImageForRecognition(image) else {
                throw ExtractorError.imageNormalizationFailed
            }

            func recognize(level: VNRequestTextRecognitionLevel) throws -> String {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = level
                request.usesLanguageCorrection = settings.languageCorrection
                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                let languages = settings.preferredLanguages.filter(supported.contains)
                request.automaticallyDetectsLanguage = languages.isEmpty
                if !languages.isEmpty { request.recognitionLanguages = languages }
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try handler.perform([request])
                let observations = (request.results ?? []).sorted { left, right in
                    let verticalDifference = abs(left.boundingBox.midY - right.boundingBox.midY)
                    if verticalDifference > 0.025 { return left.boundingBox.midY > right.boundingBox.midY }
                    return left.boundingBox.minX < right.boundingBox.minX
                }
                return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }

            let level: VNRequestTextRecognitionLevel = settings.speed == .accurate ? .accurate : .fast
            do {
                let result = try recognize(level: level)
                guard result.isEmpty, level == .fast else { return result }
            } catch where level == .accurate {
                throw error
            }
            return try recognize(level: .accurate)
        }.value
    }

    nonisolated static func captureRect(selection: CGRect, screenFrame: CGRect) -> CGRect {
        let local = CGRect(
            x: selection.minX - screenFrame.minX,
            y: screenFrame.maxY - selection.maxY,
            width: selection.width,
            height: selection.height
        )
        return local.intersection(CGRect(origin: .zero, size: screenFrame.size)).integral
    }

    nonisolated static func normalizedImageForRecognition(_ image: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private func fail(_ message: String) {
        state = .failed(message)
        openTextExtractor()
    }

    private func saveSettings() {
        defaults.set(try? JSONEncoder().encode(settings), forKey: settingsKey)
    }

    private func saveHistory() {
        defaults.set(try? JSONEncoder().encode(history), forKey: historyKey)
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private enum ExtractorError: LocalizedError {
    case displayUnavailable
    case invalidSelection
    case imageNormalizationFailed

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "The selected display is no longer available."
        case .invalidSelection: "Select a larger region and try again."
        case .imageNormalizationFailed: "The selected image could not be prepared for recognition."
        }
    }
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
            let panel = TextRegionSelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.sharingType = .none
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = TextRegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.finish(global, screen: screen)
            } cancellation: { [weak self] in self?.cancel() }
            panel.orderFront(nil)
            panel.makeFirstResponder(panel.contentView)
            return panel
        }
        let pointer = NSEvent.mouseLocation
        let activeIndex = NSScreen.screens.firstIndex { $0.frame.contains(pointer) } ?? 0
        if panels.indices.contains(activeIndex) { panels[activeIndex].makeKey() }
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

private final class TextRegionSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class TextRegionSelectionView: NSView {
    private let completion: (CGRect) -> Void
    private let cancellation: () -> Void
    private var start: CGPoint?
    private var lastPoint: CGPoint?
    private var shiftWasDownAtMouseDown = false
    private var selection = CGRect.zero
    private var tracking: NSTrackingArea?

    init(frame: CGRect, completion: @escaping (CGRect) -> Void, cancellation: @escaping () -> Void) {
        self.completion = completion
        self.cancellation = cancellation
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.2).setFill()
        bounds.fill()
        if let window {
            let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let crosshair = NSBezierPath()
            crosshair.move(to: CGPoint(x: pointer.x - 18, y: pointer.y))
            crosshair.line(to: CGPoint(x: pointer.x - 5, y: pointer.y))
            crosshair.move(to: CGPoint(x: pointer.x + 5, y: pointer.y))
            crosshair.line(to: CGPoint(x: pointer.x + 18, y: pointer.y))
            crosshair.move(to: CGPoint(x: pointer.x, y: pointer.y - 18))
            crosshair.line(to: CGPoint(x: pointer.x, y: pointer.y - 5))
            crosshair.move(to: CGPoint(x: pointer.x, y: pointer.y + 5))
            crosshair.line(to: CGPoint(x: pointer.x, y: pointer.y + 18))
            crosshair.lineCapStyle = .round
            NSColor.black.withAlphaComponent(0.75).setStroke()
            crosshair.lineWidth = 4
            crosshair.stroke()
            NSColor.white.setStroke()
            crosshair.lineWidth = 2
            crosshair.stroke()
        }
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
        shiftWasDownAtMouseDown = event.modifierFlags.contains(.shift)
        selection = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !shiftWasDownAtMouseDown, event.modifierFlags.contains(.shift), !selection.isEmpty, let lastPoint {
            selection = selection.offsetBy(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y)
        } else {
            selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        }
        lastPoint = point
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        selection.width >= 3 && selection.height >= 3 ? completion(selection) : cancellation()
    }

    override func keyDown(with event: NSEvent) {
        event.keyCode == 53 ? cancellation() : super.keyDown(with: event)
    }
}
