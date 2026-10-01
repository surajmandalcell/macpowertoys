import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
protocol ColorSampling: AnyObject {
    func show(selectionHandler: @escaping @Sendable (NSColor?) -> Void)
}

extension NSColorSampler: ColorSampling {}

@Observable
@MainActor
final class ColorPickerService {
    static let shared = ColorPickerService()

    private(set) var history: [ColorSample]
    private(set) var projects: [ColorProject]
    private(set) var selectedProjectID: UUID? {
        didSet {
            if let selectedProjectID {
                defaults.set(selectedProjectID.uuidString, forKey: selectedProjectKey)
            } else {
                defaults.removeObject(forKey: selectedProjectKey)
            }
        }
    }
    var exportError: String?
    private(set) var isPicking = false
    var defaultFormat: ColorCopyFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: formatKey) }
    }

    private let pasteboard: NSPasteboard
    private let sampler: any ColorSampling
    private let defaults: UserDefaults
    private let historyKey = "color-picker.history.v1"
    private let projectsKey = "color-picker.projects.v1"
    private let selectedProjectKey = "color-picker.selected-project.v1"
    private let formatKey = "color-picker.format.v1"
    private let maximumHistory = 100
    @ObservationIgnored private var persistenceTask: Task<Void, Error>?

    init(defaults: UserDefaults = .standard, sampler: any ColorSampling = NSColorSampler(),
         pasteboard: NSPasteboard = .general) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.sampler = sampler
        history = defaults.data(forKey: historyKey)
            .flatMap { try? JSONDecoder().decode([ColorSample].self, from: $0) } ?? []
        projects = defaults.data(forKey: projectsKey)
            .flatMap { try? JSONDecoder().decode([ColorProject].self, from: $0) } ?? []
        defaultFormat = defaults.string(forKey: formatKey)
            .flatMap(ColorCopyFormat.init(rawValue:)) ?? .hex
        selectedProjectID = defaults.string(forKey: selectedProjectKey)
            .flatMap(UUID.init(uuidString:))
            .flatMap { id in projects.contains(where: { $0.id == id }) ? id : nil }
        NotificationCenter.default.addObserver(forName: .toolActionRequested, object: nil, queue: .main) { [weak self] note in
            guard let self, let action = note.object as? ToolActionID else { return }
            Task { @MainActor [self, action] in
                switch action {
                case .colorPickerPick: self.pick()
                case .colorPickerCopyLast: self.copyLast()
                default: break
                }
            }
        }
    }

    func pick() {
        guard !isPicking else { return }
        isPicking = true
        NSApp.activate(ignoringOtherApps: true)
        sampler.show { [weak self] color in
            Task { @MainActor [weak self, color] in
                guard let self else { return }
                self.isPicking = false
                guard let color, let converted = color.usingColorSpace(.sRGB) else { return }
                self.add(ColorSample(
                    red: converted.redComponent,
                    green: converted.greenComponent,
                    blue: converted.blueComponent,
                    alpha: converted.alphaComponent
                ))
            }
        }
    }

    func add(_ sample: ColorSample) {
        var latest = sample
        latest.projectID = selectedProjectID
        latest.isPinned = history.first {
            $0.projectID == latest.projectID && $0.matches(latest)
        }?.isPinned ?? false
        history.removeAll { $0.projectID == latest.projectID && $0.matches(latest) }
        history.insert(latest, at: 0)
        trimAndSave(projectID: latest.projectID)
        copy(latest, as: defaultFormat)
    }

    func copy(_ sample: ColorSample, as format: ColorCopyFormat) {
        pasteboard.clearContents()
        pasteboard.setString(sample.string(format), forType: .string)
    }

    func copyLast() {
        guard let sample = history.first else { return }
        copy(sample, as: defaultFormat)
    }

    func togglePin(_ id: UUID, undoManager: UndoManager? = nil) {
        guard let sample = history.first(where: { $0.id == id }) else { return }
        setPinned(id, to: !sample.isPinned, undoManager: undoManager,
                  actionName: sample.isPinned ? "Unpin Color" : "Pin Color")
    }

    private func setPinned(_ id: UUID, to pinned: Bool, undoManager: UndoManager?, actionName: String) {
        guard let index = history.firstIndex(where: { $0.id == id }), history[index].isPinned != pinned else { return }
        let previous = history[index].isPinned
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] service in
            service.setPinned(id, to: previous, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        history[index].isPinned = pinned
        save()
    }

    func remove(_ id: UUID, undoManager: UndoManager? = nil) {
        removeSamples([id], undoManager: undoManager, actionName: "Delete Color")
    }

    func clearAll(undoManager: UndoManager? = nil) {
        removeSamples(Set(history.map(\.id)), undoManager: undoManager, actionName: "Clear Colors")
    }

    private func removeSamples(_ ids: Set<UUID>, undoManager: UndoManager?, actionName: String) {
        let entries = history.enumerated().filter { ids.contains($0.element.id) }
        guard !entries.isEmpty else { return }
        let remainingCount = history.count - entries.count
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] service in
            service.restoreSamples(entries, remainingCount: remainingCount, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        history.removeAll { ids.contains($0.id) }
        save()
    }

    private func restoreSamples(_ entries: [(offset: Int, element: ColorSample)], remainingCount: Int, undoManager: UndoManager?, actionName: String) {
        let existing = Set(history.map(\.id))
        let missing = entries.filter { !existing.contains($0.element.id) }
        guard !missing.isEmpty else { return }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] service in
            service.removeSamples(Set(missing.map { $0.element.id }), undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        let newerCount = max(0, history.count - remainingCount)
        for entry in missing { history.insert(entry.element, at: min(entry.offset + newerCount, history.count)) }
        save()
    }

    @discardableResult
    func createProject(named name: String, undoManager: UndoManager? = nil) -> ColorProject? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canCreateProject(named: name) else { return nil }
        let project = ColorProject(name: name)
        let previousSelection = selectedProjectID
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] service in
            service.removeProject(project.id, selection: previousSelection, undoManager: undoManager)
        }
        undoManager?.setActionName("Create Color Project")
        projects.append(project)
        saveProjects()
        selectProject(project.id)
        return project
    }

    func canCreateProject(named name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !projects.contains {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    func selectProject(_ id: UUID?, undoManager: UndoManager? = nil) {
        guard selectedProjectID != id, id == nil || projects.contains(where: { $0.id == id }) else { return }
        let previous = selectedProjectID
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] service in
            let restored = previous.flatMap { id in service.projects.contains { $0.id == id } ? id : nil }
            service.selectProject(restored, undoManager: undoManager)
        }
        undoManager?.setActionName("Change Color Project")
        selectedProjectID = id
    }

    private func removeProject(_ id: UUID, selection: UUID?, undoManager: UndoManager?) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let project = projects[index]
        let assignedIDs = Set(history.filter { $0.projectID == id }.map(\.id))
        let previousSelection = selectedProjectID
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] service in
            service.restoreProject(project, at: index, assignedIDs: assignedIDs,
                                   selection: previousSelection, undoManager: undoManager)
        }
        undoManager?.setActionName("Create Color Project")
        projects.remove(at: index)
        for index in history.indices where assignedIDs.contains(history[index].id) { history[index].projectID = nil }
        selectedProjectID = selection.flatMap { id in projects.contains { $0.id == id } ? id : nil }
        save()
    }

    private func restoreProject(_ project: ColorProject, at index: Int, assignedIDs: Set<UUID>, selection: UUID?, undoManager: UndoManager?) {
        guard !projects.contains(where: { $0.id == project.id }) else { return }
        let previousSelection = selectedProjectID
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] service in
            service.removeProject(project.id, selection: previousSelection, undoManager: undoManager)
        }
        undoManager?.setActionName("Create Color Project")
        projects.insert(project, at: min(index, projects.count))
        for index in history.indices where assignedIDs.contains(history[index].id) && history[index].projectID == nil {
            history[index].projectID = project.id
        }
        selectedProjectID = selection.flatMap { id in projects.contains { $0.id == id } ? id : nil }
        save()
    }

    func samples(in projectID: UUID?) -> [ColorSample] {
        history.filter { $0.projectID == projectID }
    }

    func export(_ project: ColorProject, from window: NSWindow? = nil) {
        let content = Self.css(for: samples(in: project.id))
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.css]
        panel.nameFieldStringValue = "\(project.name).css"
        panel.message = "Export \(project.name) colors as CSS"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await Task.detached {
                        try Data(content.utf8).write(to: url, options: .atomic)
                    }.value
                } catch {
                    self?.exportError = error.localizedDescription
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    static func css(for samples: [ColorSample]) -> String {
        let declarations = samples.enumerated().map { index, sample in
            let format: ColorCopyFormat = sample.alpha < 0.9995 ? .hexa : .hex
            return "  --color-\(index + 1): \(sample.string(format));"
        }
        return ([":root {"] + declarations + ["}", ""]).joined(separator: "\n")
    }

    private func trimAndSave(projectID: UUID?) {
        let projectSamples = history.filter { $0.projectID == projectID }
        let pinned = projectSamples.filter(\.isPinned)
        let recent = projectSamples.filter { !$0.isPinned }.prefix(max(0, maximumHistory - pinned.count))
        let keptIDs = Set((pinned + Array(recent)).map(\.id))
        history.removeAll { $0.projectID == projectID && !keptIDs.contains($0.id) }
        save()
    }

    func flushPersistence() async throws {
        // A fresh snapshot makes Retry use the retained current state.
        save()
        try await persistenceTask?.value
    }

    private func save() {
        let history = history
        let projects = projects
        // UserDefaults is thread-safe; the task chain orders snapshot writes.
        nonisolated(unsafe) let defaults = defaults
        let historyKey = historyKey
        let projectsKey = projectsKey
        let previous = persistenceTask
        persistenceTask = Task.detached(priority: .utility) {
            // A failed older snapshot must not prevent a newer save or retry.
            _ = await previous?.result
            let historyData = try JSONEncoder().encode(history)
            let projectsData = try JSONEncoder().encode(projects)
            defaults.set(historyData, forKey: historyKey)
            defaults.set(projectsData, forKey: projectsKey)
        }
    }

    private func saveProjects() { save() }
}
