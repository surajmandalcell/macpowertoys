import SwiftUI

struct ColorHistoryView: View {
    @State private var service = ColorPickerService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var search = ""

    private var samples: [ColorSample] {
        guard !search.isEmpty else { return service.history }
        return service.history.filter { sample in
            ColorCopyFormat.allCases.contains { sample.string($0).localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search colors", text: $search).textFieldStyle(.plain)
                Picker("Default", selection: $service.defaultFormat) {
                    ForEach(ColorCopyFormat.allCases) { format in Text(format.title).tag(format) }
                }
                .frame(width: 120)
                Toggle("⌃⌥⌘", isOn: Binding(
                    get: { shortcuts.isColorShortcutEnabled },
                    set: shortcuts.setColorShortcutEnabled
                ))
                .toggleStyle(.checkbox)
                .contentShape(Rectangle())
                Picker("Shortcut key", selection: Binding(
                    get: { shortcuts.colorKey },
                    set: shortcuts.setColorKey
                )) {
                    ForEach(GlobalShortcutKey.allCases) { key in Text(key.title).tag(key) }
                }
                .labelsHidden()
                .frame(width: 48)
                .contentShape(Rectangle())
            }
            .padding(12)
            Divider()
            if samples.isEmpty {
                EmptyStateView(icon: "eyedropper", message: "Pick a color to add it to history")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(samples) { sample in ColorSampleRow(sample: sample) }
                    .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Image(systemName: "eyedropper")
            Text("Color Picker").font(.system(size: 13, weight: .medium))
            Spacer()
            Button("Clear", role: .destructive) { service.clearUnpinned() }
                .contentShape(Rectangle())
            Button("Pick Color") { service.pick() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ColorSampleRow: View {
    let sample: ColorSample
    @State private var service = ColorPickerService.shared
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: sample.color))
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.string(service.defaultFormat))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                Text(sample.createdAt, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(ColorCopyFormat.allCases) { format in
                    Button(format.title) { service.copy(sample, as: format) }
                }
            } label: { Image(systemName: "doc.on.doc") }
            .menuStyle(.borderlessButton)
            .contentShape(Rectangle())
            Button { service.togglePin(sample.id) } label: { Image(systemName: sample.isPinned ? "pin.fill" : "pin") }
                .contentShape(Rectangle())
                .help(sample.isPinned ? "Unpin" : "Pin")
            Button(role: .destructive) { service.remove(sample.id) } label: { Image(systemName: "trash") }
                .contentShape(Rectangle())
                .help("Delete")
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isFocused ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .focusable()
        .focused($isFocused)
        .onKeyPress(.return) {
            service.copy(sample, as: service.defaultFormat)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
            guard let number = Int(press.characters),
                  ColorCopyFormat.allCases.indices.contains(number - 1)
            else { return .ignored }
            service.copy(sample, as: ColorCopyFormat.allCases[number - 1])
            return .handled
        }
    }
}
