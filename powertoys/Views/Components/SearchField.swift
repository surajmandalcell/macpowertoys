import OnePlusUI
import SwiftUI

struct NativeSearchField: View {
    @Binding var text: String
    var placeholder = "Search"
    var body: some View { OnePlusSearchField(prompt: placeholder, text: $text, width: nil) }
}

struct SidebarSearchField: View {
    @Binding var text: String
    var placeholder = "Search..."
    var isLoading = false
    var deepSearchEnabled: Binding<Bool>? = nil
    @Environment(\.toolWindowID) private var windowID
    var body: some View {
        HStack(spacing: 6) {
            OnePlusSidebarSearch(placeholder, text: $text)
            if isLoading { ProgressView().controlSize(.mini).accessibilityLabel("Searching") }
            if let deepSearchEnabled {
                Toggle(isOn: deepSearchEnabled) { Image(systemName: "doc.text.magnifyingglass") }
                    .toggleStyle(.button).buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .help("Search message content").accessibilityLabel("Deep search")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openToolPage)) { notification in
            if windowID == "main", (notification.object as? ToolPageRequest)?.tool == "main" { text = "" }
        }
    }
}
