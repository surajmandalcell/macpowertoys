# Architecture

- SwiftUI macOS app
- Tools/plugins are on-demand only - never open automatically on app start
- Main window shows tool settings, actual tool interfaces open in separate windows
- Sidebar: seamless blurred panel, Settings/Exit at bottom

# UI Styling (CRITICAL - Avoid Default/Native Ugliness)

## Window & Titlebar
- `.windowStyle(.hiddenTitleBar)` on WindowGroup - ONLY reliable way for seamless titlebar
- `NSVisualEffectView.state = .active` (NOT .followsWindowActiveState) - prevents appearance changes on focus loss
- DO NOT manually configure NSWindow properties (titlebarAppearsTransparent, etc.) - SwiftUI overrides them
- Sidebar extends seamlessly to top with traffic lights floating over it

## Sidebar (CONSISTENT ACROSS ALL WINDOWS)
- Use custom `HStack` layout, NOT NavigationSplitView or NavigationView (they add unwanted chrome)
- Custom `NSVisualEffectView` background with `.sidebar` material via `VisualEffectBackground()`
- Custom hover/selection states with `.contentShape(Rectangle())` for full-width hit targets
- Search bar with custom styling, not native `searchable` modifier

### Sidebar Title Pattern (EXACT for all windows):
```swift
Text("Title")
    .font(.system(size: 13, weight: .medium))
    .padding(.leading, 84)  // aligns with traffic lights
    .padding(.top, 8)
```

### Search Field Pattern (EXACT):
```swift
HStack(spacing: 6) {
    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
    TextField("Search...", text: $searchText).textFieldStyle(.plain).font(.system(size: 13))
    // clear button
}
.padding(8)
.background(Color.primary.opacity(0.06))
.clipShape(RoundedRectangle(cornerRadius: 6))
.padding(.horizontal, 12)
.padding(.top, 52)  // space for title + traffic lights
.padding(.bottom, 12)
```

### Content Area Alignment:
- Content starts at `.padding(.top, 52)` to align with sidebar search bar top
- Use `Color(nsColor: .windowBackgroundColor)` for content background

## Forms & Settings
- Use `.formStyle(.grouped)` with `.scrollContentBackground(.hidden)`
- Remove default Form padding when needed
- Custom section headers, not default gray boxes

## Buttons & Controls
- Use `.buttonStyle(.plain)` with custom hover states for sidebar/navigation items
- Add `.contentShape(Rectangle())` to make entire row clickable, not just text
- Custom backgrounds with `RoundedRectangle` and accent colors

## Lists & Grids
- Prefer `LazyVGrid` over `List` for tool grids - more control over styling
- Hide scroll indicators when appropriate: `ScrollView(showsIndicators: false)`
- Custom card styles with subtle backgrounds and hover effects

## General
- Always use `Color(nsColor: .windowBackgroundColor)` for content backgrounds to match system
- Avoid default SwiftUI chrome - if something looks "native but dated", customize it
- Test focus/unfocus states - defaults often change appearance undesirably

# Window Management (CRITICAL)

## Window State Restoration
- NEVER restore window position asynchronously in SwiftUI views (causes visible jump)
- Use `AppDelegate` + `NotificationCenter` for window lifecycle
- Restore frame BEFORE window becomes visible

## AppDelegate Pattern
```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    private var restoredWindows = Set<NSWindow>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !restoredWindows.contains(window) else { return }
        restoredWindows.insert(window)
        WindowStateManager.shared.restoreState(for: window)
    }
}
```

## Window Identifiers
- Set explicit identifiers: `window.identifier = NSWindow.Identifier("main")`
- Standard names: "main", "cc-history", "logs", "tool-{toolId}"

## Frame Validation
- Always clamp restored frames to visible screen bounds
- Handle multi-monitor setups (saved screen may no longer exist)

# Performance Patterns

## File I/O
- NEVER use `String(contentsOf:)` for files > 100KB - loads entire file into memory
- Use `FileHandle` with chunked reading (8-64KB chunks)
- Parse JSONL line-by-line, never load entire file at once

## Static Resources
- Use `static let` for DateFormatter, ISO8601DateFormatter, NSRegularExpression
- Never create formatters inside loops or SwiftUI view bodies
```swift
// GOOD
private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()

// BAD - creates new formatter on every call
func format(_ date: Date) -> String {
    let f = DateFormatter()  // Don't do this
    return f.string(from: date)
}
```

## SwiftUI Lists
- NEVER use `Array(collection.enumerated())` in ForEach - breaks SwiftUI diffing
- Use stable IDs: `ForEach(items, id: \.id)` or `ForEach(items)` if Identifiable

## Async Loading
- Use `Task.detached(priority: .userInitiated)` for background work
- Show loading indicators for operations taking > 300ms
- Use `actor` for thread-safe caches (not classes with locks)
