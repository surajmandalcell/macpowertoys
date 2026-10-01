import OnePlusUI
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
    let fillsHeight: Bool
    let content: Content

    init(_ title: String, glyph: MacTweaksGlyphName, fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.glyph = glyph
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        OnePlusCard {
            VStack(alignment: .leading, spacing: 0) {
                OnePlusCardHeader(title, systemImage: glyph.systemImage)
                content
            }
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacTweaksPreferenceRows: View {
    let itemID: String
    let fields: [TweakPreferenceField]
    let controlWidth: CGFloat
    let separator: Bool
    let summary: String
    let revision: Int
    let selections: [String: Int]
    let modifiedIdentities: Set<String>
    let backedUpIdentities: Set<String>
    let onChanged: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        ForEach(Array(fields.enumerated()), id: \.element.identity) { index, field in
            MacTweaksPreferenceRow(
                itemID: itemID,
                field: field,
                controlWidth: controlWidth,
                separator: separator || index < fields.count - 1,
                help: fields.count == 1 || index == 0 ? summary : "This companion key keeps the same behavior in alternate native dialogs.",
                revision: revision,
                selection: selections[field.identity] ?? -3,
                isModified: modifiedIdentities.contains(field.identity),
                hasBackup: backedUpIdentities.contains(field.identity),
                onChanged: onChanged,
                onError: onError
            )
        }
    }
}

struct MacTweaksPreferenceRow: View {
    let itemID: String
    let field: TweakPreferenceField
    let controlWidth: CGFloat
    let separator: Bool
    let help: String
    let revision: Int
    let selection: Int
    let isModified: Bool
    let hasBackup: Bool
    let onChanged: (String) -> Void
    let onError: (String) -> Void

    private var canWrite: Bool {
        TweakPreferences.supportsWrites(for: itemID)
    }
    private var resetAction: (() -> Void)? {
        isModified ? { restore() } : nil
    }

    var body: some View {
        OnePlusSettingRow(
            field.label,
            help: help,
            reset: resetAction,
            controlWidth: controlWidth,
            separator: separator
        ) {
            MacTweaksChoiceControl(field: field, selection: selection, controlWidth: controlWidth, isEnabled: canWrite, onSelection: apply)
        }
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
            try TweakPreferenceStore.shared.restore([field], includingUntracked: !hasBackup)
            onChanged(itemID)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct MacTweaksChoiceControl: View {
    let field: TweakPreferenceField
    let selection: Int
    let controlWidth: CGFloat
    let isEnabled: Bool
    let onSelection: (Int) -> Void

    var body: some View {
        Group {
            if selection == -3 {
                Text("Loading…").onePlusText(.caption).frame(width: controlWidth, alignment: .trailing)
            } else if field.choices.count > 20 {
                MacTweaksTimingField(field: field, selection: selection, onSelection: onSelection)
                    .frame(width: controlWidth)
            } else if field.choices.count == 2 && selection != -2 {
                MacTweaksSegmentedControl(field: field, selection: selection, controlWidth: controlWidth, onSelection: onSelection)
            } else {
                MacTweaksMenuControl(field: field, selection: selection, controlWidth: controlWidth, onSelection: onSelection)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : OnePlusMetrics.disabledOpacity)
    }
}

private struct MacTweaksSegmentedControl: View {
    let field: TweakPreferenceField
    let selection: Int
    let controlWidth: CGFloat
    let onSelection: (Int) -> Void
    private var choices: [(Int, String)] {
        [(-1, "Default\(field.defaultLabel.map { " (\($0))" } ?? "")")] +
            field.choices.indices.map { ($0, field.choices[$0].label) }
    }

    var body: some View {
        OnePlusSegmented(
            choices: choices,
            selection: Binding(get: { selection }, set: onSelection),
            accessibilityLabel: field.label,
            accessibilityIdentifierPrefix: "mac-tweaks.choice.\(field.key)",
            width: controlWidth
        )
    }
}

private struct MacTweaksMenuControl: View {
    let field: TweakPreferenceField
    let selection: Int
    let controlWidth: CGFloat
    let onSelection: (Int) -> Void

    var body: some View {
        OnePlusSelect(
            choices: (selection == -2 ? [(-2, "Custom value")] : [])
                + [(-1, defaultLabel)] + field.choices.indices.map { ($0, field.choices[$0].label) },
            selection: Binding(get: { selection }, set: { if $0 >= -1 { onSelection($0) } }),
            width: controlWidth,
            accessibilityLabel: field.label
        )
    }

    private var defaultLabel: String {
        "Default\(field.defaultLabel.map { " (\($0))" } ?? "")"
    }
}

private struct MacTweaksTimingField: View {
    let field: TweakPreferenceField
    let selection: Int
    let onSelection: (Int) -> Void

    private var selectedValue: Double? {
        guard field.choices.indices.contains(selection) else { return nil }
        return field.choices[selection].value as? Double
    }

    private var defaultValue: Double {
        guard let index = field.defaultSelection,
              field.choices.indices.contains(index),
              let value = field.choices[index].value as? Double
        else { return 0 }
        return value
    }

    private var hundredths: Binding<Int> {
        Binding(
            get: { Int(((selectedValue ?? defaultValue) * 100).rounded()) },
            set: { choose(Double($0) / 100) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(selection == -2 ? "Custom value" : selectedValue.map { String(format: "%.2f", $0) }
                 ?? "Default (\(field.defaultLabel ?? String(format: "%.2f", defaultValue)))")
                .onePlusText(.control)
                .padding(.horizontal, OnePlusMetrics.spacing[3])
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("s").onePlusText(.caption).padding(.trailing, OnePlusMetrics.spacing[3])
            OnePlusColor.line.frame(width: 1)
            Stepper(field.label, value: hundredths, in: 0...300, step: 5)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: OnePlusMetrics.spacing[7])
                .clipped()
        }
        .frame(height: OnePlusMetrics.controlHeight)
        .background(OnePlusColor.field, in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                .strokeBorder(OnePlusColor.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(field.label)
        .accessibilityValue(selection == -2 ? "Custom value" : selectedValue.map { String(format: "%.2f seconds", $0) }
                            ?? "Default, \(field.defaultLabel ?? String(format: "%.2f", defaultValue)) seconds")
    }

    private func choose(_ value: Double) {
        let index = field.choices.indices.min { lhs, rhs in
            abs((field.choices[lhs].value as? Double ?? 0) - value) < abs((field.choices[rhs].value as? Double ?? 0) - value)
        }
        if let index { onSelection(index) }
    }

}

struct MacTweaksRowDivider: View {
    var body: some View {
        Rectangle().fill(OnePlusColor.lineSoft).frame(height: 1).padding(.leading, OnePlusMetrics.cardPadding)
    }
}

enum MacTweaksPreferenceValue {
    static func label(for selection: Int, field: TweakPreferenceField) -> String {
        if selection == -1 { return "Default\(field.defaultLabel.map { " (\($0))" } ?? "")" }
        if field.choices.indices.contains(selection) { return field.choices[selection].label }
        return "Custom value"
    }
}
