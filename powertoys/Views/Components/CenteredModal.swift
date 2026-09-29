import OnePlusUI
import SwiftUI

struct UtilityModalCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "xmark") }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .help("Close").accessibilityLabel("Close")
    }
}

struct CenteredModal<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let width: CGFloat
    let height: CGFloat
    let content: () -> Content
    init(isPresented: Binding<Bool>, title: String, width: CGFloat = 700, height: CGFloat = 550,
         @ViewBuilder content: @escaping () -> Content) {
        _isPresented = isPresented; self.title = title; self.width = width; self.height = height; self.content = content
    }
    var body: some View {
        Color.clear.allowsHitTesting(false)
            .sheet(isPresented: $isPresented) {
                OnePlusSheet(title, width: width <= 420 ? .small : width <= 560 ? .medium : .large,
                             close: { isPresented = false }) {
                    content().frame(height: max(0, height - 81))
                }
            }
    }
}
