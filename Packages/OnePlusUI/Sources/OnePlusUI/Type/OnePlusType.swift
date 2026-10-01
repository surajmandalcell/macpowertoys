import AppKit
import SwiftUI

public enum OnePlusMetricTypography {
    public static let lineHeight: CGFloat = 30.24
    @MainActor static let nativeFont = NSFont(descriptor: NSFont.systemFont(ofSize: 27).fontDescriptor
        .addingAttributes([.variation: [0x77676874: 550]]), size: 27)! // OpenType wght axis
    @MainActor public static let font = Font(nativeFont)
}

public enum OnePlusDensity: String, CaseIterable, Sendable {
    case regular, compact
    public var controlHeight: CGFloat { self == .regular ? 28 : 24 }
    public var gutter: CGFloat { self == .regular ? 24 : 20 }
    public var navRowHeight: CGFloat { self == .regular ? 32 : 29 }
}

private struct OnePlusDensityKey: EnvironmentKey {
    static let defaultValue = OnePlusDensity.regular
}

public extension EnvironmentValues {
    var onePlusDensity: OnePlusDensity {
        get { self[OnePlusDensityKey.self] }
        set { self[OnePlusDensityKey.self] = newValue }
    }
}

public enum OnePlusTextRole: String, CaseIterable, Sendable {
    case sidebarTitle, nav, captionUpper, pageTitle, subtitle, tab, sectionTitle
    case cardTitle, row, control, caption, metricCaption, tableHeader, mono, metric, unit

    public func size(for density: OnePlusDensity) -> CGFloat {
        let compact = density == .compact
        switch self {
        case .sidebarTitle: return 12.5
        case .nav: return compact ? 11.5 : 12.5
        case .captionUpper: return 9
        case .pageTitle: return compact ? 20 : 24
        case .subtitle: return compact ? 10.5 : 12.5
        case .tab: return compact ? 11 : 12
        case .sectionTitle: return compact ? 12 : 13
        case .cardTitle: return compact ? 11 : 12
        case .row, .control: return compact ? 10.5 : 12
        case .caption, .metricCaption: return compact ? 9.5 : 10.5
        case .tableHeader: return 9
        case .mono: return compact ? 9.5 : 11
        case .metric: return 27
        case .unit: return compact ? 10 : 12
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .sidebarTitle, .pageTitle, .sectionTitle, .cardTitle, .metric: .semibold
        case .captionUpper, .tableHeader: .medium
        default: .regular
        }
    }

    public var tracking: CGFloat {
        switch self {
        case .sidebarTitle: -0.16
        case .pageTitle: -0.7
        case .captionUpper: 1
        case .sectionTitle, .cardTitle: -0.1
        case .tableHeader: 0.4
        case .metric: -1
        default: 0
        }
    }

    public var color: Color {
        switch self {
        case .nav, .subtitle, .mono, .unit: OnePlusColor.secondary
        case .captionUpper, .tab, .caption, .tableHeader: OnePlusColor.muted
        case .control: OnePlusColor.controlInk
        case .metricCaption: OnePlusColor.metricCaption
        default: OnePlusColor.ink
        }
    }
}

private struct OnePlusTextModifier: ViewModifier {
    @Environment(\.onePlusDensity) private var density
    let role: OnePlusTextRole
    let selected: Bool
    let color: Color?

    func body(content: Content) -> some View {
        content
            .font(role == .metric ? OnePlusMetricTypography.font : .system(
                size: role.size(for: density), weight: role.weight,
                design: role == .mono ? .monospaced : .default))
            .tracking(role.tracking)
            .foregroundStyle(color ?? (selected ? OnePlusColor.ink : role.color))
            .textCase(role == .captionUpper || role == .tableHeader ? .uppercase : nil)
            .monospacedDigit()
            .frame(height: role == .metric ? OnePlusMetricTypography.lineHeight : nil)
    }
}

public extension View {
    func onePlusDensity(_ density: OnePlusDensity) -> some View { environment(\.onePlusDensity, density) }
    func onePlusText(_ role: OnePlusTextRole, selected: Bool = false, color: Color? = nil) -> some View {
        modifier(OnePlusTextModifier(role: role, selected: selected, color: color))
    }
}
