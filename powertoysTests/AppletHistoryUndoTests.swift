import AppKit
import XCTest
@testable import powertoys

@MainActor
final class AppletHistoryUndoTests: XCTestCase {
    func testHistoryUndoPreservesRecordsOrderProjectsAndNewArrivals() async throws {
        let suite = "audit-applets-r11.undo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ColorProject(name: "Fixture")
        let samples = (0..<3).map { ColorSample(red: Double($0) / 2, green: 0.2, blue: 0.5, alpha: 1, projectID: project.id) }
        defaults.set(try JSONEncoder().encode(samples), forKey: "color-picker.history.v1")
        defaults.set(try JSONEncoder().encode([project]), forKey: "color-picker.projects.v1")
        let color = ColorPickerService(defaults: defaults, sampler: HistoryUndoSampler())
        let manager = UndoManager()
        manager.groupsByEvent = false
        func perform(_ action: () -> Void) {
            manager.beginUndoGrouping(); action(); manager.endUndoGrouping()
        }
        perform { color.togglePin(samples[0].id, undoManager: manager) }
        XCTAssertTrue(color.history[0].isPinned)
        XCTAssertTrue(manager.undoActionName == "Pin Color")
        manager.undo()
        XCTAssertTrue(!color.history[0].isPinned && manager.redoActionName == "Pin Color")
        manager.redo()
        XCTAssertTrue(color.history[0].isPinned)
        perform { color.remove(samples[1].id, undoManager: manager) }
        color.togglePin(samples[2].id)
        manager.undo()
        XCTAssertTrue(color.history.map(\.id) == samples.map(\.id))
        XCTAssertTrue(color.history[2].isPinned)
        manager.redo()
        XCTAssertTrue(color.history.map(\.id) == [samples[0].id, samples[2].id])
        manager.undo()
        perform { color.clearAll(undoManager: manager) }
        XCTAssertTrue(color.history.isEmpty)
        manager.undo()
        XCTAssertTrue(color.history.map(\.id) == samples.map(\.id))
        manager.redo()
        XCTAssertTrue(color.history.isEmpty)
        manager.undo()
        perform { color.selectProject(project.id, undoManager: manager) }
        manager.undo(); XCTAssertTrue(color.selectedProjectID == nil)
        manager.redo(); XCTAssertTrue(color.selectedProjectID == project.id)
        var created: ColorProject?
        perform { created = color.createProject(named: "New", undoManager: manager) }
        let createdProject = try XCTUnwrap(created)
        manager.undo(); XCTAssertTrue(color.projects == [project] && color.history.count == 3)
        manager.redo(); XCTAssertTrue(color.projects == [project, createdProject] && color.selectedProjectID == createdProject.id)
        await color.flushPersistence()
        let restored = ColorPickerService(defaults: defaults, sampler: HistoryUndoSampler())
        XCTAssertTrue(restored.history == color.history && restored.projects == color.projects)
        XCTAssertTrue(restored.selectedProjectID == color.selectedProjectID)

        let text = TextExtractorService(defaults: defaults, playCompletionCue: {}, screenCapturePermission: { .cancelled }, openTextExtractor: {})
        text.record("First"); text.record("Second"); text.record("Third")
        let original = text.history
        perform { text.remove(original[1].id, undoManager: manager) }
        text.record("New arrival")
        manager.undo()
        XCTAssertTrue(text.history.map(\.text) == ["New arrival", "Third", "Second", "First"])
        manager.redo()
        XCTAssertTrue(text.history.map(\.text) == ["New arrival", "Third", "First"])
        perform { text.clearHistory(undoManager: manager) }
        text.record("After clear")
        manager.undo()
        XCTAssertTrue(text.history.map(\.text) == ["After clear", "New arrival", "Third", "First"])
        manager.redo()
        XCTAssertTrue(text.history.map(\.text) == ["After clear"])
        let reopened = TextExtractorService(defaults: defaults, playCompletionCue: {}, screenCapturePermission: { .cancelled }, openTextExtractor: {})
        XCTAssertTrue(reopened.history == text.history)
    }
}

@MainActor
private final class HistoryUndoSampler: ColorSampling {
    func show(selectionHandler: @escaping @Sendable (NSColor?) -> Void) {}
}
