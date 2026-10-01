import SwiftUI

public extension Image {
    /// Template glyph assets keep 4pt of padding in a 32pt view box, so they
    /// draw 25% larger than an SF Symbol of the same size to paint the same ink.
    /// The layout slot stays `size`, so labels keep their column.
    func onePlusAssetGlyph(size: CGFloat) -> some View {
        resizable().scaledToFit()
            .frame(width: size * 1.25, height: size * 1.25)
            .frame(width: size, height: size)
    }
}
