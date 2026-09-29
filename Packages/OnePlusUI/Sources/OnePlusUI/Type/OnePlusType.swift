import SwiftUI

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
    case cardTitle, row, control, caption, tableHeader, mono, metric, unit

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
        case .caption: return compact ? 9.5 : 10.5
        case .tableHeader: return compact ? 8.5 : 9
        case .mono: return compact ? 9.5 : 11
        case .metric: return compact ? 21 : 27
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
        default: OnePlusColor.ink
        }
    }
}

private struct OnePlusTextModifier: ViewModifier {
    @Environment(\.onePlusDensity) private var density
    let role: OnePlusTextRole
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: role.size(for: density), weight: role.weight,
                          design: role == .mono ? .monospaced : .default))
            .tracking(role.tracking)
            .foregroundStyle(selected ? OnePlusColor.ink : role.color)
            .textCase(role == .captionUpper || role == .tableHeader ? .uppercase : nil)
            .monospacedDigit()
    }
}

public extension View {
    func onePlusDensity(_ density: OnePlusDensity) -> some View { environment(\.onePlusDensity, density) }
    func onePlusText(_ role: OnePlusTextRole, selected: Bool = false) -> some View {
        modifier(OnePlusTextModifier(role: role, selected: selected))
    }
}
