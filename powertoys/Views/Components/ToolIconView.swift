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
            } else if tool.logoAsset.isEmpty {
                symbolIcon
            } else {
                Image(tool.logoAsset)
                    .resizable()
                    .scaledToFit()
            }
        }
        .toolIconTile(size: size)
    }

    private var symbolIcon: some View {
        Image(systemName: tool.icon)
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.06))
    }
}

extension View {
    func toolIconTile(size: CGFloat) -> some View {
        frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 112 / 512))
    }
}
