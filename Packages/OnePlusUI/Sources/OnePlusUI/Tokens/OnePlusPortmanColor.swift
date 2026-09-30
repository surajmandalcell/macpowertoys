import SwiftUI

public extension OnePlusColor {
    /// Portman's original server palette, with darker inks for light panels.
    static let portmanSeries: [Color] = zip(
        [UInt32(0x6EC7ED), 0xB599F0, 0xEB9CD4, 0x7D9CF2, 0x7DDCE0],
        [UInt32(0x176B91), 0x7053A7, 0x9E4380, 0x4163B8, 0x1B7074]
    ).enumerated().map {
        Color(nsColor: dynamic("portman\($0.offset)", dark: $0.element.0, light: $0.element.1))
    }
}
