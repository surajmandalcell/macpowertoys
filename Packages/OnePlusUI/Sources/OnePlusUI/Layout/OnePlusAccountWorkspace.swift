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

/// Existing SwiftUI menu commands use the shared action trigger and popup.
public struct OnePlusActionMenu<Content: View>: View {
    let title: String
    let content: Content
    /// The legacy width argument remains valid. Action triggers fit their label.
    public init(_ title: String, width: CGFloat = OnePlusMetrics.controlColumn,
                @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    public var body: some View {
        OnePlusMenuButton(title) { OnePlusHostedActionMenu.entries(content) }
    }
}

@MainActor
enum OnePlusHostedActionMenu {
    static func entries<Content: View>(_ content: Content) -> [OnePlusPopupMenuEntry] {
        let menu = NSHostingMenu(rootView: content)
        menu.update()
        return entries(menu, root: menu)
    }
    private static func entries(_ menu: NSMenu, root: NSMenu, enabled: Bool = true) -> [OnePlusPopupMenuEntry] {
        menu.items.filter { !$0.isHidden }.flatMap { item in
            if item.isSeparatorItem { return [OnePlusPopupMenuEntry.separator()] }
            if item.isSectionHeader { return [.section(item.title)] }
            if let submenu = item.submenu {
                // ponytail: submenus are section groups until the popup supports nested navigation.
                return [.section(item.title)] + entries(submenu, root: root, enabled: enabled && item.isEnabled)
            }
            return [.item(OnePlusPopupMenuItem(item.title, isEnabled: enabled && item.isEnabled,
                                             isSelected: item.state == .on) {
                withExtendedLifetime(root) {
                    if let action = item.action { NSApplication.shared.sendAction(action, to: item.target, from: item) }
                }
            })]
        }
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
    func onePlusNativeTable(columns: [OnePlusGridColumn] = []) -> some View {
        modifier(OnePlusNativeTableSkin(columns: columns))
    }
}

public struct OnePlusSecureField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    public init(_ title: String, text: Binding<String>) { self.title = title; _text = text }
    public static func focusedOnOpen(_ title: String, text: Binding<String>) -> Self {
        Self(title, text: text)
    }
    public var body: some View {
        SecureField(title, text: $text).textFieldStyle(.plain).onePlusText(.control)
            .focused($focused).padding(.horizontal, 8).frame(height: OnePlusMetrics.controlHeight)
            .background(focused && OnePlusFocusPolicy.shared.showsFocus ? OnePlusColor.fieldFocus : OnePlusColor.field,
                        in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                .strokeBorder(focused && OnePlusFocusPolicy.shared.showsFocus ? OnePlusColor.focus : OnePlusColor.line, lineWidth: 1) }
            .accessibilityLabel(title)
    }
}

/// Original provider art keeps its white backing in either app appearance.
public struct OnePlusProviderTile<Content: View>: View {
    let size: CGFloat
    let content: Content
    public init(size: CGFloat, @ViewBuilder content: () -> Content) {
        self.size = size; self.content = content()
    }
    public var body: some View {
        content.padding(size / 8).frame(width: size, height: size)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 3))
    }
}
