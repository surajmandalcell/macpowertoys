//
//  SearchField.swift
//  powertoys
//

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var isLoading: Bool = false

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
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
    }
    .padding()
    .frame(width: 250)
}
