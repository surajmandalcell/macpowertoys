# Architecture

- SwiftUI macOS app
- Tools/plugins are on-demand only - never open automatically on app start
- Main window shows tool settings, actual tool interfaces open in separate windows
- Visual design: `DESIGN.md` (version 14) and the `OnePlusUI` package

# Code Principles (MANDATORY)

## Atomicity & Composition
- Shared UI components live in the `OnePlusUI` package (`Packages/OnePlusUI`)
  and are imported with `import OnePlusUI`
- Each component should do ONE thing well
- Prefer composition over duplication - if pattern appears twice, extract it
- A surface needs a different look: add a named variant to OnePlusUI, never a
  local restyle

## Single Source of Truth (SSOT)
- UI constants (colors, spacing, radii, type) are defined ONCE: `DESIGN.md`
  front matter, implemented by OnePlusUI tokens
- Reusable components define their own styling internally
- State should live at the lowest necessary level
- Use @AppStorage for persisted preferences, @State for ephemeral UI state

## Performance First
- NEVER block main thread with file I/O
- Use Task.detached for background work
- Minimize view body recomputation - extract expensive computed properties
- Use static let for expensive objects (formatters, regex)

## Maintainability
- No magic numbers - use named constants or computed properties
- Keep view bodies under 50 lines - extract subviews
- Prefer explicit over implicit - be clear about intent

## Text Selection & Interactivity
- NEVER put onTapGesture on containers with selectable text
- Use Button for clickable elements, not onTapGesture
- Keep interactive elements (buttons) separate from content
- Text logs/content must always be fully selectable

# UI Styling

`DESIGN.md` owns every visual rule: tokens, type, the 54 pt title row and its
centerline, sidebar, page, card, row, control, menu-panel, and applet anatomy,
and the native behavior contract. Build views from `OnePlusUI` components.

- Use `.windowStyle(.hiddenTitleBar)` and `OnePlusFixedWindowChrome` for window
  chrome. Never draw traffic lights.
- Use custom `HStack` sidebars, not `NavigationSplitView` or `NavigationView`.
- Use `Button` with full-row `.contentShape(Rectangle())` hit targets.
- Every scroll surface uses thin overlay indicators and never hides them.
- Test focus and unfocus states; defaults often change appearance.

# Window Management (CRITICAL)

## Window State Restoration
- NEVER restore window position asynchronously in SwiftUI views (causes visible jump)
- Use `AppDelegate` + `NotificationCenter` for window lifecycle
- Restore frame BEFORE window becomes visible

## AppDelegate Pattern
```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    private var restoredWindows = Set<ObjectIdentifier>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let windowId = ObjectIdentifier(window)
        guard !restoredWindows.contains(windowId) else { return }
        restoredWindows.insert(windowId)
        WindowStateManager.shared.restoreState(for: window)
    }
}
```

## Window Identifiers
- Set explicit identifiers: `window.identifier = NSWindow.Identifier("main")`
- Standard names: "main", "logs", "tool-{toolId}"

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
