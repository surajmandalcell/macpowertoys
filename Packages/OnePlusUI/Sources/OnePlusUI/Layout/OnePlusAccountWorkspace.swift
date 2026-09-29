import AppKit
import SwiftUI

/// A two-line sidebar row for saved accounts.
public struct OnePlusAccountNavRow<Icon: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let isDefault: Bool
    let icon: Icon
    let action: () -> Void

    public init(_ title: String, subtitle: String, selected: Bool, isDefault: Bool,
                @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.title = title; self.subtitle = subtitle; self.selected = selected
        self.isDefault = isDefault; self.icon = icon(); self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.frame(width: 15, height: 15).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).onePlusText(.nav, selected: selected).lineLimit(1)
                    Text(subtitle).onePlusText(.caption).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark").onePlusText(.caption)
                    .opacity(isDefault ? 1 : 0).accessibilityHidden(true)
            }.padding(.horizontal, 10).frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(selected: selected))
        .help(title + " · " + subtitle + (isDefault ? " · Default" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(isDefault ? "Default account" : "Saved account")
    }
}

/// Native action menus use the same trigger as selection menus.
public struct OnePlusActionMenu<Content: View>: View {
    let title: String
    let width: CGFloat
    let content: Content
    public init(_ title: String, width: CGFloat = OnePlusMetrics.controlColumn,
                @ViewBuilder content: () -> Content) {
        self.title = title; self.width = width; self.content = content()
    }
    public var body: some View {
        Menu { content } label: { OnePlusMenuLabel(title: title, width: width) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
            .accessibilityLabel(title)
    }
}

/// Compact facts within one card, separated by the caller's card divider.
public struct OnePlusStatCell: View {
    let title: String
    let value: String
    public init(_ title: String, value: String) { self.title = title; self.value = value }
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).onePlusText(.caption).lineLimit(1).help(title)
            Text(value).onePlusText(.cardTitle).lineLimit(2).help(value)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .accessibilityElement(children: .combine)
    }
}

public struct OnePlusRule: View {
    let vertical: Bool
    public init(vertical: Bool = false) { self.vertical = vertical }
    public var body: some View {
        OnePlusColor.lineSoft.frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

public extension View {
    func onePlusNativeTable() -> some View {
        self.tableStyle(.inset(alternatesRowBackgrounds: false))
            .environment(\.defaultMinListRowHeight, OnePlusTable.rowHeight(.regular))
            .scrollContentBackground(.hidden).background(OnePlusColor.panel)
            .onePlusText(.row).onePlusScrollIndicators()
    }
}

public struct OnePlusSecureField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    public init(_ title: String, text: Binding<String>) { self.title = title; _text = text }
    public var body: some View {
        SecureField(title, text: $text).textFieldStyle(.plain).onePlusText(.control)
            .focused($focused).padding(.horizontal, 8).frame(height: OnePlusMetrics.controlHeight)
            .background(focused ? OnePlusColor.fieldFocus : OnePlusColor.field,
                        in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                .strokeBorder(focused ? OnePlusColor.focus : OnePlusColor.line, lineWidth: 1) }
            .accessibilityLabel(title)
    }
}
