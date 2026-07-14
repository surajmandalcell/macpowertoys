import SwiftUI

struct ColorHistoryView: View {
    @State private var service = ColorPickerService.shared
    @State private var search = ""

    private var samples: [ColorSample] {
        guard !search.isEmpty else { return service.history }
        return service.history.filter { sample in
            ColorCopyFormat.allCases.contains { sample.string($0).localizedCaseInsensitiveContains(search) }
        }
    }

    private var windowHeight: CGFloat {
        260 + CGFloat(max(0, min(samples.count, 5) - 1) * 56)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            if samples.isEmpty {
                EmptyStateView(icon: "eyedropper", message: "Pick a color to add it to history")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(samples) { sample in
                            ColorSampleRow(sample: sample)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 520, height: windowHeight)
        .background(VisualEffectBackground(material: .hudWindow))
        .animation(.easeInOut(duration: 0.16), value: samples.count)
    }

    private var header: some View {
        HStack {
            Image(systemName: "eyedropper")
                .foregroundStyle(Color.accentColor)
            Text("Color Picker").font(.system(size: 13, weight: .medium))
            Spacer()
            GlobalShortcutMenu(action: .colorPicker)
            if !service.history.isEmpty {
                Button("Clear", role: .destructive) { service.clearUnpinned() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .contentShape(Rectangle())
            }
            Button("Pick Color") { service.pick() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search colors", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("Copy format", selection: $service.defaultFormat) {
                ForEach(ColorCopyFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(12)
    }
}

private struct ColorSampleRow: View {
    let sample: ColorSample
    @State private var service = ColorPickerService.shared
    @State private var isHovering = false
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
        .padding(10)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(isHovering ? 0.1 : 0), radius: 6, y: 2)
        .focusable()
        .focused($isFocused)
        .onHover { isHovering = $0 }
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

    private var rowBackground: Color {
        if isFocused { return Color.accentColor.opacity(0.1) }
        return Color.primary.opacity(isHovering ? 0.06 : 0.03)
    }
}
