//
//  SearchField.swift
//  powertoys
//

import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search"

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.controlSize = .small
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = placeholder
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var isLoading: Bool = false
    var deepSearchEnabled: Binding<Bool>? = nil

    @State private var isHoveringDeepSearch = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 16, height: 16)
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }

            if let deepSearch = deepSearchEnabled {
                Button {
                    deepSearch.wrappedValue.toggle()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(deepSearch.wrappedValue ? Color.accentColor : .secondary)
                        .opacity(deepSearch.wrappedValue || isHoveringDeepSearch ? 1.0 : 0.5)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { isHoveringDeepSearch = $0 }
                .help(deepSearch.wrappedValue ? "Deep search enabled (searching content)" : "Enable deep search (search message content)")
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    VStack(spacing: 20) {
        SearchField(text: .constant(""), placeholder: "Search tools...")
        SearchField(text: .constant("test"), placeholder: "Search...")
        SearchField(text: .constant("loading"), isLoading: true)
        SearchField(text: .constant("deep"), deepSearchEnabled: .constant(false))
        SearchField(text: .constant("deep active"), deepSearchEnabled: .constant(true))
    }
    .padding()
    .frame(width: 280)
}
