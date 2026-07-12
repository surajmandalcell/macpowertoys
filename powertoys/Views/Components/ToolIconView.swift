import SwiftUI

struct ToolIconView: View {
    let tool: any Tool
    var size: CGFloat

    var body: some View {
        Group {
            if tool.logoAsset.isEmpty {
                Image(systemName: tool.icon)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.primary)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: size <= 24 ? 4 : 8))
            } else {
                Image(tool.logoAsset)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}
