import AppKit
import SwiftUI

/// Keeps a visited page's state and layout without keeping hidden live work active.
public struct OnePlusRetainedPage<Revision: Equatable, Content: View>: NSViewRepresentable {
    private let isSelected: Bool
    private let revision: Revision
    private let content: () -> Content

    public init(isSelected: Bool, revision: Revision,
                @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.revision = revision
        self.content = content
    }

    public final class Coordinator {
        fileprivate var host: NSHostingView<AnyView>?
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> NSView { NSView() }

    public func updateNSView(_ view: NSView, context: Context) {
        guard isSelected || context.coordinator.host != nil else { return }
        let environment = context.environment
        // Forward page keys only; copying the scene environment invalidates unrelated roots.
        let root = AnyView(OnePlusRetainedPageContent(revision: revision, content: content)
            .equatable()
            .onePlusDensity(environment.onePlusDensity)
            .environment(\.onePlusCardPadding, environment.onePlusCardPadding)
            .environment(\.onePlusControlHeight, environment.onePlusControlHeight)
            .environment(\.onePlusPageScrollBottomInset, environment.onePlusPageScrollBottomInset)
            .environment(\.onePlusIsVisible, isSelected && environment.onePlusIsVisible)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.isEnabled, environment.isEnabled)
            .onePlusNeutralControls())
        let host = context.coordinator.host ?? NSHostingView(rootView: root)
        host.sizingOptions = []
        host.rootView = root
        context.coordinator.host = host
        if isSelected {
            if host.superview !== view {
                host.frame = view.bounds
                host.autoresizingMask = [.width, .height]
                view.addSubview(host)
            }
        } else {
            // Deliver hidden visibility before detaching, so child tasks cancel now.
            host.layoutSubtreeIfNeeded()
            host.removeFromSuperview()
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    public static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let host = coordinator.host {
            host.rootView = AnyView(EmptyView())
            host.layoutSubtreeIfNeeded()
            host.removeFromSuperview()
        }
        coordinator.host = nil
    }
}

private struct OnePlusRetainedPageContent<Revision: Equatable, Content: View>: View, @MainActor Equatable {
    let revision: Revision
    let content: () -> Content
    @Environment(\.onePlusIsVisible) private var isVisible
    @State private var frame = LastFrame()

    private final class LastFrame {
        var content: Content?
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.revision == rhs.revision }

    var body: some View {
        // A hidden body drops observation of the builder's live model, but keeps its last frame.
        if isVisible || frame.content == nil { frame.content = content() }
        return frame.content!
    }
}
