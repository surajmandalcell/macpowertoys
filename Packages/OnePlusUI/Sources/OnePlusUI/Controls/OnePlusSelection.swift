import AppKit
import SwiftUI

public struct OnePlusSwitchStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.onePlusText(.row)
            Spacer(minLength: 8)
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
        }
    }
}

public struct OnePlusSegmented<Value: Hashable>: View {
    private let choices: [(Value, String)]
    @Binding private var selection: Value
    private let label: String
    @Environment(\.onePlusDensity) private var density
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(choices: [(Value, String)], selection: Binding<Value>, accessibilityLabel: String = "Selection") {
        self.choices = choices
        _selection = selection
        label = accessibilityLabel
    }

    public static func nextSelection(in values: [Value], current: Value, direction: Int) -> Value? {
        guard !values.isEmpty else { return nil }
        let index = values.firstIndex(of: current) ?? 0
        return values[min(max(index + direction, 0), values.count - 1)]
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                Button { selection = choice.0 } label: {
                    Text(choice.1).onePlusText(.control, selected: selection == choice.0)
                        .lineLimit(1).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity).frame(height: density.controlHeight - 4)
                        .background(selection == choice.0 ? OnePlusColor.selectedControl : .clear,
                                    in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(OnePlusInteractionStyle(radius: 3))
                .accessibilityAddTraits(selection == choice.0 ? .isSelected : [])
            }
        }
        .padding(2).frame(height: density.controlHeight)
        .background(OnePlusColor.track, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusColor.line, lineWidth: 1) }
        .animation(OnePlusMotion.animation(reduceMotion: reduceMotion, duration: OnePlusMotion.selection), value: selection)
        .onMoveCommand { direction in
            guard enabled else { return }
            let delta = direction == .left || direction == .up ? -1 : 1
            if let value = Self.nextSelection(in: choices.map(\.0), current: selection, direction: delta) { selection = value }
        }
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(choices.indices, id: \.self) { index in Text(choices[index].1).tag(choices[index].0) }
            }.pickerStyle(.segmented)
        }
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
    @Environment(\.onePlusDensity) private var density
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    public init(title: String, width: CGFloat) { self.title = title; self.width = width }
    public var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 10)).accessibilityHidden(true)
        }
        .onePlusText(.control).padding(.horizontal, 10).frame(width: width, height: density.controlHeight)
        .background(enabled && (focused || hover) ? OnePlusColor.raisedHover : OnePlusColor.raised,
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
    public init(choices: [(Value, String)], selection: Binding<Value>, width: CGFloat = 160, accessibilityLabel: String) {
        self.choices = choices
        _selection = selection
        self.width = width
        label = accessibilityLabel
    }
    public var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(choices.indices, id: \.self) { index in Text(choices[index].1).tag(choices[index].0) }
            }
            if choices.isEmpty { Text("No options") }
        } label: {
            OnePlusMenuLabel(title: choices.first { $0.0 == selection }?.1 ?? "Select", width: width)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
        .accessibilityLabel(label)
        .accessibilityValue(choices.first { $0.0 == selection }?.1 ?? "No selection")
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
