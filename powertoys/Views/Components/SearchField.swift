import OnePlusUI
import SwiftUI

struct NativeSearchField: View {
    @Binding var text: String
    var placeholder = "Search"
    var body: some View { OnePlusSearchField(prompt: placeholder, text: $text, width: nil) }
}
