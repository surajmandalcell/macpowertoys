import XCTest
import CoreImage
@testable import powertoys

@MainActor
final class CoreModelTests: XCTestCase {
    func testTextExtractorSettingsAndRecognitionTitles() {
        XCTAssertEqual(TextRecognitionSpeed.allCases.map(\.title), ["Accurate", "Fast"])
        let settings = TextExtractorSettings()
        XCTAssertEqual(settings.speed, .fast)
        XCTAssertTrue(settings.languageCorrection)
        XCTAssertTrue(settings.preferredLanguages.isEmpty)
        XCTAssertTrue(settings.detectCodes)

        let legacy = Data(#"{"speed":"accurate","languageCorrection":false,"preferredLanguages":["fr-FR"]}"#.utf8)
        let migrated = try? JSONDecoder().decode(TextExtractorSettings.self, from: legacy)
        XCTAssertEqual(migrated?.speed, .accurate)
        XCTAssertEqual(migrated?.preferredLanguages, ["fr-FR"])
        XCTAssertEqual(migrated?.detectCodes, true)
    }

    func testTextExtractorPersistsAndMaintainsHistory() {
        let suiteName = "TextExtractorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = TextExtractorService(defaults: defaults)
        service.settings.detectCodes = false
        let firstDate = Date(timeIntervalSince1970: 100)
        service.record("First", createdAt: firstDate)
        service.record("Second", createdAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(service.history.map(\.text), ["Second", "First"])

        let restored = TextExtractorService(defaults: defaults)
        XCTAssertFalse(restored.settings.detectCodes)
        XCTAssertEqual(restored.history, service.history)
        restored.remove(restored.history[0].id)
        XCTAssertEqual(restored.history.map(\.text), ["First"])
        restored.clearHistory()
        XCTAssertTrue(restored.history.isEmpty)

        for index in 0...50 {
            restored.record("Item \(index)")
        }
        XCTAssertEqual(restored.history.count, 50)
        XCTAssertEqual(restored.history.first?.text, "Item 50")
        XCTAssertEqual(restored.history.last?.text, "Item 1")
    }

    func testRecognitionCopiesOnlyTextBeforePlayingCompletionCue() {
        let suiteName = "TextExtractorCompletionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            pasteboard.clearContents()
        }
        var cueText: String?
        let service = TextExtractorService(defaults: defaults, pasteboard: pasteboard) {
            cueText = pasteboard.string(forType: .string)
        }

        service.finishRecognition("Recognized text")

        XCTAssertEqual(pasteboard.string(forType: .string), "Recognized text")
        XCTAssertNil(pasteboard.data(forType: .tiff))
        XCTAssertEqual(cueText, "Recognized text")
        XCTAssertEqual(service.history.map(\.text), ["Recognized text"])
        XCTAssertEqual(service.state, .copied("Recognized text"))
    }

    func testTextRecognitionFallsBackFromUnsupportedLanguages() async throws {
        let suiteName = "TextExtractorVisionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let size = NSSize(width: 760, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ("PowerToys 42" as NSString).draw(
            at: NSPoint(x: 28, y: 42),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
        )
        image.unlockFocus()

        let service = TextExtractorService(defaults: defaults)
        service.settings.preferredLanguages = ["xx-unsupported"]
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let text = try await service.recognize(cgImage)

        XCTAssertTrue(text.replacingOccurrences(of: " ", with: "").contains("PowerToys42"))
    }

    func testTextRecognitionReadsQRCodePayload() async throws {
        let suiteName = "TextExtractorQRCodeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let payload = "https://example.com/powertoys"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)))
        let image = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))

        let service = TextExtractorService(defaults: defaults)
        let recognized = try await service.recognize(image)

        XCTAssertEqual(recognized, payload)
    }

    func testTextRecognitionNormalizesScreenCaptureImages() throws {
        let size = NSSize(width: 180, height: 60)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let source = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let normalized = try XCTUnwrap(TextExtractorService.normalizedImageForRecognition(source))

        XCTAssertEqual(normalized.width, source.width)
        XCTAssertEqual(normalized.height, source.height)
        XCTAssertEqual(normalized.bitsPerComponent, 8)
        XCTAssertEqual(normalized.bitsPerPixel, 32)
        XCTAssertEqual(normalized.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testTextExtractorCaptureRectIsIntegralAndClampedToItsDisplay() {
        let screen = CGRect(x: 100, y: 200, width: 800, height: 600)
        let selection = CGRect(x: 98.4, y: 788.2, width: 24.7, height: 18.1)

        let rect = TextExtractorService.captureRect(selection: selection, screenFrame: screen)

        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 24, height: 12))
    }

    func testLongTextExtractionNeedsExpandedView() {
        XCTAssertFalse(TextExtraction(text: "Short text").needsExpandedView)
        XCTAssertTrue(TextExtraction(text: String(repeating: "A", count: 181)).needsExpandedView)
        XCTAssertTrue(TextExtraction(text: "One\nTwo\nThree\nFour\nFive").needsExpandedView)
        XCTAssertEqual(TextExtraction(text: " https://example.com/path ").openableURL?.absoluteString, "https://example.com/path")
        XCTAssertNil(TextExtraction(text: "file:///tmp/private").openableURL)
        XCTAssertNil(TextExtraction(text: "https://").openableURL)
    }

    func testTextExtractionRelativeTimestampOmitsSeconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(TextExtraction(text: "", createdAt: now.addingTimeInterval(-30)).relativeTimestamp(at: now), "Just now")
        XCTAssertFalse(
            TextExtraction(text: "", createdAt: now.addingTimeInterval(-90))
                .relativeTimestamp(at: now)
                .localizedCaseInsensitiveContains("sec")
        )
    }

    func testCachedMessageMapsKnownAndUnknownTypes() {
        let date = Date(timeIntervalSince1970: 123)
        XCTAssertEqual(CachedMessage(messageId: "1", type: "user", content: "Hi", timestamp: date).toCCMessage(sessionId: "s").type, .user)
        XCTAssertEqual(CachedMessage(messageId: "2", type: "assistant", content: "Hello", timestamp: date).toCCMessage(sessionId: "s").type, .assistant)
        XCTAssertEqual(CachedMessage(messageId: "3", type: "future", content: "Notice", timestamp: date).toCCMessage(sessionId: "s").type, .system)
    }

    func testCachedMessageDecodesToolUseAndIgnoresMalformedJSON() throws {
        let block = ToolUseBlock(id: "tool-1", name: "Read", input: "file", output: "contents")
        let json = String(data: try JSONEncoder().encode([block]), encoding: .utf8)
        let valid = CachedMessage(messageId: "1", type: "assistant", content: "", timestamp: Date(), toolUseJSON: json)
        XCTAssertEqual(valid.toCCMessage(sessionId: "session").toolUse, [block])

        let malformed = CachedMessage(messageId: "2", type: "assistant", content: "", timestamp: Date(), toolUseJSON: "not json")
        XCTAssertTrue(malformed.toCCMessage(sessionId: "session").toolUse.isEmpty)
    }

    func testTransferRecordSnapshotsJobAndComputesDurationAndSpeed() {
        let started = Date(timeIntervalSince1970: 100)
        let job = TransferJob(
            operation: .move,
            kind: .file,
            sourceFs: "/source/file",
            destinationFs: "remote:file",
            sourceDisplay: "file",
            destinationDisplay: "remote",
            excludePatterns: ["*.tmp"],
            maxRetries: 3,
            createdAt: Date(timeIntervalSince1970: 50)
        )
        job.state = .completed
        job.startedAt = started
        job.finishedAt = started.addingTimeInterval(4)
        job.stats.bytes = 400
        job.stats.totalBytes = 500
        job.stats.transfers = 1
        job.stats.totalTransfers = 1
        job.attempt = 2

        let record = TransferRecord(job: job)
        XCTAssertEqual(record.operation, .move)
        XCTAssertEqual(record.kind, .file)
        XCTAssertEqual(record.state, .completed)
        XCTAssertEqual(record.duration, 4)
        XCTAssertEqual(record.averageSpeed, 100)
        XCTAssertEqual(record.excludePatterns, "*.tmp")
        XCTAssertEqual(record.attempts, 2)
    }

    func testTransferRecordFallbacksAndMissingDuration() {
        let job = TransferJob(
            operation: .copy,
            sourceFs: "/source",
            destinationFs: "remote:dest",
            sourceDisplay: "source",
            destinationDisplay: "dest",
            excludePatterns: [],
            maxRetries: 1
        )
        let record = TransferRecord(job: job)
        record.operationRaw = "future"
        record.kindRaw = "future"
        record.stateRaw = "future"

        XCTAssertEqual(record.operation, .copy)
        XCTAssertEqual(record.kind, .directory)
        XCTAssertEqual(record.state, .completed)
        XCTAssertNil(record.duration)
        XCTAssertEqual(record.averageSpeed, 0)
    }
}
