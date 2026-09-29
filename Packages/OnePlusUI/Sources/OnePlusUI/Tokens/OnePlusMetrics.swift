import SwiftUI

public enum OnePlusMetrics {
    public static let titleRow: CGFloat = 54
    public static let centerline: CGFloat = 27
    public static let appletTitlebar: CGFloat = 40
    public static let appletCenterline: CGFloat = 22
    public static let sidebarTitleGapAfterZoom: CGFloat = 14
    public static let searchHeight: CGFloat = 32
    public static let searchInsetX: CGFloat = 12
    public static let searchBelow: CGFloat = 14
    public static let navRowHeight: CGFloat = 32
    public static let compactNavRowHeight: CGFloat = 29
    public static let navRowGap: CGFloat = 2
    public static let navContainerInset: CGFloat = 10
    public static let navPadding: CGFloat = 10
    public static let navIcon: CGFloat = 15
    public static let navIconGap: CGFloat = 10
    public static let cardHeader: CGFloat = 40
    public static let settingRow: CGFloat = 44
    public static let captionedSettingRow: CGFloat = 56
    public static let controlHeight: CGFloat = 28
    public static let compactControlHeight: CGFloat = 24
    public static let controlColumn: CGFloat = 160
    public static let wideControlColumn: CGFloat = 180
    public static let tabHeight: CGFloat = 36
    public static let tabGap: CGFloat = 22
    public static let tabUnderline: CGFloat = 2
    public static let gutter: CGFloat = 24
    public static let taskManagerGutter: CGFloat = 20
    public static let appletGutter: CGFloat = 16
    public static let cardGap: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let contentTop: CGFloat = 16
    public static let spacing: [CGFloat] = [2, 4, 6, 8, 10, 12, 16, 20, 24, 28]
    public static let segmentRadius: CGFloat = 3
    public static let navRowRadius: CGFloat = 5
    public static let iconButtonRadius: CGFloat = 5
    public static let controlRadius: CGFloat = 6
    public static let menuTileRadius: CGFloat = 6
    public static let panelRadius: CGFloat = 8
    public static let windowRadius: CGFloat = 13
    public static let disabledOpacity: Double = 0.38
    public static let titlebarHeight = titleRow
    public static let titleLeadingInset: CGFloat = 84
    public static let fixedTitleLeadingInset = titleLeadingInset
    public static let trafficLightVerticalOffset: CGFloat = 11
    public static let contentControlHeight: CGFloat = 36
    public static let controlHorizontalPadding: CGFloat = 10
    public static let contentControlHorizontalPadding: CGFloat = 14
    public static let actionSpacing: CGFloat = 8

    public static func titleStart(afterZoom trailingX: CGFloat) -> CGFloat {
        trailingX + sidebarTitleGapAfterZoom
    }

    public static func top(of height: CGFloat, centerline: CGFloat = centerline) -> CGFloat {
        centerline - height / 2
    }
}

public struct OnePlusWindowCanvas: Equatable, Sendable {
    public let size: CGSize
    public let sidebarWidth: CGFloat
    public let density: OnePlusDensity
    public let isApplet: Bool
    public let heightRange: ClosedRange<CGFloat>?
    public var centerline: CGFloat { isApplet ? OnePlusMetrics.appletCenterline : OnePlusMetrics.centerline }

    public init(width: CGFloat, height: CGFloat, sidebarWidth: CGFloat = 200,
                density: OnePlusDensity = .regular, isApplet: Bool = false,
                heightRange: ClosedRange<CGFloat>? = nil) {
        size = CGSize(width: width, height: height)
        self.sidebarWidth = sidebarWidth
        self.density = density
        self.isApplet = isApplet
        self.heightRange = heightRange
    }

    public static let main = Self(width: 1240, height: 840, sidebarWidth: 216)
    public static let diskExplorer = Self(width: 1440, height: 900, sidebarWidth: 216)
    public static let netToys = Self(width: 1440, height: 900)
    public static let rclone = Self(width: 1240, height: 840, sidebarWidth: 216)
    public static let systemCare = Self(width: 1240, height: 840)
    public static let switchAccounts = Self(width: 1240, height: 840)
    public static let macTweaks = Self(width: 1120, height: 826)
    public static let systemMonitor = Self(width: 1080, height: 660, density: .compact)
    public static let logs = Self(width: 1080, height: 660)
    public static let inputDevices = Self(width: 1080, height: 660)
    public static let awake = Self(width: 560, height: 500, sidebarWidth: 0, isApplet: true)
    public static let colorPicker = Self(width: 420, height: 250, sidebarWidth: 0, isApplet: true, heightRange: 250...460)
    public static let textExtractor = Self(width: 480, height: 270, sidebarWidth: 0, isApplet: true, heightRange: 270...462)

    public static func tool(_ id: String) -> Self? {
        switch id {
        case "main": .main
        case "disk-explorer": .diskExplorer
        case "nettoys": .netToys
        case "rclone": .rclone
        case "system-care": .systemCare
        case "switch": .switchAccounts
        case "mac-tweaks": .macTweaks
        case "system-monitor": .systemMonitor
        case "logs": .logs
        case "input-devices": .inputDevices
        case "awake": .awake
        case "color-picker": .colorPicker
        case "text-extractor": .textExtractor
        default: nil
        }
    }
}

public enum OnePlusMotion {
    public static let hover = 0.10
    public static let selection = 0.14
    public static let content = 0.12
    public static let interactionDuration = hover
    public static func animation(reduceMotion: Bool, duration: Double = hover) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}
