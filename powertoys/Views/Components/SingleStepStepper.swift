import AppKit
import SwiftUI

struct SingleStepStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    init(
        _ title: String,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        LabeledContent(title) {
            SingleStepControl(
                title: title,
                value: $value,
                range: range,
                step: step
            )
        }
    }
}

private struct SingleStepControl: NSViewRepresentable {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSStepper {
        let stepper = NSStepper()
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.valueChanged(_:))
        configure(stepper)
        return stepper
    }

    func updateNSView(_ stepper: NSStepper, context: Context) {
        context.coordinator.value = $value
        configure(stepper)
    }

    private func configure(_ stepper: NSStepper) {
        stepper.controlSize = .small
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = Double(step)
        stepper.integerValue = value
        stepper.valueWraps = false
        stepper.autorepeat = false
        stepper.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var value: Binding<Int>

        init(value: Binding<Int>) {
            self.value = value
        }

        @objc func valueChanged(_ sender: NSStepper) {
            value.wrappedValue = sender.integerValue
        }
    }
}
