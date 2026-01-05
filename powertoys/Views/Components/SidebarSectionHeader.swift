//
//  SidebarSectionHeader.swift
//  powertoys
//

import SwiftUI

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

#Preview {
    VStack(alignment: .leading) {
        SidebarSectionHeader(title: "Dev Tools")
        SidebarSectionHeader(title: "Utilities")
    }
    .frame(width: 200)
}
