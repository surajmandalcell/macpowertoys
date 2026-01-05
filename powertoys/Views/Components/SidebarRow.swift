//
//  SidebarRow.swift
//  powertoys
//

import SwiftUI

struct SidebarRow: View {
    let icon: String
    let title: String
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected { return .accentColor }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

struct SidebarExternalRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
