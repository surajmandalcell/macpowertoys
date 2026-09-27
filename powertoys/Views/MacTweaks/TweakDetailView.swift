import SwiftUI

struct MacTweaksNotice: Equatable {
    let message: String
    var actionTitle: String?
    var targetBundleIdentifier: String?
    var targetName: String?
    var isError = false
}

struct MacTweaksPanel<Content: View>: View {
    let title: String
    let glyph: MacTweaksGlyphName
    let content: Content

    init(_ title: String, glyph: MacTweaksGlyphName, @ViewBuilder content: () -> Content) {
        self.title = title
        self.glyph = glyph
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                MacTweaksGlyph(name: glyph, color: MacTweaksPalette.muted, lineWidth: 1.55)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTweaksPalette.text)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .overlay(alignment: .bottom) { Rectangle().fill(MacTweaksPalette.line).frame(height: 1) }
            content
        }
        .background {
            ZStack {
                MacTweaksPalette.panel
                MacTweaksDither(strength: 0.13)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MacTweaksPalette.line, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacTweaksPreferenceRows: View {
    let itemID: String
    let fields: [TweakPreferenceField]
    let summary: String
    let revision: Int
    let onChanged: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        ForEach(Array(fields.enumerated()), id: \.element.identity) { index, field in
            MacTweaksPreferenceRow(
                itemID: itemID,
                field: field,
                help: fields.count == 1 || index == 0 ? summary : "This companion key keeps the same behavior in alternate native dialogs.",
                revision: revision,
                onChanged: onChanged,
                onError: onError
            )
            if index < fields.count - 1 { MacTweaksRowDivider() }
        }
    }
}

struct MacTweaksPreferenceRow: View {
    let itemID: String
    let field: TweakPreferenceField
    let help: String
    let revision: Int
    let onChanged: (String) -> Void
    let onError: (String) -> Void

    @State private var isHovering = false
    @State private var showsHelp = false

    private var selection: Int { TweakPreferenceStore.shared.selectedChoice(for: field) }
    private var isModified: Bool { TweakPreferenceStore.shared.isModified(field) }
    private var canWrite: Bool {
        TweakPreferences.supportsWrites(for: itemID) || isModified
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Text(field.label)
                    .font(.system(size: 12))
                    .foregroundStyle(canWrite ? MacTweaksPalette.text.opacity(0.9) : MacTweaksPalette.muted)
                    .lineLimit(1)
                if isModified {
                    Button {
                        restore()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(MacTweaksHoverButtonStyle(cornerRadius: 5))
                    .foregroundStyle(MacTweaksPalette.secondary)
                    .help("Restore the value from before Mac Tweaks changed it")
                    .accessibilityLabel("Reset \(field.label)")
                }
                Button {
                    showsHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .regular))
                        .frame(width: 20, height: 22)
                }
                .buttonStyle(MacTweaksHoverButtonStyle(cornerRadius: 5))
                .foregroundStyle(MacTweaksPalette.muted)
                .opacity(isHovering || showsHelp ? 1 : 0)
                .popover(isPresented: $showsHelp, arrowEdge: .bottom) {
                    Text(help)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(width: 250, alignment: .leading)
                        .padding(14)
                }
                .accessibilityLabel("About \(field.label)")
            }
            Spacer(minLength: 8)
            MacTweaksChoiceControl(field: field, selection: selection, isEnabled: canWrite, onSelection: apply)
                .id("\(revision)-\(field.identity)-\(selection)")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.white.opacity(isHovering ? 0.018 : 0))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityIdentifier("mac-tweaks.setting.\(field.key)")
    }

    private func apply(_ choice: Int) {
        do {
            try TweakPreferenceStore.shared.apply([field], selections: [field.identity: choice])
            onChanged(itemID)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func restore() {
        do {
            try TweakPreferenceStore.shared.restore([field])
            onChanged(itemID)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct MacTweaksChoiceControl: View {
    let field: TweakPreferenceField
    let selection: Int
    let isEnabled: Bool
    let onSelection: (Int) -> Void

    var body: some View {
        Group {
            if field.choices.count > 20 {
                MacTweaksTimingField(field: field, selection: selection, onSelection: onSelection)
            } else if field.choices.count == 2 {
                MacTweaksSegmentedControl(field: field, selection: selection, onSelection: onSelection)
            } else {
                MacTweaksMenuControl(field: field, selection: selection, onSelection: onSelection)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct MacTweaksSegmentedControl: View {
    let field: TweakPreferenceField
    let selection: Int
    let onSelection: (Int) -> Void

    private var choices: [(Int, String)] {
        [(-1, "Default\(field.defaultLabel.map { " (\($0))" } ?? "")")] +
            field.choices.indices.map { ($0, field.choices[$0].label) }
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(choices, id: \.0) { value, label in
                Button(label) { onSelection(value) }
                    .font(.system(size: 10.5, weight: value == selection ? .medium : .regular))
                    .foregroundStyle(value == selection ? MacTweaksPalette.text : MacTweaksPalette.secondary)
                    .lineLimit(1)
                    .frame(width: value == -1 ? 92 : 30, height: 24)
                    .background(value == selection ? Color.white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityAddTraits(value == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(width: 160, height: 28)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(MacTweaksPalette.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.13), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(field.label)
    }
}

private struct MacTweaksMenuControl: View {
    let field: TweakPreferenceField
    let selection: Int
    let onSelection: (Int) -> Void

    private var valueLabel: String {
        if selection == -1 { return "Default\(field.defaultLabel.map { " (\($0))" } ?? "")" }
        if field.choices.indices.contains(selection) { return field.choices[selection].label }
        return "Current value"
    }

    var body: some View {
        Menu {
            Button("System default") { onSelection(-1) }
            Divider()
            ForEach(field.choices.indices, id: \.self) { index in
                Button(field.choices[index].label) { onSelection(index) }
            }
        } label: {
            HStack(spacing: 7) {
                Text(valueLabel).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .medium))
            }
            .font(.system(size: 11))
            .foregroundStyle(MacTweaksPalette.secondary)
            .padding(.horizontal, 10)
            .frame(width: 160, height: 28)
            .background(MacTweaksPalette.panelRaised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(MacTweaksPalette.line, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(field.label)
        .accessibilityValue(valueLabel)
    }
}

private struct MacTweaksTimingField: View {
    let field: TweakPreferenceField
    let selection: Int
    let onSelection: (Int) -> Void

    @FocusState private var isFocused: Bool
    @State private var text = ""

    private var selectedValue: Double? {
        guard field.choices.indices.contains(selection) else { return nil }
        return field.choices[selection].value as? Double
    }

    var body: some View {
        HStack(spacing: 0) {
            TextField(defaultPlaceholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit(submit)
                .onChange(of: isFocused) { wasFocused, focused in
                    if wasFocused && !focused { submit() }
                }
                .padding(.leading, 8)
            Text("s")
                .font(.system(size: 10))
                .foregroundStyle(MacTweaksPalette.muted)
                .padding(.horizontal, 5)
            VStack(spacing: 0) {
                stepButton("plus", amount: 0.05)
                Rectangle().fill(MacTweaksPalette.line).frame(height: 1)
                stepButton("minus", amount: -0.05)
            }
            .frame(width: 20)
            .overlay(alignment: .leading) { Rectangle().fill(MacTweaksPalette.line).frame(width: 1) }
        }
        .frame(width: 160, height: 28)
        .background(MacTweaksPalette.panelRaised, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(MacTweaksPalette.line, lineWidth: 1))
        .onAppear(perform: sync)
        .onChange(of: selection) { _, _ in if !isFocused { sync() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(field.label)
    }

    private var defaultPlaceholder: String {
        "Default\(field.defaultLabel.map { " (\($0.replacingOccurrences(of: " seconds", with: "")))" } ?? "")"
    }

    private func stepButton(_ symbol: String, amount: Double) -> some View {
        Button {
            let baseline = selectedValue ?? field.defaultLabel.flatMap(parse) ?? 0
            choose(min(3, max(0, baseline + amount)))
        } label: {
            Image(systemName: symbol).font(.system(size: 7, weight: .medium)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacTweaksPalette.secondary)
        .focusEffectDisabled()
        .accessibilityLabel(symbol == "plus" ? "Increase \(field.label)" : "Decrease \(field.label)")
    }

    private func sync() {
        text = selectedValue.map { String(format: "%.2f", $0) } ?? ""
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { onSelection(-1); return }
        guard let value = parse(trimmed), value >= 0, value <= 3 else { sync(); return }
        choose(value)
    }

    private func choose(_ value: Double) {
        let index = field.choices.indices.min { lhs, rhs in
            abs((field.choices[lhs].value as? Double ?? 0) - value) < abs((field.choices[rhs].value as? Double ?? 0) - value)
        }
        if let index { onSelection(index) }
    }

    private func parse(_ value: String) -> Double? {
        Double(value.components(separatedBy: .whitespaces).first ?? value)
    }
}

struct MacTweaksToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color(white: 0.847) : Color(white: 0.216))
                    .overlay {
                        Capsule().stroke(
                            configuration.isOn ? Color(white: 0.847) : Color(white: 0.282),
                            lineWidth: 1
                        )
                    }
                Circle()
                    .fill(configuration.isOn ? Color(white: 0.161) : Color(white: 0.667))
                    .frame(width: 12, height: 12)
                    .offset(x: configuration.isOn ? 14 : 2)
            }
            .frame(width: 30, height: 18)
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct MacTweaksHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        MacTweaksHoverButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct MacTweaksHoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @State private var hovering = false

    var body: some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : hovering ? 0.055 : 0), in: RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct MacTweaksRowDivider: View {
    var body: some View {
        Rectangle().fill(MacTweaksPalette.line).frame(height: 1).padding(.leading, 16)
    }
}

enum MacTweaksPreferenceValue {
    static func label(for selection: Int, field: TweakPreferenceField) -> String {
        if selection == -1 { return "System default\(field.defaultLabel.map { " (\($0))" } ?? "")" }
        if field.choices.indices.contains(selection) { return field.choices[selection].label }
        return "Custom value"
    }
}
