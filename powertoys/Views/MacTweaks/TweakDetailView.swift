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
    let content: Content

    init(_ title: String, glyph: MacTweaksGlyphName, @ViewBuilder content: () -> Content) {
        self.title = title
        self.glyph = glyph
        self.content = content()
    }

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader(title, systemImage: glyph.systemImage)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacTweaksPreferenceRows: View {
    let itemID: String
    let fields: [TweakPreferenceField]
    let summary: String
    let revision: Int
    let selections: [String: Int]
    let modifiedIdentities: Set<String>
    let onChanged: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        let controlWidth = fields.contains { $0.choices.count == 2 }
            ? OnePlusMetrics.wideControlColumn
            : OnePlusMetrics.controlColumn
        ForEach(Array(fields.enumerated()), id: \.element.identity) { index, field in
            MacTweaksPreferenceRow(
                itemID: itemID,
                field: field,
                controlWidth: controlWidth,
                help: fields.count == 1 || index == 0 ? summary : "This companion key keeps the same behavior in alternate native dialogs.",
                revision: revision,
                selection: selections[field.identity] ?? -1,
                isModified: modifiedIdentities.contains(field.identity),
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
    let controlWidth: CGFloat
    let help: String
    let revision: Int
    let selection: Int
    let isModified: Bool
    let onChanged: (String) -> Void
    let onError: (String) -> Void

    private var canWrite: Bool {
        TweakPreferences.supportsWrites(for: itemID) || isModified
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
            separator: false
        ) {
            MacTweaksChoiceControl(field: field, selection: selection, isEnabled: canWrite, onSelection: apply)
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
        .opacity(isEnabled ? 1 : OnePlusMetrics.disabledOpacity)
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
        OnePlusSegmented(
            choices: choices,
            selection: Binding(get: { selection }, set: onSelection),
            accessibilityLabel: field.label
        )
    }
}

private struct MacTweaksMenuControl: View {
    let field: TweakPreferenceField
    let selection: Int
    let onSelection: (Int) -> Void

    var body: some View {
        OnePlusSelect(
            choices: [(-1, "System default")] + field.choices.indices.map { ($0, field.choices[$0].label) },
            selection: Binding(get: { selection }, set: onSelection),
            accessibilityLabel: field.label
        )
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

    var body: some View {
        OnePlusStepperField(
            field.label,
            value: Binding(
                get: { Int(((selectedValue ?? 0) * 100).rounded()) },
                set: { choose(Double($0) / 100) }
            ),
            in: 0...300,
            step: 5,
            unit: "cs"
        )
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
        if selection == -1 { return "System default\(field.defaultLabel.map { " (\($0))" } ?? "")" }
        if field.choices.indices.contains(selection) { return field.choices[selection].label }
        return "Custom value"
    }
}
