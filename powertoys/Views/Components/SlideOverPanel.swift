//
//  SlideOverPanel.swift
//  powertoys
//

import SwiftUI

struct SlideOverPanel<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let persistenceKey: String?
    @ViewBuilder let content: () -> Content

    @State private var panelWidth: CGFloat = 350
    @GestureState private var dragOffset: CGFloat = 0

    private let minWidth: CGFloat = 250
    private let maxWidth: CGFloat = 600

    init(
        isPresented: Binding<Bool>,
        title: String,
        persistenceKey: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.persistenceKey = persistenceKey
        self.content = content

        if let key = persistenceKey {
            let saved = UserDefaults.standard.double(forKey: "slideOverPanel.\(key).width")
            if saved > 0 {
                _panelWidth = State(initialValue: CGFloat(saved))
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            dragHandle

            VStack(spacing: 0) {
                header
                Divider()
                content()
            }
            .frame(width: max(minWidth, min(maxWidth, panelWidth + dragOffset)))
            .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
        }
        .transition(.move(edge: .trailing))
    }

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = -value.translation.width
                    }
                    .onEnded { value in
                        let newWidth = panelWidth - value.translation.width
                        panelWidth = max(minWidth, min(maxWidth, newWidth))
                        saveWidth()
                    }
            )
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func saveWidth() {
        guard let key = persistenceKey else { return }
        UserDefaults.standard.set(Double(panelWidth), forKey: "slideOverPanel.\(key).width")
    }
}
