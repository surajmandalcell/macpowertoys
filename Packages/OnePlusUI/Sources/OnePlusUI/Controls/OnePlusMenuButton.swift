import SwiftUI

/// A native action menu with the shared neutral or ghost trigger.
public struct OnePlusMenuButton<Label: View, Content: View>: View {
    public enum Variant { case neutral, ghost }
    let variant: Variant
    let label: Label
    let content: Content
    public init(variant: Variant = .ghost, @ViewBuilder content: () -> Content,
                @ViewBuilder label: () -> Label) {
        self.variant = variant; self.label = label(); self.content = content()
    }
    public var body: some View {
        Menu { content } label: { label }
        .menuStyle(.button)
        .buttonStyle(OnePlusButtonStyle(variant == .ghost ? .ghost : .neutral))
        .menuIndicator(.hidden)
        .onePlusNeutralControls().fixedSize()
        .focusEffectDisabled()
    }
}

public extension OnePlusMenuButton where Label == Text {
    init(_ title: String, variant: Variant = .ghost, @ViewBuilder content: () -> Content) {
        self.init(variant: variant, content: content, label: { Text(title) })
    }
}
