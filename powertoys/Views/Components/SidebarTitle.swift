//
//  SidebarTitle.swift
//  powertoys
//

import SwiftUI

struct SidebarTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .padding(.leading, 84)
            .padding(.top, 8)
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        Color.gray.opacity(0.2)
        SidebarTitle(text: "MacPowerToys")
    }
    .frame(width: 220, height: 100)
}
