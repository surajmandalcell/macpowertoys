import OnePlusUI
import XCTest
@testable import powertoys

final class CompactAppletRedesignTests: XCTestCase {
    func testHistoryWindowsStayWithinTheirCanvasForEmptyAndLargeHistories() {
        for count in [0, 1, 2, 5, 1000] {
            XCTAssertTrue(OnePlusWindowCanvas.colorPicker.heightRange!.contains(ColorPickerLayout.historyHeight(count: count)))
            XCTAssertTrue(OnePlusWindowCanvas.textExtractor.heightRange!.contains(TextExtractorLayout.historyHeight(count: count)))
        }
        XCTAssertEqual(ColorPickerLayout.historyHeight(count: 1000), 460)
        XCTAssertEqual(TextExtractorLayout.historyHeight(count: 1000), 462)
        XCTAssertEqual(AwakeLayout.windowWidth, 560)
        XCTAssertEqual(AwakeLayout.windowHeight, 500)
    }

    func testColorHistoryPresentationFiltersAndFormatsOffTheViewPath() throws {
        let projectID = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let projectSample = ColorSample(
            id: UUID(), red: 1, green: 0, blue: 0, alpha: 1,
            createdAt: now.addingTimeInterval(-120), projectID: projectID
        )
        let unfiledSample = ColorSample(
            id: UUID(), red: 0, green: 0, blue: 1, alpha: 1,
            createdAt: now
        )

        let presentation = colorPickerPresentation(
            history: [projectSample, unfiledSample], projectID: projectID,
            search: "255, 0, 0", format: .hex, now: now
        )

        XCTAssertEqual(presentation.samples.map(\.id), [projectSample.id])
        XCTAssertEqual(presentation.samples.first?.value, "#FF0000")
        XCTAssertEqual(presentation.projectCounts[projectID], 1)
        XCTAssertEqual(presentation.unfiledCount, 1)
    }

    func testTextHistoryPresentationPreparesRowMetadata() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let extraction = TextExtraction(
            id: UUID(), text: "https://example.com/path",
            createdAt: now.addingTimeInterval(-120)
        )

        let row = try XCTUnwrap(textExtractionPresentations([extraction], now: now).first)

        XCTAssertEqual(row.id, extraction.id)
        XCTAssertEqual(row.openableURL?.absoluteString, extraction.text)
        XCTAssertFalse(row.timestamp.isEmpty)
    }
}
