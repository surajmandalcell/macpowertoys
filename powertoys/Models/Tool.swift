//
//  Tool.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation

// MARK: - Tool Protocol

protocol Tool: Identifiable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var icon: String { get }
    var logoAsset: String { get }
    var iconFileURL: URL? { get }
    var category: ToolCategory { get }
    var manual: [ToolManualSection] { get }
    var hasTrayTab: Bool { get }
    var searchKeywords: [String] { get }
}

extension Tool {
    var hasTrayTab: Bool { false }
    var iconFileURL: URL? { nil }
    var searchKeywords: [String] { [] }
}

// MARK: - Manual

struct ToolManualSection: Identifiable {
    let title: String
    let points: [String]

    var id: String { title }
}

// MARK: - Tool Category

enum ToolCategory: String, CaseIterable, Identifiable {
    case all = "All Tools"
    case dev = "Developer"
    case text = "Text"
    case files = "Files"
    case system = "System"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .dev: return "hammer"
        case .text: return "textformat"
        case .files: return "folder"
        case .system: return "gearshape.2"
        }
    }
}

// MARK: - Cloud Sync Tool

struct RcloneTool: Tool {
    let id = "rclone"
    let name = "Cloud Sync"
    let description = "Move files between your Mac and cloud storage with live progress, automatic retries, and ignore rules."
    let icon = "cloud"
    let logoAsset = "CloudSyncLogo"
    let category = ToolCategory.files
    let hasTrayTab = true

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Connect Cloud Storage", points: [
            "Click + next to Remotes in the Cloud Sync sidebar.",
            "Choose any connector offered by your installed rclone version, enter its required settings, and press Connect.",
            "For OAuth connectors, complete the provider's browser sign-in. rclone stores and refreshes the resulting credentials."
        ]),
        ToolManualSection(title: "Transfers", points: [
            "Press ⌘N or click New Transfer.",
            "Copy adds and updates files. Sync mirrors the source exactly, deleting extras. Move removes files from the source.",
            "Watch overall and per-file progress live. Failed transfers retry automatically with backoff."
        ]),
        ToolManualSection(title: "Browse & Preview", points: [
            "Click a remote in the sidebar to browse its files.",
            "Double-click folders to navigate. Press Space or click the eye to Quick Look a file.",
            "Drag files out to your Mac to download them, or drop local files into the folder to upload."
        ]),
        ToolManualSection(title: "Activity & Details", points: [
            "Every finished transfer is recorded in Activity with sizes and timing.",
            "Select ⓘ on a transfer to view paths, ignore rules, speed, attempts, and errors."
        ]),
        ToolManualSection(title: "Ignore Rules & Limits", points: [
            "Open Settings from the sidebar (⌘,) to edit ignore patterns. Add one glob per line. MacPowerToys applies each pattern to every transfer.",
            "System junk like .DS_Store, .fseventsd, and System Volume Information is ignored by default.",
            "Parallel transfers, bandwidth limits, and retry counts live on the same page."
        ]),
        ToolManualSection(title: "Dev Sync", points: [
            "Open Dev Sync in the sidebar and choose Set Up Dev Sync. Pick your internal dev folder and the matching folder on an external drive.",
            "Dev One-Way copies internal projects to the drive. Dev Bidirectional syncs changes both ways. Projects that live only on the drive stay there and appear as links in your internal folder.",
            "Review the preview before anything changes. Git ignore rules decide what is copied; ignored secrets such as .env files are still backed up unless you turn that off.",
            "Every overwrite and deletion is kept in the safety store for a retention period. Conflicts never pick a winner; resolve them from the pair page."
        ])
    ]

    static let shared = RcloneTool()
}

// MARK: - Logs Tool

struct LogsTool: Tool {
    let id = "logs"
    let name = "Logs"
    let description = "Inspect MacPowerToys activity and recent macOS errors and faults in clearly separated views."
    let icon = "doc.text.magnifyingglass"
    let logoAsset = "LogsLogo"
    let category = ToolCategory.system

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Reading Logs", points: [
            "Internal Logs contains MacPowerToys errors, warnings, info, and debug messages.",
            "System Issues reads recent macOS errors and faults on demand without saving them in the app.",
            "Choose a source in the sidebar, then filter internal levels or search messages and sources.",
            "Log text is fully selectable for copying into bug reports."
        ]),
        ToolManualSection(title: "Housekeeping", points: [
            "Internal logs are kept for two days, then pruned automatically.",
            "Clear Internal Logs empties the app's in-memory view.",
            "System Issues keeps at most 500 rows in memory and fetches them again when requested.",
            "Press ⌘, inside the window to change the log font size."
        ])
    ]

    static let shared = LogsTool()
}

// MARK: - Ruler Tool

struct RulerTool: Tool {
    let id = "ruler"
    let name = "Ruler"
    let description = "Measure the screen with movable, resizable rulers in pixels, millimeters, or inches."
    let icon = "ruler"
    let logoAsset = "RulerLogo"
    let category = ToolCategory.dev

    let manual = [
        ToolManualSection(title: "Rulers", points: [
            "Drag a ruler to move it and drag an end or corner to resize it.",
            "Press ⌘N for another ruler. Use H or V to show or hide a wing, and ⌘` to cycle rulers.",
            "Use U for units, F for floating, S for shadow, G for grouping, and O to align at the pointer."
        ]),
        ToolManualSection(title: "Settings", points: [
            "Press ⌘, to edit the active ruler. Press ⌥⌘, to edit defaults for new rulers.",
            "Choose color, foreground and background opacity, dimensions, float, and shadow."
        ])
    ]

    static let shared = RulerTool()
}

// MARK: - Awake Tool

struct AwakeTool: Tool {
    let id = "awake"
    let name = "Awake"
    let description = "Keep your Mac awake indefinitely, for a duration, or until a chosen time without changing Energy settings."
    let icon = "cup.and.saucer"
    let logoAsset = "AwakeLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Modes", points: [
            "Off uses normal macOS power settings. Indefinite remains active until disabled.",
            "Timed mode counts down for a duration. Until mode expires at a specific date and time.",
            "Keep Display On is independent and only applies while an active Awake mode is selected."
        ]),
        ToolManualSection(title: "System Behavior", points: [
            "Awake uses macOS power assertions and never edits your Energy settings.",
            "Manual sleep, closing a MacBook lid, low power, and thermal protection still take precedence."
        ])
    ]

    static let shared = AwakeTool()
}

// MARK: - Color Picker Tool

struct ColorPickerTool: Tool {
    let id = "color-picker"
    let name = "Color Picker"
    let description = "Pick any onscreen color, copy it instantly, and keep a compact searchable history of useful values."
    let icon = "eyedropper"
    let logoAsset = "ColorPickerLogo"
    let category = ToolCategory.dev
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Pick and Copy", points: [
            "Press Pick Color to start the native macOS sampler immediately.",
            "The selected color is copied in your default format and saved to history.",
            "Open Color History to copy HEX, RGB, HSL, CSS, SwiftUI, or NSColor representations."
        ])
    ]

    static let shared = ColorPickerTool()
}

// MARK: - Text Extractor Tool

struct TextExtractorTool: Tool {
    let id = "text-extractor"
    let name = "Text Extractor"
    let description = "Select text anywhere on screen and copy it using private, fully on-device Apple Vision recognition."
    let icon = "text.viewfinder"
    let logoAsset = "TextExtractorLogo"
    let category = ToolCategory.text
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Extract Text", points: [
            "Press Extract Text, drag around a screen region, and release to recognize and copy its text.",
            "Vision performs recognition locally. Captured pixels are discarded after processing.",
            "Screen Recording permission is required because macOS protects pixels belonging to other applications."
        ])
    ]

    static let shared = TextExtractorTool()
}

// MARK: - Input Devices Tool

struct InputDevicesTool: Tool {
    let id = "input-devices"
    let name = "Input Devices"
    let description = "Tune mouse and trackpad scrolling independently, including direction, speed, horizontal movement, and wheel smoothing."
    let icon = "computermouse"
    let logoAsset = "InputDevicesLogoA"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Profiles", points: [
            "Mouse-like wheel events and precise trackpad events have separate controls.",
            "Reverse either axis, change speed, disable horizontal motion, or smooth coarse mouse-wheel steps.",
            "Auto selects the matching profile for wheel or precision scrolling."
        ]),
        ToolManualSection(title: "Permission", points: [
            "Enable Input Control and grant Accessibility permission when macOS asks.",
            "Input Devices changes only scroll events. It does not record keys, clicks, or pointer movement."
        ])
    ]

    static let shared = InputDevicesTool()
}

// MARK: - System Care Tool

struct SystemCareTool: Tool {
    let id = "system-care"
    let name = "System Care"
    let description = "Understand storage, preview safe cleanup, remove apps, and use advanced Mole maintenance."
    let icon = "internaldrive"
    let logoAsset = "SystemCareLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Storage and Cleanup", points: [
            "Choose a folder in Storage to see its largest contents and drill into any directory.",
            "Quick Cleanup scans supported rebuildable data. Guided Cleanup lets you choose categories. Analysis Only cannot clean.",
            "Review every selected item before moving it to macOS Trash."
        ]),
        ToolManualSection(title: "Mole CLI", points: [
            "Install or update Mole from the Mole CLI page with Homebrew.",
            "Preview each maintenance operation before opening it in Terminal.",
            "Mole uses Terminal when macOS needs administrator approval."
        ])
    ]

    static let shared = SystemCareTool()
}

struct DiskExplorerTool: Tool {
    let id = "disk-explorer"
    let name = "Diskman"
    let description = "Analyze storage with live treemaps and rings, then manage removable disks and partitions."
    let icon = "internaldrive"
    let logoAsset = "DiskExplorerLogo"
    let category = ToolCategory.files

    let manual = [
        ToolManualSection(title: "Scan", points: [
            "Your Home Folder scans when Diskman opens. Choose a volume or another folder to scan it instead.",
            "The scan counts space used on disk, includes hidden files, and reports locations it could not read.",
            "Stop or rescan from the top bar. Scanning stops when the window closes."
        ]),
        ToolManualSection(title: "Explore", points: [
            "Choose Treemap or Rings, then measure space, file counts, or the age of recent changes. Your choices are remembered.",
            "Click a folder in the chart or contents list to go inside it. Use the path above the chart to go back.",
            "Search the current folder, change the sort order, or use Quick Look and Show in Finder for a file."
        ]),
        ToolManualSection(title: "Remove", points: [
            "Mark files or folders, then open Review to check the exact list and total size.",
            "Move to Trash is recoverable until you empty Trash. Permanent deletion asks again and cannot be undone."
        ]),
        ToolManualSection(title: "Modify", points: [
            "Select a physical disk or partition in Modify to verify, repair, mount, eject, format, or change its partition map.",
            "Diskman allows changes only on writable removable or external media and checks the device again before every operation.",
            "Review data-loss actions carefully and type the disk identifier to confirm them."
        ])
    ]

    static let shared = DiskExplorerTool()
}

// MARK: - System Monitor Tool

struct SystemMonitorTool: Tool {
    let id = "system-monitor"
    let name = "System Monitor"
    let description = "Watch CPU, memory, disk, network, battery, and thermal health on demand, with an optional lightweight menu-bar summary."
    let icon = "chart.xyaxis.line"
    let logoAsset = "SystemMonitorLogo"
    let category = ToolCategory.system
    let hasTrayTab = false

    let manual = [
        ToolManualSection(title: "Detailed Monitoring", points: [
            "Open System Monitor to view CPU, memory, disk, network, battery, and thermal state.",
            "Charts show the last two minutes of activity.",
            "Closing the window stops detailed updates."
        ]),
        ToolManualSection(title: "Menu Bar", points: [
            "Enable a grouped System Monitor item or separate metric items; either opens the Monitor popup.",
            "RAM is selected by default. Choose a refresh interval in settings, or turn the menu off to stop its timer."
        ])
    ]

    static let shared = SystemMonitorTool()
}

// MARK: - NetToys Tool

struct NetToysTool: Tool {
    let id = "nettoys"
    let name = "NetToys"
    let description = "Scan IP networks, keep SSH hosts attached to changing local addresses, and review network outages."
    let icon = "network"
    let logoAsset = "NetToysLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "IP Scanner", points: [
            "Enter one address, a range, a CIDR block, or a list of addresses.",
            "Choose TCP ports, then scan. Filter, select, copy, rescan, or export the results."
        ]),
        ToolManualSection(title: "SSH Anchor", points: [
            "Choose an explicit host and port from ~/.ssh/config.",
            "SSH Anchor checks that port every 2 to 3 seconds. If the address stops working, it searches the local subnet on only that port.",
            "Enrollment gives every grouped alias one stable host-key identity and accepts only its first key automatically.",
            "Enable Automatically installs your public key once so SSH stays key-only after address changes.",
            "A successful recovery changes only the HostName value in the selected host block."
        ]),
        ToolManualSection(title: "Network History", points: [
            "Network History records gateway and internet state changes.",
            "The bundled NetToys Helper runs only while NetToys is enabled."
        ])
    ]

    static let shared = NetToysTool()
}

struct PortmanTool: Tool {
    let id = "portman"
    let name = "Portman"
    let description = "See local development servers and forward private SSH ports to this Mac."
    let icon = "circle.grid.2x2.fill"
    let logoAsset = "PortmanLogo"
    let category = ToolCategory.dev
    let hasTrayTab = false

    let manual = [
        ToolManualSection(title: "Local servers", points: [
            "Open Portman from the launcher or its counted menu-bar item. The panel shows listening development ports and their share of Mac memory.",
            "Select a server for process-tree, memory, CPU, and project details. Clean up previews the memory to free before stopping selected servers."
        ]),
        ToolManualSection(title: "SSH forwarding", points: [
            "Enter an SSH host or choose an alias from ~/.ssh/config, then scan its listening ports.",
            "Select ports and choose local port numbers. Portman binds each tunnel to 127.0.0.1.",
            "SSH uses your existing keys and known-host policy. A tunnel ends when you stop it or quit MacPowerToys."
        ])
    ]

    static let shared = PortmanTool()
}

struct MacTweaksTool: Tool {
    let id = "mac-tweaks"
    let name = "Mac Tweaks"
    let description = "Find and control small Mac settings, starting with Mic Lock for Bluetooth headphone sound."
    let icon = "slider.horizontal.3"
    let logoAsset = "MacTweaksLogo"
    let category = ToolCategory.system
    let searchKeywords = ["mic lock", "microphone", "bluetooth", "airpods", "audio input"]

    let manual = [
        ToolManualSection(title: "Mic Lock", points: [
            "Open Mac Tweaks and turn on Mic Lock.",
            "Choose a primary microphone and up to three fallbacks. A disconnected choice stays saved.",
            "Mic Lock restores the first available choice when macOS changes input. If none is available, it selects a built-in or other non-wireless input."
        ])
    ]

    static let shared = MacTweaksTool()
}

struct SwitchTool: Tool {
    let id = "switch"
    let name = "Switch"
    let description = "Keep CLI accounts together, switch identities, and review usage."
    let icon = "person.2"
    let logoAsset = "SwitchLogo"
    let category = ToolCategory.dev
    let hasTrayTab = true
    let searchKeywords = ["account", "codex", "grok", "usage"]

    let manual = [
        ToolManualSection(title: "Accounts", points: [
            "Sign in to Codex CLI or Grok Build, or import an existing account folder.",
            "Choose Make Default to switch the account used by the corresponding CLI.",
            "Verify access, open the selected CLI, and refresh usage from the account detail view."
        ]),
        ToolManualSection(title: "Shared Store", points: [
            "Switch.app is optional. This applet and Switch.app use the same account store when both are installed.",
            "Recovery shows interrupted operations and linked settings that need repair."
        ])
    ]

    static let shared = SwitchTool()
}

// MARK: - Marketplace Tool

struct MarketplaceTool: Tool {
    let receipt: MarketplaceReceipt
    let iconFileURL: URL?

    var id: String { receipt.toolID }
    var name: String { receipt.name }
    var description: String { receipt.summary }
    var icon: String { "shippingbox" }
    var logoAsset: String { "" }
    var category: ToolCategory { receipt.category.toolCategory }
    var manual: [ToolManualSection] {
        receipt.manual.map { ToolManualSection(title: $0.title, points: $0.points) }
    }
}

// MARK: - Available Tools

struct ToolRegistry {
    static let builtInTools: [any Tool] = [
        RcloneTool.shared,
        LogsTool.shared,
        RulerTool.shared,
        AwakeTool.shared,
        ColorPickerTool.shared,
        TextExtractorTool.shared,
        InputDevicesTool.shared,
        SystemCareTool.shared,
        DiskExplorerTool.shared,
        SystemMonitorTool.shared,
        NetToysTool.shared,
        PortmanTool.shared,
        MacTweaksTool.shared,
        SwitchTool.shared
    ]

    static var allTools: [any Tool] {
        builtInTools + MarketplaceManager.shared.installedTools
    }

    static func tools(for category: ToolCategory) -> [any Tool] {
        if category == .all {
            return allTools
        }
        return allTools.filter { $0.category == category }
    }

    static func tool(for id: String) -> (any Tool)? {
        allTools.first { $0.id == id }
    }
}
