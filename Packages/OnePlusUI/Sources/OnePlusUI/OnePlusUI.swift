import AppKit
import SwiftUI

public enum OnePlusTheme {
    public static let desktop = Color(red: 0.043, green: 0.043, blue: 0.043)
    public static let window = Color(red: 0.086, green: 0.086, blue: 0.086)
    public static let sidebar = Color(red: 0.114, green: 0.114, blue: 0.114)
    public static let card = Color(red: 0.125, green: 0.125, blue: 0.125)
    public static let cardHover = Color(red: 0.145, green: 0.145, blue: 0.145)
    public static let line = Color(red: 0.188, green: 0.188, blue: 0.188)
    public static let lineSoft = Color(red: 0.157, green: 0.157, blue: 0.157)
    public static let ink = Color(red: 0.929, green: 0.929, blue: 0.929)
    public static let secondary = Color(red: 0.627, green: 0.627, blue: 0.627)
    public static let muted = Color(red: 0.463, green: 0.463, blue: 0.463)
    public static let accent = Color(red: 0.933, green: 0.357, blue: 0.314)
}

public enum OnePlusMetrics {
    public static let titlebarHeight: CGFloat = 40
    public static let titleLeadingInset: CGFloat = 84
    public static let trafficLightVerticalOffset: CGFloat = 4
    public static let panelRadius: CGFloat = 9
    public static let controlRadius: CGFloat = 5
    public static let controlHeight: CGFloat = 27
    public static let contentControlHeight: CGFloat = 36
    public static let controlHorizontalPadding: CGFloat = 10
    public static let contentControlHorizontalPadding: CGFloat = 14
    public static let actionSpacing: CGFloat = 8
}

public enum OnePlusMotion {
    public static let interactionDuration = 0.14

    public static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: interactionDuration)
    }
}

public struct OnePlusPanel<Content: View>: View {
    private let textured: Bool
    private let content: Content

    public init(textured: Bool = false, @ViewBuilder content: () -> Content) {
        self.textured = textured
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius)
                        .fill(OnePlusTheme.card)
                    if textured {
                        OnePlusDitherTexture()
                            .clipShape(RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius)
                    .strokeBorder(OnePlusTheme.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius))
    }
}

public struct OnePlusDitherTexture: View {
    static let resourceImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "grain", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private let strength: Double

    public init(strength: Double = 0.34) {
        self.strength = strength
    }

    @ViewBuilder
    public var body: some View {
        if let resourceImage = Self.resourceImage {
            Image(nsImage: resourceImage)
                .resizable()
                .interpolation(.none)
                .frame(width: 240, height: 150)
                .opacity(strength)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

public struct OnePlusSidebarTitle: View {
    private let text: String
    private let height: CGFloat
    private let leadingInset: CGFloat

    public init(
        _ text: String,
        height: CGFloat = OnePlusMetrics.titlebarHeight,
        leadingInset: CGFloat = OnePlusMetrics.titleLeadingInset
    ) {
        self.text = text
        self.height = height
        self.leadingInset = leadingInset
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OnePlusTheme.ink)
            .frame(height: height)
            .padding(.leading, leadingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct OnePlusFixedWindowChrome: NSViewRepresentable {
    private let contentSize: NSSize
    private let trafficLightVerticalOffset: CGFloat

    public init(
        contentSize: NSSize,
        trafficLightVerticalOffset: CGFloat = OnePlusMetrics.trafficLightVerticalOffset
    ) {
        self.contentSize = contentSize
        self.trafficLightVerticalOffset = trafficLightVerticalOffset
    }

    public func makeNSView(context: Context) -> NSView {
        OnePlusFixedWindowChromeView(
            contentSize: contentSize,
            trafficLightVerticalOffset: trafficLightVerticalOffset
        )
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let chrome = nsView as? OnePlusFixedWindowChromeView else { return }
        chrome.update(contentSize: contentSize, trafficLightVerticalOffset: trafficLightVerticalOffset)
    }
}

private final class OnePlusFixedWindowChromeView: NSView {
    private var contentSize: NSSize
    private var trafficLightVerticalOffset: CGFloat
    private var trafficLightBaselineY: CGFloat?
    private weak var configuredWindow: NSWindow?

    override var acceptsFirstResponder: Bool { true }

    init(contentSize: NSSize, trafficLightVerticalOffset: CGFloat) {
        self.contentSize = contentSize
        self.trafficLightVerticalOffset = trafficLightVerticalOffset
        super.init(frame: .zero)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if configuredWindow !== window {
            configuredWindow = window
            trafficLightBaselineY = nil
        }
        apply(to: window)
        schedule(in: window, resetFocus: true)
    }

    func update(contentSize: NSSize, trafficLightVerticalOffset: CGFloat) {
        self.contentSize = contentSize
        self.trafficLightVerticalOffset = trafficLightVerticalOffset
        guard let window else { return }
        apply(to: window)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let notifiedWindow = notification.object as? NSWindow,
              notifiedWindow === window else { return }
        apply(to: notifiedWindow)
        schedule(in: notifiedWindow, resetFocus: false)
    }

    private func apply(to window: NSWindow) {
        window.styleMask.remove(.resizable)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        let currentSize = window.contentView?.bounds.size ?? .zero
        if abs(currentSize.width - contentSize.width) > 0.5
            || abs(currentSize.height - contentSize.height) > 0.5 {
            window.setContentSize(contentSize)
        }
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.appearance = NSAppearance(named: .darkAqua)
        alignTrafficLights(in: window)
    }

    private func schedule(in window: NSWindow, resetFocus: Bool) {
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            apply(to: window)
            if resetFocus { window.makeFirstResponder(self) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
            guard let self, let window else { return }
            apply(to: window)
            if resetFocus { window.makeFirstResponder(self) }
        }
    }

    private func alignTrafficLights(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton) else { return }
        if trafficLightBaselineY == nil { trafficLightBaselineY = closeButton.frame.origin.y }
        guard let baselineY = trafficLightBaselineY else { return }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            button.setFrameOrigin(NSPoint(
                x: button.frame.origin.x,
                y: baselineY - trafficLightVerticalOffset
            ))
        }
    }
}

public enum OnePlusControlTone: Equatable {
    case standard
    case primary
    case destructive
    case quiet

    fileprivate var foreground: Color {
        switch self {
        case .primary: OnePlusTheme.window
        case .destructive: Color(red: 0.937, green: 0.635, blue: 0.608)
        case .standard, .quiet: OnePlusTheme.ink.opacity(0.88)
        }
    }

    fileprivate func background(hovering: Bool, pressed: Bool) -> Color {
        switch self {
        case .primary:
            Color.white.opacity(pressed ? 0.76 : hovering ? 0.94 : 0.86)
        case .destructive:
            OnePlusTheme.accent.opacity(pressed ? 0.12 : hovering ? 0.25 : 0.16)
        case .standard:
            Color.white.opacity(pressed ? 0.045 : hovering ? 0.12 : 0.075)
        case .quiet:
            Color.white.opacity(pressed ? 0.025 : hovering ? 0.085 : 0.035)
        }
    }

    fileprivate var border: Color {
        switch self {
        case .primary: Color.white.opacity(0.72)
        case .destructive: OnePlusTheme.accent.opacity(0.42)
        case .standard, .quiet: OnePlusTheme.line
        }
    }
}

public struct OnePlusControlButtonStyle: ButtonStyle {
    private let tone: OnePlusControlTone
    private let minWidth: CGFloat?
    private let minHeight: CGFloat
    private let horizontalPadding: CGFloat

    public init(
        tone: OnePlusControlTone = .standard,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = OnePlusMetrics.controlHeight,
        horizontalPadding: CGFloat = OnePlusMetrics.controlHorizontalPadding
    ) {
        self.tone = tone
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.horizontalPadding = horizontalPadding
    }

    public func makeBody(configuration: Configuration) -> some View {
        Body(
            label: configuration.label,
            pressed: configuration.isPressed,
            tone: tone,
            minWidth: minWidth,
            minHeight: minHeight,
            horizontalPadding: horizontalPadding
        )
    }

    private struct Body<Label: View>: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        let label: Label
        let pressed: Bool
        let tone: OnePlusControlTone
        let minWidth: CGFloat?
        let minHeight: CGFloat
        let horizontalPadding: CGFloat

        var body: some View {
            label
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(tone.foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: minWidth, minHeight: minHeight)
                .background(
                    RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                        .fill(tone.background(hovering: hovering, pressed: pressed))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                        .strokeBorder(
                            isFocused ? OnePlusTheme.accent.opacity(0.85) : tone.border,
                            lineWidth: isFocused ? 1.5 : 1
                        )
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(tone == .primary ? 0.08 : 0.035))
                        .frame(height: 1)
                        .padding(.horizontal, OnePlusMetrics.controlRadius)
                }
                .contentShape(RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
                .opacity(isEnabled ? 1 : 0.38)
                .onHover { hovering = isEnabled && $0 }
                .animation(OnePlusMotion.animation(reduceMotion: reduceMotion), value: hovering || pressed)
        }
    }
}

public extension View {
    func onePlusControl(
        _ tone: OnePlusControlTone = .standard,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = OnePlusMetrics.controlHeight,
        horizontalPadding: CGFloat = OnePlusMetrics.controlHorizontalPadding
    ) -> some View {
        buttonStyle(OnePlusControlButtonStyle(
            tone: tone,
            minWidth: minWidth,
            minHeight: minHeight,
            horizontalPadding: horizontalPadding
        ))
        .focusEffectDisabled()
    }
}

public struct OnePlusMenuLabel: View {
    private let title: String
    private let width: CGFloat
    @Environment(\.isFocused) private var isFocused
    @State private var hovering = false

    public init(title: String, width: CGFloat) {
        self.title = title
        self.width = width
    }

    public var body: some View {
        Text(title)
            .lineLimit(1)
            .frame(width: width - 18, alignment: .leading)
            .font(.system(size: 10.5))
            .foregroundStyle(OnePlusTheme.ink.opacity(0.88))
            .padding(.horizontal, 9)
            .frame(height: OnePlusMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                    .fill(OnePlusControlTone.quiet.background(hovering: hovering, pressed: false))
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(OnePlusTheme.secondary)
                    .padding(.trailing, 9)
                    .accessibilityHidden(true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                    .strokeBorder(isFocused ? OnePlusTheme.accent.opacity(0.85) : OnePlusTheme.line)
            }
            .contentShape(RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
            .onHover { hovering = $0 }
            .accessibilityLabel(title)
    }
}

public struct OnePlusSelect<Value: Hashable>: View {
    private let choices: [(Value, String)]
    @Binding private var selection: Value
    private let width: CGFloat
    private let accessibilityLabel: String

    public init(
        choices: [(Value, String)],
        selection: Binding<Value>,
        width: CGFloat = 120,
        accessibilityLabel: String
    ) {
        self.choices = choices
        _selection = selection
        self.width = width
        self.accessibilityLabel = accessibilityLabel
    }

    private var selectedTitle: String {
        choices.first { $0.0 == selection }?.1 ?? choices.first?.1 ?? ""
    }

    public var body: some View {
        Menu {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                Button {
                    selection = choice.0
                } label: {
                    if choice.0 == selection {
                        Label(choice.1, systemImage: "checkmark")
                    } else {
                        Text(choice.1)
                    }
                }
            }
        } label: {
            OnePlusMenuLabel(title: selectedTitle, width: width)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(accessibilityLabel)
    }
}

public struct OnePlusSearchField: View {
    private let prompt: String
    @Binding private var text: String
    private let width: CGFloat
    private let focusTrigger: Int
    @FocusState private var focused: Bool

    public init(
        prompt: String,
        text: Binding<String>,
        width: CGFloat = 300,
        focusTrigger: Int = 0
    ) {
        self.prompt = prompt
        _text = text
        self.width = width
        self.focusTrigger = focusTrigger
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(OnePlusTheme.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 34)
        .background(Color(red: 0.133, green: 0.133, blue: 0.133))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focused ? OnePlusTheme.accent.opacity(0.72) : OnePlusTheme.line)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { focused = true }
        .onAppear { if focusTrigger > 0 { focused = true } }
        .onChange(of: focusTrigger) { _, _ in focused = true }
    }
}

public struct OnePlusSegments<Value: Hashable>: View {
    private let choices: [(Value, String)]
    @Binding private var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(choices: [(Value, String)], selection: Binding<Value>) {
        self.choices = choices
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 1) {
            ForEach(choices.indices, id: \.self) { index in
                let (value, label) = choices[index]
                OnePlusSegmentButton(label: label, selected: selection == value) {
                    selection = value
                }
            }
        }
        .padding(2)
        .background(Color(red: 0.105, green: 0.105, blue: 0.105), in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusTheme.line) }
        .fixedSize()
        .animation(OnePlusMotion.animation(reduceMotion: reduceMotion), value: selection)
    }
}

private struct OnePlusSegmentButton: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(label, action: action)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(selected ? OnePlusTheme.ink : OnePlusTheme.secondary)
            .padding(.horizontal, 9)
            .frame(minHeight: 24)
            .background(
                Color.white.opacity(selected ? 0.09 : hovering ? 0.05 : 0),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
