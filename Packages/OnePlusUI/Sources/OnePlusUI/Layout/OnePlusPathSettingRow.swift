import SwiftUI

/// A setting row with a selectable SF Mono path below its label.
public struct OnePlusPathSettingRow<Control: View>: View {
    private let label: String
    private let path: String
    private let controlWidth: CGFloat
    private let separator: Bool
    private let control: Control

    public init(_ label: String, path: String,
                controlWidth: CGFloat = OnePlusMetrics.controlColumn,
                separator: Bool = true, @ViewBuilder control: () -> Control) {
        self.label = label
        self.path = path
        self.controlWidth = controlWidth
        self.separator = separator
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: OnePlusMetrics.spacing[5]) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                Text(label).onePlusText(.row).lineLimit(1).help(label)
                Text(path).onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled).help(path)
            }.frame(maxWidth: .infinity, alignment: .leading)
            control.frame(width: controlWidth, alignment: .trailing)
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: OnePlusMetrics.captionedSettingRow)
        .overlay(alignment: .bottom) { if separator { OnePlusRule() } }
    }
}
