//
//  SubtleProgressBar.swift
//  powertoys
//

import SwiftUI

struct SubtleProgressBar: View {
    let progress: Double

    private var isActive: Bool {
        progress > 0 && progress < 1
    }

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.green.opacity(isActive ? 0.4 : 0.08))
                .frame(width: geo.size.width * progress)
                .animation(.easeInOut(duration: 0.2), value: progress)
        }
        .frame(height: 3)
    }
}
