import XCTest
@testable import powertoys

@MainActor
final class ColorPickerTests: XCTestCase {
    func testProjectsOwnNewPicksAndDeduplicateIndependently() {
        let (service, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }
        let sample = ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)

        let website = try! XCTUnwrap(service.createProject(named: "Website"))
        service.add(sample)
        let app = try! XCTUnwrap(service.createProject(named: "App"))
        service.add(sample)
        service.add(sample)

        XCTAssertEqual(service.samples(in: website.id).count, 1)
        XCTAssertEqual(service.samples(in: app.id).count, 1)
        XCTAssertEqual(service.selectedProjectID, app.id)
    }

    func testProjectsAndSelectionPersist() {
        let (service, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = try! XCTUnwrap(service.createProject(named: "Brand"))
        service.add(ColorSample(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))

        let restored = ColorPickerService(defaults: defaults)

        XCTAssertEqual(restored.projects, [project])
        XCTAssertEqual(restored.selectedProjectID, project.id)
        XCTAssertEqual(restored.samples(in: project.id).count, 1)
    }

    func testProjectCSSUsesHexAndAlphaOnlyWhenNeeded() {
        let samples = [
            ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1),
            ColorSample(red: 0, green: 0.5, blue: 1, alpha: 0.5)
        ]

        XCTAssertEqual(ColorPickerService.css(for: samples), """
        :root {
          --color-1: #FF8000;
          --color-2: #0080FF80;
        }

        """)
    }

    func testLegacyColorSampleDecodesWithoutProject() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","red":1,"green":0.5,"blue":0,"alpha":1,"createdAt":0,"isPinned":false}"#.utf8)

        let sample = try JSONDecoder().decode(ColorSample.self, from: data)

        XCTAssertNil(sample.projectID)
    }

    private func makeService() -> (ColorPickerService, UserDefaults, String) {
        let suite = "ColorPickerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (ColorPickerService(defaults: defaults), defaults, suite)
    }
}
