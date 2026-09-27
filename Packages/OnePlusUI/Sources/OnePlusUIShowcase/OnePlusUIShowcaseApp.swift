import OnePlusUI
import SwiftUI

@main
struct OnePlusUIShowcaseApp: App {
    var body: some Scene {
        Window("OnePlusUI", id: "oneplus-ui-showcase") {
            OnePlusUIShowcase()
                .frame(width: 920, height: 680)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct OnePlusUIShowcase: View {
    @State private var page = "Controls"
    @State private var query = ""
    @State private var selection = "Balanced"
    @State private var segment = "Combined"

    private let pages = ["Foundation", "Controls", "Surfaces"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                OnePlusSidebarTitle("OnePlusUI")
                VStack(spacing: 2) {
                    ForEach(pages, id: \.self) { item in
                        Button {
                            page = item
                        } label: {
                            HStack {
                                Image(systemName: icon(for: item)).frame(width: 16)
                                Text(item)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                page == item ? Color.white.opacity(0.09) : .clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                Spacer()
                Text("Swift Package")
                    .font(.system(size: 10))
                    .foregroundStyle(OnePlusTheme.muted)
                    .padding(16)
            }
            .frame(width: 190)
            .background(OnePlusTheme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(OnePlusTheme.line).frame(width: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(page)
                        .font(.system(size: 22, weight: .semibold))
                    Text("Reusable macOS primitives with fixed geometry, native type, restrained motion, and matching dark surfaces.")
                        .font(.system(size: 12))
                        .foregroundStyle(OnePlusTheme.secondary)
                    palette
                    controls
                    surfaces
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(OnePlusTheme.window)
        }
        .foregroundStyle(OnePlusTheme.ink)
        .background(OnePlusTheme.window)
    }

    private var palette: some View {
        showcaseSection("Palette") {
            HStack(spacing: 8) {
                swatch("Window", OnePlusTheme.window)
                swatch("Sidebar", OnePlusTheme.sidebar)
                swatch("Card", OnePlusTheme.card)
                swatch("Accent", OnePlusTheme.accent)
                swatch("Ink", OnePlusTheme.ink)
            }
        }
    }

    private var controls: some View {
        showcaseSection("Controls") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Button("Standard") {}.onePlusControl()
                    Button("Primary") {}.onePlusControl(.primary)
                    Button("Danger") {}.onePlusControl(.destructive)
                    Button("Disabled") {}.onePlusControl().disabled(true)
                }
                HStack(spacing: 12) {
                    OnePlusSearchField(prompt: "Search components", text: $query, width: 280)
                    OnePlusSelect(
                        choices: [("Compact", "Compact"), ("Balanced", "Balanced"), ("Roomy", "Roomy")],
                        selection: $selection,
                        width: 120,
                        accessibilityLabel: "Density"
                    )
                    OnePlusSegments(
                        choices: [("Off", "Off"), ("Combined", "Combined"), ("Separate", "Separate")],
                        selection: $segment
                    )
                }
            }
        }
    }

    private var surfaces: some View {
        showcaseSection("Surfaces") {
            HStack(spacing: 12) {
                OnePlusPanel(textured: true) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Textured panel", systemImage: "circle.grid.cross")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Static dither adds depth without an idle animation loop.")
                            .font(.system(size: 10))
                            .foregroundStyle(OnePlusTheme.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                OnePlusPanel {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Plain panel", systemImage: "rectangle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("The same radius, border, type, and semantic colors.")
                            .font(.system(size: 10))
                            .foregroundStyle(OnePlusTheme.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 112)
        }
    }

    private func showcaseSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(OnePlusTheme.muted)
            content()
        }
    }

    private func swatch(_ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(height: 44)
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusTheme.line) }
            Text(label).font(.system(size: 9)).foregroundStyle(OnePlusTheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func icon(for page: String) -> String {
        switch page {
        case "Foundation": "paintpalette"
        case "Surfaces": "square.stack.3d.up"
        default: "slider.horizontal.3"
        }
    }
}
