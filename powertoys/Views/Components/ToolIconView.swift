import SwiftUI

struct ToolIconView: View {
    let tool: any Tool
    var size: CGFloat

    var body: some View {
        Group {
            if let iconFileURL = tool.iconFileURL {
                AsyncImage(url: iconFileURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    symbolIcon
                }
                .clipShape(RoundedRectangle(cornerRadius: size <= 24 ? 4 : 8))
            } else if tool.logoAsset.isEmpty {
                symbolIcon
            } else {
                Image(tool.logoAsset)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }

    private var symbolIcon: some View {
        Image(systemName: tool.icon)
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: size <= 24 ? 4 : 8))
    }
}
