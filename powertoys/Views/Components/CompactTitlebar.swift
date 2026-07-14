import SwiftUI

struct CompactTitlebar<Title: View, Actions: View>: View {
    let clearsTrafficLights: Bool
    let title: Title
    let actions: Actions

    init(
        clearsTrafficLights: Bool = true,
        @ViewBuilder title: () -> Title,
        @ViewBuilder actions: () -> Actions
    ) {
        self.clearsTrafficLights = clearsTrafficLights
        self.title = title()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 8) {
            title
            Spacer(minLength: 12)
            actions
        }
        .padding(.leading, clearsTrafficLights ? UtilityLayout.compactTitlebarTrafficLightInset : UtilityLayout.horizontalInset)
        .padding(.trailing, UtilityLayout.horizontalInset)
        .frame(height: UtilityLayout.compactTitlebarHeight - UtilityLayout.compactTitlebarTopInset)
        .padding(.top, UtilityLayout.compactTitlebarTopInset)
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

    var body: some View {
        Button(action: action) {
            CompactTitlebarControlLabel(isPrimary: isPrimary) {
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

struct CompactTitlebarControlLabel<Content: View>: View {
    let isPrimary: Bool
    let foregroundStyle: AnyShapeStyle
    let content: Content
    @State private var isHovering = false

    init(
        isPrimary: Bool = false,
        foregroundStyle: AnyShapeStyle? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isPrimary = isPrimary
        self.foregroundStyle = foregroundStyle
            ?? (isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        self.content = content()
    }

    var body: some View {
        content
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 9)
            .frame(height: UtilityLayout.compactTitlebarControlHeight)
            .background(
                isPrimary
                    ? Color.accentColor
                    : isHovering ? Color.primary.opacity(0.06) : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: UtilityLayout.compactTitlebarControlRadius))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}
