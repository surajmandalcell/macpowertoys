# PowerToys macOS - Specification

## Overview

A macOS utility application that lives in the menu bar, providing quick access to various productivity tools through a sidebar-based interface.

---

## Phase 1: Core Shell Implementation

### 1.1 Menu Bar Item

**Appearance:**
- Icon: Wrench in a rounded rectangle/box container
- Style: SF Symbol-based, monochrome, template image (adapts to light/dark mode)
- Size: 18x18 points (standard menu bar size)
- Icon options to consider:
  - `wrench.adjustable` - adjustable wrench
  - `wrench.and.screwdriver` - wrench with screwdriver
  - `gearshape` - gear (alternative)
  - Custom asset: wrench inside rounded rectangle

**Behavior:**
| Action | Result |
|--------|--------|
| Left-click | Opens the main PowerToys window |
| Right-click | Shows context menu |

**Context Menu Items:**
```
┌─────────────────┐
│ Open PowerToys  │
├─────────────────┤
│ Quit            │
└─────────────────┘
```

### 1.2 Main Window

**Window Properties:**
- Title: "PowerToys" (or hidden title bar)
- Size: ~800x600 points (resizable)
- Style: Unified toolbar with sidebar (NavigationSplitView)
- Position: Centered on screen initially

**Layout:**
```
┌──────────────────────────────────────────────────────┐
│  [x][_][+]                PowerToys                  │
├────────────────┬─────────────────────────────────────┤
│                │                                     │
│  [icon] All    │                                     │
│                │                                     │
│  CATEGORIES    │        Content Area                 │
│  ─────────     │                                     │
│  [icon] Text   │     (Tool-specific content          │
│  [icon] Files  │      displayed here)                │
│  [icon] System │                                     │
│  [icon] Dev    │                                     │
│                │                                     │
│                │                                     │
│                │                                     │
│  ─────────     │                                     │
│  [icon] Settings│                                    │
│                │                                     │
└────────────────┴─────────────────────────────────────┘
        │                       │
    ~200pt                  Flexible
```

### 1.3 Sidebar Categories (Phase 1 - Empty Placeholders)

Using SF Symbols (Apple's built-in icon system):

| Category | SF Symbol | Description |
|----------|-----------|-------------|
| All Tools | `square.grid.2x2` | Grid icon showing all available tools |
| Text | `textformat` | Text formatting/manipulation tools |
| Files | `folder` | File-related utilities |
| System | `gearshape.2` | System utilities |
| Dev | `hammer` | Developer tools |
| Settings | `slider.horizontal.3` | App settings (bottom of sidebar) |

---

## Architecture

### File Structure (Proposed)

```
powertoys/
├── App/
│   └── PowerToysApp.swift          # App entry point with MenuBarExtra
├── Features/
│   └── MainWindow/
│       ├── MainWindowView.swift    # Main NavigationSplitView
│       ├── SidebarView.swift       # Left sidebar with categories
│       └── ContentAreaView.swift   # Right content area
├── Models/
│   ├── Category.swift              # Category enum/model
│   └── Tool.swift                  # Tool protocol/base
├── Components/
│   └── SidebarItem.swift           # Reusable sidebar item component
├── Resources/
│   └── Assets.xcassets/
│       └── MenuBarIcon.imageset/   # Custom menu bar icon (if needed)
└── Utilities/
    └── WindowManager.swift         # Window open/close management
```

### Key SwiftUI Components

1. **MenuBarExtra** - Native SwiftUI menu bar support (macOS 13+)
2. **NavigationSplitView** - Sidebar + content layout
3. **SF Symbols** - System icons (no external dependencies)

---

## Technical Decisions

### Menu Bar Implementation Options

| Option | Pros | Cons |
|--------|------|------|
| **MenuBarExtra (SwiftUI)** | Native, simple, modern | macOS 13+ only |
| NSStatusItem (AppKit) | Works on older macOS | More code, bridging needed |

**Decision:** Use `MenuBarExtra` - target is macOS 26.2, well above requirement.

### Window Management

- Use `@Environment(\.openWindow)` for window opening
- Use `Window` scene type for the main window
- Keep app running when window closes (menu bar app behavior)

### Icon Strategy

1. **Menu Bar Icon:** Create a simple SF Symbol composition or custom asset
2. **Sidebar Icons:** Use SF Symbols exclusively (no external dependencies)

---

## Implementation Steps

### Step 1: Menu Bar Setup
- [ ] Replace `WindowGroup` with `MenuBarExtra` + `Window` scenes
- [ ] Create menu bar icon (SF Symbol or custom asset)
- [ ] Implement left-click to open window
- [ ] Implement right-click context menu

### Step 2: Main Window Shell
- [ ] Create main window with NavigationSplitView
- [ ] Implement sidebar with category items
- [ ] Add placeholder content area
- [ ] Style window (title bar, size, etc.)

### Step 3: Category Navigation
- [ ] Create Category model/enum
- [ ] Implement sidebar selection state
- [ ] Create content views for each category (empty placeholders)
- [ ] Add Settings section at bottom of sidebar

---

## Open Questions

1. **Menu bar icon design:** Should we use:
   - A simple `wrench` SF Symbol?
   - A `wrench` inside `app.badge` style container?
   - A custom drawn icon?

2. **Window behavior on close:** Should closing the window:
   - Hide the window (standard menu bar app behavior)?
   - Minimize to dock?

3. **First tool to implement:** After the shell is complete, which tool category should we prioritize?

---

## References

- [SF Symbols Browser](https://developer.apple.com/sf-symbols/)
- [MenuBarExtra Documentation](https://developer.apple.com/documentation/swiftui/menubarextra)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
