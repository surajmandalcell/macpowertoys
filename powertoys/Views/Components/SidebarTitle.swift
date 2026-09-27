//
//  SidebarTitle.swift
//  powertoys
//

import OnePlusUI
import SwiftUI

struct SidebarTitle: View {
    let text: String

    var body: some View {
        OnePlusSidebarTitle(
            text,
            height: UtilityLayout.workspaceTitlebarHeight,
            leadingInset: UtilityLayout.workspaceTitleLeadingInset
        )
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        Color.gray.opacity(0.2)
        SidebarTitle(text: "MacPowerToys")
    }
    .frame(width: 220, height: 100)
}
