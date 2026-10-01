import AppKit
import SwiftUI

/// A selectable SF Mono path beside or below its setting label.
public struct OnePlusPathSettingRow<Control: View>: View {
    public enum Layout { case stacked, horizontal }
    private let layout: Layout
    private let help: String?
    private let label: String
    private let path: String
    private let controlWidth: CGFloat
    private let separator: Bool
    private let control: Control

    public init(_ label: String, path: String,
                controlWidth: CGFloat = OnePlusMetrics.controlColumn,
                separator: Bool = true, layout: Layout = .stacked, help: String? = nil, @ViewBuilder control: () -> Control) {
        self.layout = layout; self.help = help
        self.label = label
        self.path = path
        self.controlWidth = controlWidth
        self.separator = separator
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: layout == .horizontal ? 8 : OnePlusMetrics.spacing[5]) {
            if layout == .horizontal {
                Text(label).onePlusText(.row).lineLimit(1).layoutPriority(1).help(help ?? label).accessibilityHint(help ?? "")
                Spacer(minLength: 8)
                pathText
                control.fixedSize()
            } else {
                VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                    Text(label).onePlusText(.row).lineLimit(1).help(help ?? label).accessibilityHint(help ?? "")
                    pathText
                }.frame(maxWidth: .infinity, alignment: .leading)
                control.frame(width: controlWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: layout == .horizontal ? OnePlusMetrics.settingRow : OnePlusMetrics.captionedSettingRow)
        .overlay(alignment: .bottom) { if separator { OnePlusRule() } }
    }

    private var pathText: some View {
        Text(path).onePlusText(.mono).lineLimit(1).truncationMode(.middle)
            .textSelection(.enabled).help(path)
            .contextMenu {
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
    }
}
