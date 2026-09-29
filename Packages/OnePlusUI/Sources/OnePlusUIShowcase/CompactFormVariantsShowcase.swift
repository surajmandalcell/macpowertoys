import AppKit
import OnePlusUI
import SwiftUI

struct CompactFormVariantsShowcase: View {
    @State private var tab = "History"
    @State private var value = 30
    @State private var mode = "Ask"

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader("Compact form variants")
            OnePlusTabStrip(tabs: [OnePlusTab("History", "History"), OnePlusTab("Projects", "Projects")],
                            selection: $tab, layout: .applet)
            OnePlusSettingRow("Scan interval") {
                OnePlusStepperField("Seconds", value: $value, in: 1...60, unit: "sec")
            }
            OnePlusSettingRow("Mode") {
                OnePlusSegmented(choices: [("Off", "Off"), ("Ask", "Ask"), ("Auto", "Auto")], selection: $mode)
            }
            NativeFormSample().frame(height: 80).padding(OnePlusMetrics.cardPadding)
        }
        .frame(width: 420).onePlusDensity(.compact)
        .environment(\.onePlusControlHeight, OnePlusMetrics.controlHeight)
    }
}

private struct NativeFormSample: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let card = OnePlusNativeCardView()
        let field = OnePlusNativeStepperField(frame: NSRect(x: 16, y: 44, width: 80, height: 28))
        field.awakeFromNib()
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 4000
        field.formatter = formatter
        field.stringValue = "260"
        field.setAccessibilityLabel("Width")
        card.addSubview(field)
        let toggle = OnePlusNativeSwitchButton(frame: NSRect(x: 16, y: 8, width: 260, height: 28))
        toggle.setButtonType(.switch)
        toggle.title = "Native switch"
        toggle.state = .on
        toggle.awakeFromNib()
        card.addSubview(toggle)
        OnePlusNativeForm.style(card)
        return card
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
