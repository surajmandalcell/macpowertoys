import AppKit
import OnePlusUI
import SwiftUI

@main
@MainActor
struct OnePlusUIShowcaseApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        let delegate = ShowcaseDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class ShowcaseDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1240, height: 840),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = ProcessInfo.processInfo.environment["ONEPLUS_SHOWCASE_TITLE"] ?? "OnePlusUI"
        window.identifier = NSUserInterfaceItemIdentifier("oneplus-ui-showcase")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnePlusUIShowcase())
        self.window = window
        window.orderBack(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct OnePlusUIShowcase: View {
    private static let tableColumns: [OnePlusGridColumn] = [
        .init("Name", width: 170, textRole: .row, leadingInset: 16),
        .init("MAC vendor", width: 120, textRole: .row),
        .init("Completed", width: 110, alignment: .trailing, textRole: .mono)
    ]
    @State private var page = "Foundation"
    @State private var query = ""
    @State private var processQuery = ""
    @State private var light = false
    @State private var selectedTab = "Overview"
    @State private var enabled = true
    @State private var checked = true
    @State private var mode = "Auto"
    @State private var text = "MacBook Pro"
    @State private var invalidText = ""
    @State private var notes = "# Local workspace\n\nCPU samples use the last 60 seconds.\nAll values in this showcase are sample data."
    @State private var interval = 2
    @State private var showSheet = false
    @State private var toast: String?
    @State private var menuTab = "home"
    @State private var placement = "Combined"
    @State private var preference = "Default (Off)"
    @State private var tableSelection = Set<String>()
    @State private var tableRows = (1...4).map { OnePlusTableItem(id: String($0), cells: ["Workstation \($0)", "Apple", "Completed"], symbol: "desktopcomputer") }
    @State private var tableSortColumn = 0
    @State private var tableAscending = true
    @State private var menuTabs = [OnePlusMenuTab("home", "Home", systemImage: "square.grid.2x2"),
                                   OnePlusMenuTab("cpu", "CPU", systemImage: "cpu"),
                                   OnePlusMenuTab("gpu", "GPU", systemImage: "rectangle.3.group"),
                                   OnePlusMenuTab("memory", "Memory", systemImage: "memorychip"),
                                   OnePlusMenuTab("network", "Network", systemImage: "network"),
                                   OnePlusMenuTab("disk", "Disk", systemImage: "internaldrive"),
                                   OnePlusMenuTab("battery", "Battery", systemImage: "battery.100"),
                                   OnePlusMenuTab("sensors", "Sensors", systemImage: "thermometer.medium"),
                                   OnePlusMenuTab("processes", "Processes", systemImage: "list.bullet")]
    private let pages = ["Foundation", "Typography", "Buttons", "Inputs", "Popup menus", "Data", "Native tables", "Fixed regions", "Settings", "Task Manager", "Menu panel", "Applets", "Compact forms", "Rows and tabs", "Feedback"]
    private let samples: [Double] = [16, 18, 15, 22, 19, 17, 24, 42, 33, 24, 22, 21, 28, 19, 24, 21, 20, 26, 24, 28]
    private var compact: Bool { page == "Task Manager" }
    private var canvas: OnePlusWindowCanvas {
        OnePlusWindowCanvas(width: 1240, height: 840, sidebarWidth: compact ? 200 : 216,
                            density: compact ? .compact : .regular)
    }

    var body: some View {
        OnePlusWindowRoot(canvas: canvas) {
            OnePlusSidebar(title: "OnePlusUI") {
                OnePlusSidebarSearch("Search pages", text: $query)
            } navigation: {
                OnePlusNavCaption("Components")
                ForEach(pages.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { item in
                    if item == "Settings" { OnePlusNavCaption("Samples", spacing: .sectionStart) }
                    OnePlusNavRow(item, systemImage: icon(item), selected: page == item,
                                  count: item == "Inputs" ? 8 : nil) { page = item; toast = nil }
                }
            } bottom: {
                OnePlusNavRow("Version 2", systemImage: "shippingbox", external: true) { announce("OnePlusUI v2 · DESIGN.md v14") }
                OnePlusNavRow("Quit showcase", systemImage: "rectangle.portrait.and.arrow.right") { NSApp.terminate(nil) }
            }
        } content: {
            if page == "Fixed regions" {
                PageRegionsShowcase(header: pageHeader)
            } else {
                OnePlusPage {
                    pageHeader
                } tabs: {
                    OnePlusTabStrip(tabs: [OnePlusTab("Overview", "Overview", count: 12), OnePlusTab("Details", "Details", count: 4)],
                                    selection: $selectedTab) {
                        OnePlusStatus("Sample data")
                    }
                } content: { pageContent }
                .overlay(alignment: .bottom) { if let toast { OnePlusToast(toast) } }
            }
        }
        .onChange(of: light) { _, value in NSApp.appearance = NSAppearance(named: value ? .aqua : .darkAqua) }
        .sheet(isPresented: $showSheet) {
            OnePlusSheet("Edit workspace", close: { showSheet = false }) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Give this sample workspace a name.").onePlusText(.row)
                    OnePlusTextField("Workspace name", text: $text)
                    Toggle("Keep local history", isOn: $enabled).toggleStyle(OnePlusSwitchStyle())
                }
            } footer: {
                Button("Cancel") { showSheet = false }.buttonStyle(OnePlusButtonStyle(.ghost))
                Button("Save") { showSheet = false; announce("Workspace saved") }
                    .buttonStyle(OnePlusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            toast = nil
        }
    }

    private var pageHeader: some View {
        OnePlusPageHeader(title: compact ? "TASK MANAGER" : page,
                          subtitle: compact ? "Apple M4 Pro · 12 cores · 24 GB · Sample data" : "OnePlusUI v2 · macOS component reference",
                          titleStyle: compact ? .dotMatrix : .system) {
            Button(light ? "Dark appearance" : "Light appearance") { light.toggle() }
                .buttonStyle(OnePlusButtonStyle(.ghost))
                .accessibilityIdentifier("showcase.appearance")
            Button("Open sheet") { showSheet = true }.buttonStyle(OnePlusButtonStyle())
        }
    }

    @ViewBuilder private var pageContent: some View {
        if selectedTab == "Details" {
            OnePlusCard {
                OnePlusCardHeader("Component details")
                VStack(spacing: 8) {
                    OnePlusKeyValueRow("Page", value: page)
                    OnePlusKeyValueRow("Density", value: compact ? "Compact" : "Regular")
                    OnePlusKeyValueRow("Canvas", value: "1240 × 840 pt", monospaced: true)
                    OnePlusKeyValueRow("Traffic-light centerline", value: "27 pt", monospaced: true)
                    OnePlusKeyValueRow("Page title top", value: "16 pt", monospaced: true)
                }.padding(16)
            }
        } else {
            switch page {
            case "Foundation": foundation
            case "Typography": typography
            case "Buttons": buttons
            case "Inputs": inputs
            case "Popup menus": PopupMenusShowcase()
            case "Data": data
            case "Native tables": nativeTables
            case "Settings": settings
            case "Task Manager": taskManager
            case "Menu panel": menuPanel
            case "Applets": applets
            case "Compact forms": CompactFormVariantsShowcase()
            case "Rows and tabs": RowAndTabStatesShowcase()
            default: feedback
            }
        }
    }

    private var foundation: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnePlusSectionTitle("Dynamic colors")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
                ForEach(Array(palette.enumerated()), id: \.offset) { _, token in
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 6).fill(token.1).frame(height: 32)
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusColor.line, lineWidth: 1) }
                        Text(token.0).onePlusText(.caption)
                    }
                }
            }
            HStack(spacing: 16) {
                OnePlusCard(textured: true) {
                    OnePlusCardHeader("Static corner grain", systemImage: "circle.dotted")
                    Text("Exact 240 × 150 source pixels. No idle animation.").onePlusText(.row).padding(16)
                }
                OnePlusCard {
                    OnePlusCardHeader("Flat surface", systemImage: "rectangle")
                    Text("One-point border. Eight-point radius.").onePlusText(.row).padding(16)
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Geometry")
                HStack(spacing: 24) {
                    OnePlusKeyValueRow("Empty title row", value: "54 pt", monospaced: true)
                    OnePlusKeyValueRow("Page title top", value: "16 pt", monospaced: true)
                    OnePlusKeyValueRow("Card header", value: "40 pt", monospaced: true)
                    OnePlusKeyValueRow("Setting row", value: "44 pt", monospaced: true)
                }.padding(16)
            }
            OnePlusSectionTitle("Chart and storage series")
            OnePlusSegmentBar(values: [1, 1, 1, 1])
            OnePlusSegmentBar(values: Array(repeating: 1, count: 11), colors: OnePlusColor.storageSeries)
        }
    }

    private var typography: some View {
        OnePlusCard {
            OnePlusCardHeader("San Francisco and SF Mono")
            HStack(spacing: 16) { Text("ROLE").frame(maxWidth: .infinity, alignment: .leading); Text("REGULAR").frame(width: 300, alignment: .leading); Text("COMPACT").frame(width: 300, alignment: .leading) }
                .onePlusTableHeader()
            ForEach(OnePlusTextRole.allCases, id: \.rawValue) { role in
                HStack(spacing: 16) {
                    Text(role.rawValue).onePlusText(.mono).frame(maxWidth: .infinity, alignment: .leading)
                    Text(role == .metric ? "27.4" : "System activity").onePlusText(role).onePlusDensity(.regular).frame(width: 300, alignment: .leading)
                    Text(role == .metric ? "27.4" : "System activity").onePlusText(role).onePlusDensity(.compact).frame(width: 300, alignment: .leading)
                }.padding(.horizontal, 12).frame(height: 34)
            }
            HStack { Text("Dot matrix").onePlusText(.mono); Spacer(); OnePlusDotTitle("TASK MANAGER 0123456789") }
                .padding(16)
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnePlusCard {
                OnePlusCardHeader("Button states")
                HStack {
                    Text("VARIANT").frame(width: 120, alignment: .leading)
                    ForEach(["Rest", "Hover", "Pressed", "Focus", "Disabled"], id: \.self) { Text($0).frame(maxWidth: .infinity) }
                }.onePlusTableHeader()
                ForEach(OnePlusButtonStyle.Variant.allCases, id: \.rawValue) { variant in
                    HStack(spacing: 12) {
                        Text(variant.rawValue.capitalized).onePlusText(.row).frame(width: 120, alignment: .leading)
                        ForEach(OnePlusControlState.allCases, id: \.rawValue) { state in
                            sampleButton(variant).environment(\.onePlusControlState, state).frame(maxWidth: .infinity)
                        }
                        sampleButton(variant).disabled(true).frame(maxWidth: .infinity)
                    }.padding(.horizontal, 12).frame(height: 52)
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Compact density · automatic 24 pt")
                HStack(spacing: 12) {
                    ForEach(OnePlusButtonStyle.Variant.allCases, id: \.rawValue) { variant in sampleButton(variant) }
                    Spacer()
                }.padding(16).onePlusDensity(.compact)
            }
            OnePlusCard {
                OnePlusCardHeader("Custom menu triggers")
                HStack(spacing: 12) {
                    OnePlusMenuButton("More", items: [.item(OnePlusPopupMenuItem("Show details") { announce("Details selected") })])
                    OnePlusMenuButton("Export", variant: .neutral,
                                      items: [.item(OnePlusPopupMenuItem("Export sample") { announce("Sample exported") })])
                    OnePlusMenuButton("Presets", items: [.item(OnePlusPopupMenuItem("Default") { announce("Default selected") })])
                    OnePlusMenuButton("Unavailable", items: []).disabled(true)
                    Spacer()
                }.padding(16)
            }
            OnePlusCard {
                OnePlusToolPageHeader(title: "Catalog tool", subtitle: "A tool page with an icon and separate actions.") {
                    Image(systemName: "wrench.adjustable").resizable().scaledToFit()
                } actions: {
                    Toggle("Enable tool", isOn: $enabled).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    Button("Open") { announce("Opened catalog tool") }.buttonStyle(OnePlusButtonStyle.catalogOpen)
                    Button("Open") {}.buttonStyle(OnePlusButtonStyle.catalogOpen).disabled(true)
                }
                OnePlusNavRow("Disabled tool", systemImage: "wrench.adjustable", muted: true) { announce("Tool settings opened") }
            }
            OnePlusBanner("All actions update the sample toast. Destructive actions affect sample data only.")
        }
    }
    private func sampleButton(_ variant: OnePlusButtonStyle.Variant, size: OnePlusButtonStyle.Size? = nil) -> some View {
        Button { announce("\(variant.rawValue.capitalized) action completed") } label: {
            if variant == .icon || variant == .borderedIcon { Image(systemName: "arrow.clockwise") }
            else { Text(variant == .destructive ? "Remove" : variant == .link ? "View all" : "Action") }
        }.buttonStyle(OnePlusButtonStyle(variant, size: size)).accessibilityLabel("\(variant.rawValue.capitalized) action")
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                OnePlusCard {
                    OnePlusCardHeader("Selection")
                    OnePlusSettingRow("Enabled") { Toggle("Enabled", isOn: $enabled).labelsHidden().toggleStyle(OnePlusSwitchStyle()) }
                    OnePlusSettingRow("Disabled") { Toggle("Disabled", isOn: .constant(false)).labelsHidden().toggleStyle(OnePlusSwitchStyle()).disabled(true) }
                    OnePlusSettingRow("Default state") { OnePlusSegmented(choices: ["Default (Off)", "On", "Off"].map { ($0, $0) }, selection: $preference) }
                    OnePlusSettingRow("Placement") { OnePlusSegmented(choices: ["None", "Combined", "Separate"].map { ($0, $0) }, selection: $placement) }
                    OnePlusSettingRow("Popup") { OnePlusSelect(choices: [("Off", "Off"), ("Auto", "Auto"), ("On", "On")], selection: $mode, accessibilityLabel: "Mode") }
                    OnePlusSettingRow("Catalog view") {
                        OnePlusSegmented(iconChoices: [("Off", "Grid", "square.grid.2x2"), ("Auto", "List", "list.bullet")],
                                         selection: $mode, accessibilityLabel: "Catalog view")
                            .frame(width: OnePlusCatalogMetrics.viewControlWidth)
                    }
                    OnePlusSettingRow("Checkbox") { Toggle("Keep history", isOn: $checked).toggleStyle(OnePlusCheckboxStyle()) }
                    OnePlusSettingRow("Radio", separator: false) { OnePlusRadio("Mode", choices: [("Off", "Off"), ("Auto", "Auto")], selection: $mode).horizontalRadioGroupLayout().labelsHidden() }
                }
                OnePlusCard {
                    OnePlusCardHeader("Text input")
                    VStack(alignment: .leading, spacing: 12) {
                        OnePlusTextField("Workspace name", text: $text)
                        OnePlusTextField("Unavailable", text: .constant("Disabled field")).disabled(true)
                        OnePlusTextField("Required name", text: $invalidText, error: invalidText.isEmpty ? "Enter a name." : nil)
                        OnePlusSearchField(prompt: "Find a process", text: $processQuery, width: nil)
                        OnePlusStepperField("Refresh interval", value: $interval, in: 1...60, unit: "sec")
                    }.padding(16)
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Native text editor", systemImage: "text.alignleft")
                OnePlusTextEditor("Workspace notes", text: $notes).frame(height: 180).padding(16)
            }
        }
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricTiles
            OnePlusCard {
                OnePlusCardHeader("CPU history · sample data")
                OnePlusAreaChart(values: samples).frame(height: 130).padding(16)
            }
            HStack(alignment: .top, spacing: 16) {
                OnePlusCard {
                    OnePlusCardHeader("Connections")
                    OnePlusGridTable(columns: [.init("Host", width: 200), .init("State", width: 95), .init("Latency", width: 90, trailing: true)],
                                     rows: [["MacBook Pro", "Online", "2 ms"], ["Home server", "Offline", "n/a"], ["Workstation", "Online", "18 ms"]])
                }
                OnePlusCard {
                    OnePlusCardHeader("State and values")
                    VStack(spacing: 10) {
                        HStack { OnePlusStatus("Online"); OnePlusStatus("Offline", state: .offline); OnePlusStatus("Warning", state: .warning) }
                        HStack { OnePlusStatus("Saved", state: .success); OnePlusStatus("Failed", state: .error); OnePlusBadge(7); OnePlusBadge(3, pending: true) }
                        OnePlusKeyValueRow("System", value: "macOS", monospaced: true)
                        OnePlusUsageBar(value: 0.64)
                        OnePlusSegmentBar(values: [44, 28, 18, 10])
                    }.padding(16)
                }
            }
        }
    }

    private var nativeTables: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(OnePlusDensity.allCases, id: \.self) { density in
                HStack(alignment: .top, spacing: 16) {
                    OnePlusCard {
                        OnePlusCardHeader("Native table · \(density.rawValue)")
                        OnePlusNativeTable(columns: Self.tableColumns,
                                           rows: tableRows, selection: $tableSelection,
                                           sortColumn: tableSortColumn, ascending: tableAscending,
                                           sort: { column, ascending in
                                               tableSortColumn = column; tableAscending = ascending
                                               tableRows.sort {
                                                   let left = $0.cells[column] + $0.id
                                                   let right = $1.cells[column] + $1.id
                                                   return ascending ? left < right : left > right
                                               }
                                           }, open: { _ in announce("Opened sample") },
                                           preview: { _ in announce("Preview sample") }, remove: { ids in
                                               tableRows.removeAll { ids.contains($0.id) }
                                               tableSelection.subtract(ids)
                                           }, actions: { ids in [.init("Show names") {
                                               announce(tableRows.filter { ids.contains($0.id) }.map { $0.cells[0] }.joined(separator: ", "))
                                           }] })
                            .frame(height: OnePlusTable.rowHeight(density) * 4 + 28)
                    }
                    OnePlusCard {
                        OnePlusCardHeader("SwiftUI Table · \(density.rawValue)")
                        Table(tableRows, selection: $tableSelection) {
                            TableColumn("Name") { Text($0.cells[0]).onePlusTableCell(Self.tableColumns[0], position: .first) }.width(min: 140, ideal: 170)
                            TableColumn("MAC vendor") { Text($0.cells[1]).onePlusTableCell(Self.tableColumns[1]) }.width(120)
                            TableColumn("Completed") { Text($0.cells[2]).onePlusTableCell(Self.tableColumns[2], position: .last) }.width(110)
                        }.onePlusNativeTable(columns: Self.tableColumns).frame(height: OnePlusTable.rowHeight(density) * 4 + 28)
                    }
                }.onePlusDensity(density)
            }
            OnePlusBanner("Headers use 9 pt type. Regular rows are 34 pt; compact rows are 28 pt.")
        }
    }

    private var metricTiles: some View {
        HStack(spacing: 16) {
            OnePlusMetricTile("CPU", systemImage: "cpu", value: "27.4", unit: "%", caption: "12 cores", action: { announce("CPU selected") }) {
                OnePlusSparkline(values: samples).frame(height: 32)
            }
            OnePlusMetricTile("Memory", systemImage: "memorychip", value: "14.6", unit: "GB", caption: "of 24 GB") { OnePlusUsageBar(value: 0.61).frame(height: 32) }
            OnePlusMetricTile("Disk", systemImage: "internaldrive", value: "328", unit: "GB", caption: "of 1 TB") { OnePlusSegmentBar(values: [32, 22, 12, 34]).frame(height: 32) }
            OnePlusMetricTile("Network", systemImage: "network", value: "2.8", unit: "MB/s", caption: "Ethernet") { OnePlusSparkline(values: samples.reversed()).frame(height: 32) }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnePlusSectionTitle("General", actionTitle: "Reset all") { enabled = true; interval = 2; mode = "Auto"; announce("Defaults restored") }
            OnePlusCard {
                OnePlusCardHeader("Workspace", systemImage: "macwindow")
                OnePlusSettingRow("Record history", caption: "Keep recent activity on this Mac.", help: "History stays on this Mac.", reset: { enabled = true }) {
                    Toggle("Record history", isOn: $enabled).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Refresh interval", reset: { interval = 2 }) { OnePlusStepperField("Seconds", value: $interval, in: 1...60, unit: "sec") }
                OnePlusSettingRow("Behavior", reset: { mode = "Auto" }) { OnePlusSelect(choices: [("Off", "Off"), ("Auto", "Automatic"), ("On", "Always on")], selection: $mode, accessibilityLabel: "Behavior") }
                OnePlusSettingRow("Display name", controlWidth: 180, separator: false) { OnePlusTextField("Name", text: $text) }
            }
            OnePlusCard {
                OnePlusCardHeader("Menu bar", systemImage: "menubar.rectangle")
                OnePlusSettingRow("Show item") { Toggle("Show item", isOn: $checked).labelsHidden().toggleStyle(OnePlusSwitchStyle()) }
                OnePlusSettingRow("Placement", controlWidth: 180, separator: false) { OnePlusSegmented(choices: ["None", "Combined", "Separate"].map { ($0, $0) }, selection: $placement) }
            }
            OnePlusBanner("These settings change the sample only.")
        }
    }

    private var taskManager: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricTiles
            HStack(alignment: .top, spacing: 16) {
                OnePlusCard {
                    OnePlusCardHeader("Processor", systemImage: "cpu") { OnePlusStatus("27.4%") }
                    OnePlusAreaChart(values: samples).frame(height: 168).padding(16)
                }
                OnePlusCard {
                    OnePlusCardHeader("Memory", systemImage: "memorychip") { OnePlusStatus("Normal") }
                    VStack(spacing: 8) {
                        OnePlusKeyValueRow("Physical memory", value: "24.00 GB", monospaced: true)
                        OnePlusKeyValueRow("Memory used", value: "14.60 GB", monospaced: true)
                        OnePlusKeyValueRow("Cached files", value: "6.28 GB", monospaced: true)
                        OnePlusKeyValueRow("Swap used", value: "0 bytes", monospaced: true)
                        OnePlusUsageBar(value: 0.61)
                    }.padding(16).frame(height: 200)
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Processes", systemImage: "list.bullet") { OnePlusSearchField(prompt: "Filter processes", text: $processQuery, width: 200, height: 24) }
                OnePlusGridTable(columns: [.init("Process", width: 400), .init("PID", width: 140, trailing: true), .init("CPU", width: 150, trailing: true), .init("Memory", width: 150, trailing: true)],
                                 rows: [["WindowServer", "318", "8.4%", "728 MB"], ["OnePlusUIShowcase", "1024", "0.1%", "42 MB"], ["kernel_task", "0", "2.3%", "186 MB"]].filter { processQuery.isEmpty || $0[0].localizedCaseInsensitiveContains(processQuery) })
            }
        }
    }

    private var menuPanel: some View {
        HStack(alignment: .top, spacing: 24) {
            OnePlusMenuPanel(maximumHeight: 650) {
                OnePlusMenuTabStrip(tabs: menuTabs, selection: $menuTab) { from, to in menuTabs.swapAt(from, to) }
            } actions: {
                OnePlusMenuOpenApp { page = "Task Manager" }
            } toolbar: {
                OnePlusSearchField(prompt: "Filter panel cards", text: $processQuery, width: 338, height: 28)
            } footer: {
                HStack {
                    OnePlusStatus("Live while open")
                    Spacer()
                    Button("Refresh") { announce("Panel refreshed") }.buttonStyle(OnePlusButtonStyle(.ghost))
                }.frame(height: 24)
            } content: {
                if menuTab != "home" {
                    OnePlusMenuSectionHeader(menuTabs.first { $0.id == menuTab }?.title ?? "Activity")
                    OnePlusMenuTile(span: 3, height: 140) { OnePlusAreaChart(values: samples) }
                }
                HStack(spacing: 5) {
                    menuTile("CPU", value: "27.4", unit: "%")
                    menuTile("GPU", value: "12.8", unit: "%")
                    menuTile("Memory", value: "14.6", unit: "GB")
                }
                HStack(spacing: 5) {
                    OnePlusMenuTile(span: 2) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Network").onePlusText(.caption)
                            Text("↓ 2.8 MB/s    ↑ 184 KB/s").onePlusText(.mono)
                            OnePlusSparkline(values: samples).frame(height: 18)
                        }
                    }
                    menuTile("Disk", value: "328", unit: "GB")
                }
                OnePlusMenuControlRow("Fan", systemImage: "fan", status: "1800 rpm") {
                    OnePlusSegmented(choices: [("Auto", "Auto"), ("On", "Max")], selection: $mode)
                }
                OnePlusMenuControlRow("Awake", systemImage: "sun.max", status: enabled ? "On" : "Off") {
                    Toggle("Awake", isOn: $enabled).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusMenuSectionHeader("Remote hosts", actionTitle: "Manage") { announce("Remote hosts selected") }
                OnePlusMenuItemCard("Home server", systemImage: "server.rack", status: "Connected", metrics: [
                    .init("CPU", systemImage: "cpu", value: "4.2", unit: "%"),
                    .init("Memory", systemImage: "memorychip", value: "8.4", unit: "GB"),
                    .init("Disk", systemImage: "internaldrive", value: "42", unit: "%")
                ]) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mac mini · Ethernet").onePlusText(.caption)
                        OnePlusUsageBar(value: 0.42)
                    }
                } actions: {
                    Button("Details") { announce("Home server selected") }
                    Button("Refresh") { announce("Host refreshed") }
                }
                OnePlusMenuItemCard("Offline sample host", systemImage: "server.rack", status: "Offline",
                                    online: false, metrics: [
                    .init("CPU", systemImage: "cpu", value: "—"),
                    .init("RAM", systemImage: "memorychip", value: "—"),
                    .init("Network", systemImage: "arrow.up.arrow.down", value: "—")
                ]) {
                    Text("No disk data").onePlusText(.caption)
                } actions: {
                    Button("Open SSH") { announce("This is a sample host") }
                    Button("Open App") { page = "Task Manager" }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                OnePlusSectionTitle("Menu panel")
                OnePlusKeyValueRow("Width", value: "356 pt")
                OnePlusKeyValueRow("Top bar", value: "\(Int(OnePlusMenuMetrics.topBar)) pt")
                OnePlusKeyValueRow("Tabs", value: "26 pt")
                OnePlusKeyValueRow("Grid gap", value: "5 pt")
                OnePlusKeyValueRow("Columns", value: "3")
                OnePlusBanner("Tabs change the body. Use a tab's context menu to change its order.")
            }.frame(width: 320)
            Spacer(minLength: 0)
        }
    }
    private func menuTile(_ title: String, value: String, unit: String) -> some View {
        OnePlusMenuTile(action: { announce("\(title) selected") }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).onePlusText(.caption)
                HStack(alignment: .firstTextBaseline, spacing: 2) { Text(value).font(.system(size: 19, weight: .medium)).monospacedDigit(); Text(unit).onePlusText(.caption) }
                OnePlusSparkline(values: samples).frame(height: 14)
            }
        }
    }

    private var applets: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnePlusSectionTitle("Applet titlebar · 40 pt · centerline 22 pt")
            OnePlusCard {
                OnePlusAppletTitlebar(title: "Awake") {
                    Button("Start") { enabled.toggle(); announce(enabled ? "Awake started" : "Awake stopped") }.buttonStyle(OnePlusButtonStyle(.primary, size: .small))
                }
                OnePlusColor.lineSoft.frame(height: 1)
                VStack(alignment: .leading, spacing: 16) {
                    OnePlusSegmented(choices: [("Off", "Off"), ("Auto", "Until"), ("On", "Indefinitely")], selection: $mode)
                    OnePlusStatus(enabled ? "Keeping your Mac awake" : "Sleep is allowed")
                    OnePlusSettingRow("Keep display on", separator: false) { Toggle("Display", isOn: $checked).labelsHidden().toggleStyle(OnePlusSwitchStyle()) }
                }.padding(16).onePlusFloatingSettings(isActive: false) { showSheet = true }
            }.frame(width: 560)
            OnePlusCard {
                OnePlusAppletTitlebar(title: "Color Picker") {
                    Button("Pick color") { announce("Sample color copied") }.buttonStyle(OnePlusButtonStyle(.primary, size: .small))
                }
                OnePlusEmptyState("No colors yet", systemImage: "eyedropper", caption: "Pick a color to add it to history.")
            }.frame(width: 420)
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnePlusBanner("Full Disk Access is needed to read every folder.", tone: .warning) {
                Button("Review access") { announce("Permission details opened") }
            }
            OnePlusBanner("The sample host could not be reached. Check its address.", tone: .error) {
                Button("Retry") { announce("Retry completed") }
            }
            HStack(alignment: .top, spacing: 16) {
                OnePlusCard {
                    OnePlusCardHeader("Empty")
                    OnePlusEmptyState("No hosts added", systemImage: "desktopcomputer", caption: "Add a host to see its activity.") {
                        Button("Add host") { showSheet = true }
                    }.frame(height: 205)
                }
                OnePlusCard {
                    OnePlusCardHeader("Loading")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reading sample data…").onePlusText(.row)
                        OnePlusUsageBar(value: 0.45)
                        Text("45% complete").onePlusText(.caption)
                    }.padding(40).frame(height: 205)
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Feedback actions")
                HStack(spacing: 12) {
                    Button("Show toast") { announce("Settings saved") }.buttonStyle(OnePlusButtonStyle())
                    Button("Open native sheet") { showSheet = true }.buttonStyle(OnePlusButtonStyle(.primary))
                    OnePlusFloatingSettingsButton(isActive: true) { showSheet = true }
                }.padding(16)
            }
            OnePlusToast("Static toast sample")
        }
    }

    private func announce(_ message: String) { toast = message }
    private func icon(_ name: String) -> String {
        switch name {
        case "Foundation": "square.stack.3d.up"
        case "Typography": "textformat"
        case "Buttons": "cursorarrow.click"
        case "Inputs": "slider.horizontal.3"
        case "Popup menus": "chevron.up.chevron.down"
        case "Data": "chart.xyaxis.line"
        case "Native tables": "tablecells"
        case "Fixed regions": "rectangle.topthird.inset.filled"
        case "Settings": "gearshape"
        case "Task Manager": "cpu"
        case "Menu panel": "menubar.rectangle"
        case "Applets", "Compact forms": "macwindow"
        default: "bubble.left"
        }
    }
    private var palette: [(String, Color)] {
        [("window", OnePlusColor.window), ("sidebar", OnePlusColor.sidebar), ("panel", OnePlusColor.panel),
         ("panelHover", OnePlusColor.panelHover), ("raised", OnePlusColor.raised), ("raisedHover", OnePlusColor.raisedHover),
         ("pressed", OnePlusColor.pressed), ("field", OnePlusColor.field), ("fieldFocus", OnePlusColor.fieldFocus),
         ("track", OnePlusColor.track), ("selection", OnePlusColor.selection), ("selectedControl", OnePlusColor.selectedControl),
         ("line", OnePlusColor.line), ("lineSoft", OnePlusColor.lineSoft), ("ink", OnePlusColor.ink), ("secondary", OnePlusColor.secondary),
         ("muted", OnePlusColor.muted), ("controlInk", OnePlusColor.controlInk), ("accent", OnePlusColor.accent),
         ("primaryFill", OnePlusColor.primaryFill), ("primaryInk", OnePlusColor.primaryInk), ("ok", OnePlusColor.ok),
         ("warn", OnePlusColor.warn), ("danger", OnePlusColor.danger), ("dangerFill", OnePlusColor.dangerFill), ("dangerLine", OnePlusColor.dangerLine)]
    }
}
