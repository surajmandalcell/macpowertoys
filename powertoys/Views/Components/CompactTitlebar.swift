import SwiftUI

struct CompactTitlebar<Title: View, Actions: View>: View {
    let clearsTrafficLights: Bool
    let showsBottomSeparator: Bool
    let title: Title
    let actions: Actions

    init(
        clearsTrafficLights: Bool = true,
        showsBottomSeparator: Bool = true,
        @ViewBuilder title: () -> Title,
        @ViewBuilder actions: () -> Actions
    ) {
        self.clearsTrafficLights = clearsTrafficLights
        self.showsBottomSeparator = showsBottomSeparator
        self.title = title()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 12)
                actions
            }
            .padding(.leading, clearsTrafficLights ? UtilityLayout.compactTitlebarTrafficLightInset : UtilityLayout.horizontalInset)
            .padding(.trailing, UtilityLayout.horizontalInset)
            .frame(height: UtilityLayout.compactTitlebarHeight - (showsBottomSeparator ? 1 : 0))

            if showsBottomSeparator {
                Divider()
            }
        }
    }
}

struct CompactTitlebarTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
    }
}

struct CompactTitlebarButton: View {
    let title: String
    var isPrimary = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(isPrimary ? Color.accentColor : isHovering ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}

struct CompactTitlebarIconButton: View {
    let systemName: String
    let helpText: String
    let action: () -> Void
    @State private var isHovering = false

    init(systemName: String, help: String, action: @escaping () -> Void) {
        self.systemName = systemName
        helpText = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .help(helpText)
    }
}
