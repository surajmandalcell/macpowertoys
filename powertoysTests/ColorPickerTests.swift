import XCTest
@testable import powertoys

@MainActor
final class ColorPickerTests: XCTestCase {
    func testPickIgnoresRequestsWhileSamplerIsActive() async {
        let sampler = ColorSamplerStub()
        let (service, defaults, suite) = makeService(sampler: sampler)
        defer { defaults.removePersistentDomain(forName: suite) }

        service.pick()
        service.pick()

        XCTAssertTrue(service.isPicking)
        XCTAssertEqual(sampler.showCount, 1)

        sampler.complete(with: nil)
        await Task.yield()
        XCTAssertFalse(service.isPicking)

        service.pick()
        XCTAssertEqual(sampler.showCount, 2)
    }

    func testProjectsOwnNewPicksAndDeduplicateIndependently() {
        let (service, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }
        let sample = ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)

        let website = try! XCTUnwrap(service.createProject(named: "Website"))
        XCTAssertFalse(service.canCreateProject(named: " website "))
        XCTAssertTrue(service.canCreateProject(named: "App"))
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

    private func makeService(
        sampler: any ColorSampling = NSColorSampler()
    ) -> (ColorPickerService, UserDefaults, String) {
        let suite = "ColorPickerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (ColorPickerService(defaults: defaults, sampler: sampler), defaults, suite)
    }
}

@MainActor
private final class ColorSamplerStub: ColorSampling {
    private(set) var showCount = 0
    private var selectionHandler: (@Sendable (NSColor?) -> Void)?

    func show(selectionHandler: @escaping @Sendable (NSColor?) -> Void) {
        showCount += 1
        self.selectionHandler = selectionHandler
    }

    func complete(with color: NSColor?) {
        let selectionHandler = selectionHandler
        self.selectionHandler = nil
        selectionHandler?(color)
    }
}
