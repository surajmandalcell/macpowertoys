import AppKit
import CoreImage
import CoreGraphics
import CoreText
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
    private var recognitionWarmupTask: Task<Void, Never>?
    private var didPrewarm = false

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
        if shareableContentTask == nil { prepareShareableContent() }
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

    func prewarm() {
        guard !didPrewarm else { return }
        didPrewarm = true
        let settings = settings
        recognitionWarmupTask = Task.detached(priority: .userInitiated) {
            Self.prewarmRecognition(settings: settings)
        }
        if CGPreflightScreenCaptureAccess() { prepareShareableContent() }
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
            configuration.scalesToFit = false
            configuration.showsCursor = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let text = try await recognize(image, sourceScale: screen.backingScaleFactor)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("No text was found. The clipboard was not changed.")
                return
            }
            finishRecognition(text)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func recognize(_ image: CGImage, sourceScale: CGFloat = 2) async throws -> String {
        let settings = settings
        if let recognitionWarmupTask {
            await recognitionWarmupTask.value
            self.recognitionWarmupTask = nil
        }
        return try await Task.detached(priority: .userInitiated) {
            let lowDensity = sourceScale < 2
            let recognitionImage = lowDensity
                ? Self.enhancedImageForRecognition(image, sourceScale: sourceScale) ?? image
                : image

            func recognize(level: VNRequestTextRecognitionLevel) throws -> String {
                let textRequest = Self.textRecognitionRequest(level: level, settings: settings, lowDensity: lowDensity)
                let barcodeRequest = settings.detectCodes ? VNDetectBarcodesRequest() : nil
                let requests: [VNRequest] = [textRequest] + (barcodeRequest.map { [$0] } ?? [])
                let handler = VNImageRequestHandler(cgImage: recognitionImage, options: [:])
                try handler.perform(requests)
                if let payload = barcodeRequest?.results?.compactMap(\.payloadStringValue).first,
                   !payload.isEmpty {
                    return payload
                }
                let observations = (textRequest.results ?? []).sorted { left, right in
                    let verticalDifference = abs(left.boundingBox.midY - right.boundingBox.midY)
                    if verticalDifference > 0.015 { return left.boundingBox.midY > right.boundingBox.midY }
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

    private nonisolated static let fastRecognitionLanguages: [String] = loadSupportedRecognitionLanguages(level: .fast)
    private nonisolated static let accurateRecognitionLanguages: [String] = loadSupportedRecognitionLanguages(level: .accurate)
    private nonisolated static let recognitionContext = CIContext(options: [.useSoftwareRenderer: false])

    private nonisolated static func loadSupportedRecognitionLanguages(level: VNRequestTextRecognitionLevel) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    private nonisolated static func supportedRecognitionLanguages(level: VNRequestTextRecognitionLevel) -> [String] {
        level == .fast ? fastRecognitionLanguages : accurateRecognitionLanguages
    }

    private nonisolated static func textRecognitionRequest(
        level: VNRequestTextRecognitionLevel,
        settings: TextExtractorSettings,
        lowDensity: Bool
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = settings.languageCorrection
        if lowDensity {
            request.minimumTextHeight = 0
            if let newest = VNRecognizeTextRequest.supportedRevisions.max() {
                request.revision = newest
            }
        }
        let supported = supportedRecognitionLanguages(level: level)
        let languages = settings.preferredLanguages.filter(supported.contains)
        request.automaticallyDetectsLanguage = languages.isEmpty
        if !languages.isEmpty { request.recognitionLanguages = languages }
        return request
    }

    private nonisolated static func prewarmRecognition(settings: TextExtractorSettings) {
        _ = fastRecognitionLanguages
        _ = accurateRecognitionLanguages
        guard let image = prewarmImage() else { return }
        let levels: [VNRequestTextRecognitionLevel] = settings.speed == .accurate ? [.accurate] : [.fast, .accurate]
        for (index, level) in levels.enumerated() {
            let text = textRecognitionRequest(level: level, settings: settings, lowDensity: false)
            let barcode = settings.detectCodes && index == 0 ? VNDetectBarcodesRequest() : nil
            let requests: [VNRequest] = [text] + (barcode.map { [$0] } ?? [])
            try? VNImageRequestHandler(cgImage: image).perform(requests)
        }
    }

    nonisolated static func prewarmImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 512,
            height: 128,
            bitsPerComponent: 8,
            bytesPerRow: 512,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 128))
        let attributes = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 42, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ] as CFDictionary
        guard let string = CFAttributedStringCreate(nil, "MacPowerToys warmup 123" as CFString, attributes) else { return nil }
        context.textPosition = CGPoint(x: 18, y: 42)
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
        return context.makeImage()
    }

    nonisolated static func enhancedImageForRecognition(_ image: CGImage, sourceScale: CGFloat) -> CGImage? {
        guard sourceScale > 0, sourceScale < 2 else { return nil }
        let scale = max(1, 3 / sourceScale)
        let input = CIImage(cgImage: image)
        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        lanczos.setValue(input, forKey: kCIInputImageKey)
        lanczos.setValue(scale, forKey: kCIInputScaleKey)
        lanczos.setValue(1, forKey: kCIInputAspectRatioKey)
        guard var output = lanczos.outputImage else { return nil }
        if let contrast = CIFilter(name: "CIColorControls") {
            contrast.setValue(output, forKey: kCIInputImageKey)
            contrast.setValue(1.1, forKey: kCIInputContrastKey)
            output = contrast.outputImage ?? output
        }
        if let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(output, forKey: kCIInputImageKey)
            unsharp.setValue(1.6, forKey: kCIInputRadiusKey)
            unsharp.setValue(0.7, forKey: kCIInputIntensityKey)
            output = unsharp.outputImage ?? output
        }
        return recognitionContext.createCGImage(output, from: output.extent)
    }

    private func fail(_ message: String) {
        state = .failed(message)
        openTextExtractor()
    }

    private func prepareShareableContent() {
        shareableContentTask?.cancel()
        shareableContentTask = Task {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
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

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "The selected display is no longer available."
        case .invalidSelection: "Select a larger region and try again."
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

enum TextSelectionCursor {
    static let cursor: NSCursor = {
        let size = NSSize(width: 36, height: 36)
        let image = NSImage(size: size)
        image.lockFocus()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 18))
        path.line(to: NSPoint(x: 13, y: 18))
        path.move(to: NSPoint(x: 23, y: 18))
        path.line(to: NSPoint(x: 36, y: 18))
        path.move(to: NSPoint(x: 18, y: 0))
        path.line(to: NSPoint(x: 18, y: 13))
        path.move(to: NSPoint(x: 18, y: 23))
        path.line(to: NSPoint(x: 18, y: 36))
        path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(0.78).setStroke()
        path.lineWidth = 4
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 18, y: 18))
    }()
}

private final class TextRegionSelectionView: NSView {
    private let completion: (CGRect) -> Void
    private let cancellation: () -> Void
    private var start: CGPoint?
    private var lastPoint: CGPoint?
    private var shiftWasDownAtMouseDown = false
    private var selection = CGRect.zero

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
        addCursorRect(bounds, cursor: TextSelectionCursor.cursor)
    }

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

    override func mouseUp(with event: NSEvent) {
        selection.width >= 3 && selection.height >= 3 ? completion(selection) : cancellation()
    }

    override func keyDown(with event: NSEvent) {
        event.keyCode == 53 ? cancellation() : super.keyDown(with: event)
    }
}
