import AppKit
import Observation
import UniformTypeIdentifiers

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
    var defaultFormat: ColorCopyFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: formatKey) }
    }

    private let sampler = NSColorSampler()
    private let defaults: UserDefaults
    private let historyKey = "color-picker.history.v1"
    private let projectsKey = "color-picker.projects.v1"
    private let selectedProjectKey = "color-picker.selected-project.v1"
    private let formatKey = "color-picker.format.v1"
    private let maximumHistory = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        NSApp.activate(ignoringOtherApps: true)
        sampler.show { [weak self] color in
            guard let self, let color, let converted = color.usingColorSpace(.sRGB) else { return }
            let sample = ColorSample(
                    red: converted.redComponent,
                    green: converted.greenComponent,
                    blue: converted.blueComponent,
                    alpha: converted.alphaComponent
                )
            Task { @MainActor [self, sample] in
                self.add(sample)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sample.string(format), forType: .string)
    }

    func copyLast() {
        guard let sample = history.first else { return }
        copy(sample, as: defaultFormat)
    }

    func togglePin(_ id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].isPinned.toggle()
        save()
    }

    func remove(_ id: UUID) {
        history.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned(in projectID: UUID?) {
        history.removeAll { $0.projectID == projectID && !$0.isPinned }
        save()
    }

    @discardableResult
    func createProject(named name: String) -> ColorProject? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !projects.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        let project = ColorProject(name: name)
        projects.append(project)
        saveProjects()
        selectProject(project.id)
        return project
    }

    func selectProject(_ id: UUID?) {
        guard id == nil || projects.contains(where: { $0.id == id }) else { return }
        selectedProjectID = id
    }

    func samples(in projectID: UUID?) -> [ColorSample] {
        history.filter { $0.projectID == projectID }
    }

    func export(_ project: ColorProject) {
        let content = Self.css(for: samples(in: project.id))
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.css]
        panel.nameFieldStringValue = "\(project.name).css"
        panel.message = "Export \(project.name) colors as CSS"
        panel.begin { [weak self] response in
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

    private func save() {
        defaults.set(try? JSONEncoder().encode(history), forKey: historyKey)
    }

    private func saveProjects() {
        defaults.set(try? JSONEncoder().encode(projects), forKey: projectsKey)
    }
}
