# PowerToys

A native macOS utility app built with SwiftUI, featuring a pluggable architecture for developer tools.

![Home](docs/screenshots/home_v1.png)

## Features

### Utility Suite

- **Ruler** - Floating horizontal, vertical, and joined rulers with calibrated units,
  region measurement, grouping, multi-display restoration, and developer copy formats.
- **Awake** - Passive, indefinite, timed, and expire-at power modes with optional
  display control, menu-bar access, presets, and process attachment.
- **Color Picker** - Native onscreen sampling with immediate copy, persistent history,
  pinning, search, and CSS, SwiftUI, AppKit, HEX, RGB, and HSL formats.
- **Text Extractor** - Private on-device Vision OCR for a selected screen region.
- **Raycast and Shortcuts** - Separate searchable commands for each utility through
  the included Raycast extension and Apple App Shortcuts.

### CC History

Browse and search your Claude Code conversation history with a clean, native interface.

- **Project-based organization** - Sessions grouped by project directory
- **Full-text search** - Search across all conversations
- **Message filtering** - Filter by User, Claude, System messages, tool calls, thinking blocks
- **Export options** - Export conversations as Markdown, JSON, or plain text
- **Syntax highlighting** - Code blocks rendered with proper highlighting

![CC History](docs/screenshots/cc_history1.png)

**Thinking blocks** - View Claude's reasoning process in expandable panels:

![CC History with Thinking](docs/screenshots/cc_history2.png)

### Logs

Real-time application logs with filtering and search.

- **Level filtering** - Filter by Error, Warning, Info, Debug
- **Search** - Full-text search across all log entries
- **Auto-pruning** - Logs older than 2 days are automatically cleaned up

![Logs](docs/screenshots/logs.png)

## Requirements

- macOS 26.2+
- Xcode 26.2+

## Building

```bash
git clone https://github.com/user/powertoys.git
cd powertoys
open powertoys.xcodeproj
```

Build and run with `Cmd+R` in Xcode.

## Architecture

```
powertoys/
├── Core/               # App infrastructure
│   ├── Models/         # SwiftData models
│   ├── LogManager      # Logging system
│   └── WindowState     # Window position persistence
├── Models/             # Domain models
├── Services/           # Business logic
│   ├── CCHistoryParser # JSONL conversation parser
│   ├── ProjectManager  # Project discovery
│   └── ExportManager   # Export functionality
└── Views/              # SwiftUI views
    ├── Components/     # Reusable UI components
    ├── CCHistory/      # CC History tool views
    ├── Ruler/          # Floating ruler controls and overlays
    ├── Awake/          # Power assertion controls
    ├── ColorPicker/    # Color history and copy UI
    ├── TextExtractor/  # Local OCR UI
    └── Logs/           # Logs tool views
```

Tools are pluggable - each tool implements the `Tool` protocol and registers in `ToolRegistry`. Tools can have their own dedicated windows with full UI customization.

The `raycast` directory contains a companion extension whose no-view commands call
the same stable action router used by App Intents, deep links, menus, and windows.

## License

MIT
