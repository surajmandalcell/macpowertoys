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
            .frame(height: UtilityLayout.workspaceTitlebarHeight)
            .padding(.leading, UtilityLayout.workspaceTitleLeadingInset)
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        Color.gray.opacity(0.2)
        SidebarTitle(text: "MacPowerToys")
    }
    .frame(width: 220, height: 100)
}
