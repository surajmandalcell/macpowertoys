import SwiftUI

extension View {
    func utilitySectionHeader() -> some View {
        font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    func utilitySectionCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
