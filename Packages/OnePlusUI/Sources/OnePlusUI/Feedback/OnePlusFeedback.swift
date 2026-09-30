import AppKit
import SwiftUI

public struct OnePlusEmptyState<Action: View>: View {
    let title: String
    let icon: String
    let caption: String?
    let action: Action
    public init(_ title: String, systemImage: String, caption: String? = nil, @ViewBuilder action: () -> Action) {
        self.title = title; icon = systemImage; self.caption = caption; self.action = action()
    }
    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(OnePlusColor.muted).accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(OnePlusColor.ink)
            if let caption { Text(caption).onePlusText(.caption).multilineTextAlignment(.center) }
            action.buttonStyle(OnePlusButtonStyle())
        }.padding(.vertical, 40).padding(.horizontal, 20).frame(maxWidth: .infinity)
    }
}

public extension OnePlusEmptyState where Action == EmptyView {
    init(_ title: String, systemImage: String, caption: String? = nil) {
        self.init(title, systemImage: systemImage, caption: caption, action: { EmptyView() })
    }
}

public struct OnePlusToast: View {
    let message: String
    let icon: String
    public init(_ message: String, systemImage: String = "checkmark.circle") { self.message = message; icon = systemImage }
    public var body: some View {
        Label(message, systemImage: icon).font(.system(size: 11)).foregroundStyle(OnePlusColor.ink)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(OnePlusColor.raised.opacity(0.96), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusColor.line, lineWidth: 1) }
            .padding(.bottom, 20).allowsHitTesting(false)
            .onChange(of: message, initial: true) { _, message in
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                     userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
    }
}

public struct OnePlusBanner<Action: View>: View {
    public enum Tone: Sendable { case information, warning, error }
    let message: String
    let tone: Tone
    let action: Action
    public init(_ message: String, tone: Tone = .information, @ViewBuilder action: () -> Action) {
        self.message = message; self.tone = tone; self.action = action()
    }
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tone == .information ? "info.circle" : tone == .warning ? "exclamationmark.triangle" : "exclamationmark.circle")
                .foregroundStyle(tone == .information ? OnePlusColor.secondary : tone == .warning ? OnePlusColor.warn : OnePlusColor.danger)
                .accessibilityHidden(true)
            Text(message).onePlusText(.row).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action.buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(OnePlusColor.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(tone == .error ? OnePlusColor.dangerLine : OnePlusColor.line, lineWidth: 1) }
    }
}

public extension OnePlusBanner where Action == EmptyView {
    init(_ message: String, tone: Tone = .information) { self.init(message, tone: tone, action: { EmptyView() }) }
}

public enum OnePlusSheetWidth: CGFloat, Sendable { case small = 420, medium = 560, large = 700 }

/// Present inside SwiftUI's native `.sheet` modifier.
public struct OnePlusSheet<Body: View, Footer: View>: View {
    let title: String
    let width: CGFloat
    let close: (() -> Void)?
    let content: Body
    let footer: Footer
    public init(_ title: String, width: OnePlusSheetWidth = .medium, close: (() -> Void)? = nil,
                @ViewBuilder content: () -> Body, @ViewBuilder footer: () -> Footer) {
        self.title = title; self.width = width.rawValue; self.close = close
        self.content = content(); self.footer = footer()
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).onePlusText(.sectionTitle).accessibilityAddTraits(.isHeader)
                Spacer()
                if let close {
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                        .help("Close").accessibilityLabel("Close").keyboardShortcut(.cancelAction)
                }
            }.padding(.horizontal, 20).frame(height: 40)
            OnePlusColor.lineSoft.frame(height: 1)
            content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            if Footer.self != EmptyView.self {
                OnePlusColor.lineSoft.frame(height: 1)
                HStack(spacing: 8) { Spacer(); footer }.padding(20)
            }
        }.frame(width: width).background(OnePlusColor.window).onePlusDensity(.regular)
            .onePlusNeutralControls()
            .onePlusFocusPolicy()
            .onePlusAppAppearance()
    }
}

public extension OnePlusSheet where Footer == EmptyView {
    init(_ title: String, width: OnePlusSheetWidth = .medium, close: (() -> Void)? = nil, @ViewBuilder content: () -> Body) {
        self.init(title, width: width, close: close, content: content, footer: { EmptyView() })
    }
}
