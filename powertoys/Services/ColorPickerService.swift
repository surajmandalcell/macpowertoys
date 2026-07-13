import AppKit
import Observation

@Observable
@MainActor
final class ColorPickerService {
    static let shared = ColorPickerService()

    private(set) var history: [ColorSample]
    var defaultFormat: ColorCopyFormat {
        didSet { UserDefaults.standard.set(defaultFormat.rawValue, forKey: formatKey) }
    }

    private let sampler = NSColorSampler()
    private let historyKey = "color-picker.history.v1"
    private let formatKey = "color-picker.format.v1"
    private let maximumHistory = 100

    private init() {
        history = UserDefaults.standard.data(forKey: historyKey)
            .flatMap { try? JSONDecoder().decode([ColorSample].self, from: $0) } ?? []
        defaultFormat = UserDefaults.standard.string(forKey: formatKey)
            .flatMap(ColorCopyFormat.init(rawValue:)) ?? .hex
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
        let wasPinned = history.first { $0.matches(sample) }?.isPinned ?? false
        history.removeAll { $0.matches(sample) }
        var latest = sample
        latest.isPinned = wasPinned
        history.insert(latest, at: 0)
        trimAndSave()
        copy(sample, as: defaultFormat)
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

    func clearUnpinned() {
        history.removeAll { !$0.isPinned }
        save()
    }

    private func trimAndSave() {
        let pinned = history.filter(\.isPinned)
        let recent = history.filter { !$0.isPinned }.prefix(max(0, maximumHistory - pinned.count))
        history = pinned + Array(recent)
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: historyKey)
    }
}
