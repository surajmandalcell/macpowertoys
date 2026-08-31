//
//  SidebarRow.swift
//  powertoys
//

import SwiftUI

struct SidebarRow: View {
    let icon: String
    let title: String
    var isSelected: Bool = false
    var logoAsset: String? = nil
    let action: () -> Void

    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let logoAsset, !logoAsset.isEmpty {
                    Image(logoAsset)
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .toolIconTile(size: 16)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(foregroundColor)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(minHeight: UtilityLayout.sidebarRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle())
        .focusEffectDisabled()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectionColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var selectionColor: Color {
        guard isSelected else { return .clear }
        return Color(nsColor: controlActiveState == .inactive
            ? .unemphasizedSelectedContentBackgroundColor
            : .selectedContentBackgroundColor)
    }

    private var foregroundColor: Color {
        guard isSelected else { return .primary }
        return Color(nsColor: controlActiveState == .inactive
            ? .unemphasizedSelectedTextColor
            : .alternateSelectedControlTextColor)
    }
}

struct SidebarExternalRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: UtilityLayout.sidebarRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle())
        .focusEffectDisabled()
    }
}

#Preview {
    VStack(spacing: 4) {
        SidebarRow(icon: "square.grid.2x2", title: "All Tools", isSelected: true) {}
        SidebarRow(icon: "gearshape", title: "Settings") {}
        SidebarExternalRow(icon: "doc.text", title: "Open Logs") {}
    }
    .padding()
    .frame(width: 220)
    .background(Color.gray.opacity(0.1))
}
