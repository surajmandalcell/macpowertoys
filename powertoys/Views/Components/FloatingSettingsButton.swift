import SwiftUI

struct FloatingSettingsButton: View {
    let isActive: Bool
    let helpText: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "gearshape.fill" : "gearshape")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .help(helpText)
        .padding(.leading, UtilityLayout.horizontalInset)
        .padding(.bottom, UtilityLayout.contentBottomInset)
    }

    private var background: Color {
        if isActive { return Color.accentColor.opacity(0.1) }
        return Color.primary.opacity(isHovering ? 0.06 : 0.03)
    }
}
