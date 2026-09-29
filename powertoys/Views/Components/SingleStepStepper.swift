import OnePlusUI
import SwiftUI

struct SingleStepStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) {
        self.title = title; _value = value; self.range = range; self.step = step
    }
    var body: some View {
        HStack {
            Text(title).onePlusText(.row)
            Spacer()
            OnePlusStepperField(title, value: $value, in: range, step: step)
                .frame(width: OnePlusMetrics.controlColumn)
        }
    }
}
