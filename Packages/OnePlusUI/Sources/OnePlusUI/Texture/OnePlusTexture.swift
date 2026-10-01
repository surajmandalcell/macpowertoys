import AppKit
import SwiftUI

public enum OnePlusTextureAsset: String, CaseIterable, Sendable {
    case grain, ribbon, diskDither, partitionBand

    @MainActor public var image: NSImage? { Self.images[self] }
    @MainActor private static let images: [Self: NSImage] = Dictionary(uniqueKeysWithValues: allCases.compactMap { asset in
        guard let url = Bundle.module.url(forResource: asset.rawValue, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (asset, image)
    })
}

public struct OnePlusWindowTexture: View {
    @Environment(\.colorScheme) private var colorScheme
    public init() {}
    public var body: some View {
        GeometryReader { _ in
            if let image = OnePlusTextureAsset.ribbon.image {
                Image(nsImage: image).resizable().interpolation(.none)
                    .frame(width: 630, height: 198)
                    .mask(LinearGradient(stops: [
                        .init(color: .clear, location: 0), .init(color: .black, location: 0.26),
                        .init(color: .black, location: 0.82), .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing))
                    .opacity(colorScheme == .dark ? 0.20 : 0.10)
                    .offset(x: 16, y: -8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

public struct OnePlusMetricTexture: View {
    public static let size = CGSize(width: 180, height: 110)
    public static let opacity = 0.07
    public init() {}
    public var body: some View {
        GeometryReader { _ in
            if let image = OnePlusTextureAsset.ribbon.image {
                Image(nsImage: image).resizable().interpolation(.none).saturation(0)
                    .frame(width: Self.size.width, height: Self.size.height).opacity(Self.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

public struct OnePlusDitherTexture: View {
    static var resourceImage: NSImage? { OnePlusTextureAsset.grain.image }
    private let strength: Double
    public init(strength: Double = 0.14) { self.strength = strength }
    public var body: some View {
        GeometryReader { _ in
            if let image = Self.resourceImage {
                Image(nsImage: image).resizable().interpolation(.none)
                    .frame(width: 200, height: 125).opacity(strength)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

public extension View {
    /// Apply before clipping the card to its final shape.
    func onePlusGrain(opacity: Double = 0.14) -> some View {
        overlay(OnePlusDitherTexture(strength: opacity)).clipped()
    }
}

@MainActor
public enum OnePlusChartPattern {
    public static let pattern: CGPattern = {
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { _, context in
            context.setAlpha(0.65)
            context.fill(CGRect(x: 0, y: 0, width: 0.65, height: 0.65))
            context.setAlpha(0.30)
            context.fill(CGRect(x: 2, y: 2, width: 0.65, height: 0.65))
        }, releaseInfo: nil)
        return CGPattern(info: nil, bounds: CGRect(x: 0, y: 0, width: 4, height: 4),
                         matrix: .identity, xStep: 4, yStep: 4, tiling: .constantSpacing,
                         isColored: false, callbacks: &callbacks)!
    }()
}
