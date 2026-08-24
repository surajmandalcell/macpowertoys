import SwiftUI

enum NetToysPage: String, CaseIterable, Identifiable {
    case scanner = "IP Scanner"
    case anchor = "SSH Anchor"
    case history = "Network History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scanner: "dot.radiowaves.left.and.right"
        case .anchor: "link"
        case .history: "chart.xyaxis.line"
        }
    }
}

struct NetToysWindowView: View {
    @State private var page = NetToysPage.scanner
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            QuietDivider()
            content
                .utilityContentTransition(value: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .frame(minWidth: 860, minHeight: 600)
        .background(WindowAccessor(identifier: "nettoys"))
        .sheet(isPresented: $showSettings) {
            ToolAboutView(toolId: "nettoys")
                .frame(width: 540, height: 520)
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysRescanRun)) { notification in
            guard let run = notification.object as? NetToysScanRun else { return }
            page = .scanner
            Task { @MainActor in
                await Task.yield()
                NotificationCenter.default.post(name: .netToysStartScan, object: run)
            }
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarSectionHeader(title: "Network")
                        .padding(.horizontal, 4)

                    ForEach(NetToysPage.allCases) { item in
                        SidebarRow(
                            icon: item.icon,
                            title: item.rawValue,
                            isSelected: page == item
                        ) {
                            page = item
                        }
                        .accessibilityIdentifier("nettoys.page.\(item.id)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, UtilityLayout.workspaceContentTopInset)

                Spacer()

                SidebarRow(icon: "gearshape", title: "Settings") {
                    showSettings = true
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            SidebarTitle(text: "NetToys")
        }
        .frame(width: UtilityLayout.compactSidebarWidth)
        .background(VisualEffectBackground())
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .scanner:
            NetToysScannerView()
        case .anchor:
            NetToysAnchorView()
        case .history:
            NetToysHistoryView()
        }
    }
}

extension Notification.Name {
    static let netToysRescanRun = Notification.Name("netToysRescanRun")
    static let netToysStartScan = Notification.Name("netToysStartScan")
}

struct NetToysPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
                .controlSize(.small)
                .frame(height: UtilityLayout.workspaceActionHeight)
        }
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .frame(height: UtilityLayout.workspaceTitlebarHeight)
        .overlay(alignment: .bottom) { QuietDivider() }
    }
}
