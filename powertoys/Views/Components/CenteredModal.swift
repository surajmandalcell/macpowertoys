//
//  CenteredModal.swift
//  powertoys
//

import SwiftUI

struct CenteredModal<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        isPresented: Binding<Bool>,
        title: String,
        width: CGFloat = 700,
        height: CGFloat = 550,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.width = width
        self.height = height
        self.content = content
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .transition(.opacity)

            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
                .padding(16)

                QuietDivider()

                content()
            }
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            .transition(.opacity)
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
