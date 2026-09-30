import AppKit
import SwiftUI

public struct OnePlusSwitchStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            Button { configuration.isOn.toggle() } label: {
                Capsule().fill(configuration.isOn ? OnePlusColor.primaryFill : OnePlusColor.selection)
                    .overlay { Capsule().strokeBorder(OnePlusColor.line, lineWidth: 1) }
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? OnePlusColor.primaryInk : OnePlusColor.secondary)
                            .frame(width: 11, height: 11).padding(.horizontal, 3)
                    }
                    .frame(width: 29, height: 17)
                    .frame(height: 24)
            }
            .buttonStyle(OnePlusInteractionStyle(radius: 10))
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        } label: {
            configuration.label.onePlusText(.row)
        }
    }
}

public struct OnePlusSegmented<Value: Hashable>: View {
    private let choices: [(Value, String)]
    private let symbols: [Value: String]
    private let identifierPrefix: String?
    @Binding private var selection: Value
    private let label: String
    private let width: CGFloat?
    @Environment(\.onePlusDensity) private var density
    @Environment(\.onePlusControlHeight) private var controlHeight
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(choices: [(Value, String)], selection: Binding<Value>, accessibilityLabel: String = "Selection",
                accessibilityIdentifierPrefix: String? = nil, width: CGFloat? = nil) {
        self.choices = choices
        symbols = [:]
        identifierPrefix = accessibilityIdentifierPrefix
        _selection = selection
        label = accessibilityLabel
        self.width = width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    public init(iconChoices: [(Value, String, String)], selection: Binding<Value>, accessibilityLabel: String) {
        choices = iconChoices.map { ($0.0, $0.1) }
        symbols = Dictionary(uniqueKeysWithValues: iconChoices.map { ($0.0, $0.2) })
        identifierPrefix = nil
        _selection = selection
        label = accessibilityLabel
        width = nil
    }

    public static func nextSelection(in values: [Value], current: Value, direction: Int) -> Value? {
        guard !values.isEmpty else { return nil }
        let index = values.firstIndex(of: current) ?? 0
        return values[min(max(index + direction, 0), values.count - 1)]
    }

    private var labelPadding: CGFloat {
        guard !choices.isEmpty, symbols.isEmpty else { return 8 }
        let font = NSFont.systemFont(ofSize: OnePlusTextRole.control.size(for: density))
        let labelsWidth = choices.reduce(CGFloat.zero) { $0 + ceil(($1.1 as NSString).size(withAttributes: [.font: font]).width) }
        let remaining = (width ?? OnePlusMetrics.wideControlColumn) - labelsWidth - 4 - CGFloat(choices.count - 1) * 2
        return min(8, max(4, floor(remaining / CGFloat(choices.count)) / 2))
    }

    public var body: some View {
        let padding = labelPadding
        HStack(spacing: 2) {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                Button { selection = choice.0 } label: {
                    Group {
                        if let symbol = symbols[choice.0] {
                            Image(systemName: symbol).accessibilityLabel(choice.1)
                        } else {
                            Text(choice.1)
                        }
                    }.onePlusText(.control, selected: selection == choice.0)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false).padding(.horizontal, padding)
                        .frame(maxWidth: width == nil ? nil : .infinity)
                        .frame(height: (controlHeight ?? density.controlHeight) - 4)
                        .background(selection == choice.0 ? OnePlusColor.selectedControl : .clear,
                                    in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(OnePlusInteractionStyle(radius: 3, disabledOpacity: 1))
                .accessibilityAddTraits(selection == choice.0 ? .isSelected : [])
                .accessibilityIdentifier(identifierPrefix.map { "\($0).\(choice.0)" } ?? "")
                .help(choice.1)
            }
        }
        .padding(2).frame(width: width).fixedSize(horizontal: width == nil, vertical: false).frame(height: controlHeight ?? density.controlHeight)
        .background(OnePlusColor.track, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusColor.line, lineWidth: 1) }
        .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
        .animation(OnePlusMotion.animation(reduceMotion: reduceMotion, duration: OnePlusMotion.selection), value: selection)
        .onMoveCommand { direction in
            guard enabled else { return }
            let delta = direction == .left || direction == .up ? -1 : 1
            if let value = Self.nextSelection(in: choices.map(\.0), current: selection, direction: delta) { selection = value }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

public struct OnePlusSegments<Value: Hashable>: View {
    private let choices: [(Value, String)]
    @Binding private var selection: Value
    public init(choices: [(Value, String)], selection: Binding<Value>) {
        self.choices = choices
        _selection = selection
    }
    public var body: some View { OnePlusSegmented(choices: choices, selection: $selection).fixedSize() }
}

public struct OnePlusMenuLabel: View {
    let title: String
    let width: CGFloat
    let expanded: Bool
    @Environment(\.onePlusDensity) private var density
    @Environment(\.onePlusControlHeight) private var controlHeight
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    public init(title: String, width: CGFloat, expanded: Bool = false) {
        self.title = title
        self.width = width
        self.expanded = expanded
    }
    public var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 10)).accessibilityHidden(true)
        }
        .onePlusText(.control).padding(.horizontal, 10).frame(width: width, height: controlHeight ?? density.controlHeight)
        .background(enabled && (focused || hover || expanded) ? OnePlusColor.raisedHover : OnePlusColor.raised,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? OnePlusColor.focus : OnePlusColor.line, lineWidth: 1) }
        .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity).onHover { hover = $0 }
        .contentShape(Rectangle())
    }
}

public struct OnePlusSelect<Value: Hashable>: View {
    private let choices: [(Value, String)]
    @Binding private var selection: Value
    private let width: CGFloat
    private let label: String
    @Environment(\.onePlusDensity) private var density
    @FocusState private var focused: Bool
    @State private var expanded = false
    @State private var anchor = OnePlusPopupAnchorReference()
    public init(choices: [(Value, String)], selection: Binding<Value>, width: CGFloat = 160, accessibilityLabel: String) {
        self.choices = choices
        _selection = selection
        self.width = width
        label = accessibilityLabel
    }
    public var body: some View {
        Button {
            toggle()
        } label: {
            OnePlusMenuLabel(title: choices.first { $0.0 == selection }?.1 ?? "Select",
                             width: width, expanded: expanded)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .focused($focused)
        .focusEffectDisabled()
        .background { OnePlusPopupAnchor(reference: anchor) }
        .onMoveCommand { direction in
            if direction == .down, !expanded { toggle() }
        }
        .accessibilityLabel(label)
        .accessibilityValue(choices.first { $0.0 == selection }?.1 ?? "No selection")
        .accessibilityHint(expanded ? "Menu open" : "Opens menu")
        .help(choices.first { $0.0 == selection }?.1 ?? "No selection")
    }

    private func toggle() {
        let entries = popupEntries
        OnePlusPopupPresenter.shared.toggle(anchor: anchor.view, entries: entries, density: density,
                                            initialID: entries.first { $0.item?.isSelected == true }?.id) { reason in
            expanded = false
            if reason == .escape { focused = true }
        }
        expanded = OnePlusPopupPresenter.shared.isOpen(for: anchor.view)
    }

    private var popupEntries: [OnePlusPopupMenuEntry] {
        guard !choices.isEmpty else {
            return [.item(OnePlusPopupMenuItem("No options", isEnabled: false) {})]
        }
        return choices.map { choice in
            .item(OnePlusPopupMenuItem(choice.1, isSelected: choice.0 == selection) {
                selection = choice.0
            })
        }
    }
}

public struct OnePlusCheckboxStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) { configuration.label.onePlusText(.row) }
            .toggleStyle(.checkbox).tint(OnePlusColor.primaryFill)
    }
}

public struct OnePlusRadio<Value: Hashable>: View {
    let choices: [(Value, String)]
    @Binding var selection: Value
    let label: String
    public init(_ label: String, choices: [(Value, String)], selection: Binding<Value>) {
        self.label = label; self.choices = choices; _selection = selection
    }
    public var body: some View {
        Picker(label, selection: $selection) {
            ForEach(choices.indices, id: \.self) { index in Text(choices[index].1).tag(choices[index].0) }
        }.pickerStyle(.radioGroup).onePlusText(.row).tint(OnePlusColor.primaryFill)
    }
}
