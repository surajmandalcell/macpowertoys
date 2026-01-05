# Spec Q&A - Part 2

## Q19: Tool Details Panel Width
**A:** Resizable by user:
- Drag handle on left edge to adjust width
- Remember user's preferred width
- Min/max constraints to prevent unusable sizes

## Q20: Log Levels
**A:** 4 levels: Error, Warning, Info, Debug
- **Error**: Failures, crashes, exceptions
- **Warning**: Potential issues, degraded states
- **Info**: Normal events, operations completed
- **Debug**: Detailed debugging info (only when enabled in settings)

## Q21: Bookmark Update Indicator
**A:** Yes, dot indicator:
- Small dot badge on bookmark chip when conversation has new messages
- "New" = updated since user last viewed that conversation
- Clears when user opens the conversation

## Q22: Bookmark Slots Behavior
**A:** Only show filled bookmarks:
- Show only bookmarked items (1-5)
- "Add bookmark" via right-click on conversations, not via empty slots
- When at 5 bookmarks, show "Remove existing to add new" or replace flow
- Clean minimal UI - no empty placeholder slots

## Q23: Project Name Display
**A:** Formatted path (last 2 segments):
- Raw: `-Users-suraj-dev-myproject`
- Display: `dev/myproject`
- Shows context (parent folder) without full path clutter
- Real slashes instead of dashes

## Q24: Thinking Blocks Display
**A:** Separate tab/section:
- Thinking content NOT inline with conversation messages
- Dedicated "Thinking" tab or collapsible section in the UI
- Keeps main conversation view clean
- View thinking separately when interested

## Q25: Thinking Panel Implementation
**A:** Side panel toggle:
- Button in toolbar to show/hide thinking panel on right side
- Similar to tool details slide-over
- Can have both tool details AND thinking panel open concept
- Non-intrusive, on-demand

## Q26: Mid-Conversation Live Updates
**A:** Append silently:
- New messages added at bottom without disrupting scroll position
- If user is scrolled up, they stay where they are
- If user is at bottom, auto-scroll to show new content
- No toast/banner interruption

## Q27: macOS Version Target
**A:** macOS 14 (Sonoma):
- Modern APIs including SwiftData
- Good balance of compatibility and features
- Observable macro, improved SwiftUI
- Released Sept 2023, good adoption by now

## Q28: Database Framework
**A:** Use SwiftData:
- Modern, type-safe persistence
- Automatic migrations
- Native SwiftUI integration with @Query
- No need for raw SQLite or third-party wrappers

## Q29: Markdown Handling
**A:** Code blocks only:
- Syntax-highlight code fences
- Rest of message as plain text
- No heading/list/link rendering
- Keeps it clean and focused

## Q30: Syntax Highlighting
**A:** Yes, with language detection:
- Parse fence language (```python, ```swift, etc.)
- Apply language-specific syntax highlighting
- Fall back to generic if language unknown
- Use a library like Highlightr or similar

## Q31: Syntax Highlighting Library
**A:** SwiftSyntaxHighlight:
- Pure Swift implementation
- No JavaScript dependency (unlike Highlightr)
- Fewer languages but lighter weight
- Native performance

## Q32: CC History Settings Scope
**A:** Current settings are sufficient:
- Copy format preference
- Auto-refresh toggle
- No additional settings needed (theme, font size, etc.)
- Keep it minimal

## Q33: Project Tree State Persistence
**A:** SwiftData alongside cache:
- Store expand/collapse state in SwiftData model
- Part of the conversation cache system
- Persists across app restarts
- Consistent with other cached data

## Q34: Syntax Highlighting Library (Revised)
**A:** Search for Swift-native options:
- Find a pure Swift package for syntax highlighting
- Prioritize native performance over feature count
- Avoid JavaScript-based solutions like Highlightr
- Research options: Splash, swift-syntax, or custom solution

## Q35: Window Toggle Shortcut
**A:** No shortcut needed:
- Menu bar access is sufficient
- Double-click in sidebar opens tool windows
- Keep shortcut space clean for in-app navigation

## Q36: Deep Linking / Launch Options
**A:** Support both URL scheme AND CLI arguments:
- URL scheme: `powertoys://open/cchistory`
- CLI: `powertoys --open cchistory`
- Allows automation and integration with other tools
- Useful for scripting and launcher apps

## Q37: Error State Display
**A:** Empty state with icon + message:
- Centered illustration/icon in content area
- Helpful text explaining the issue
- E.g., "No conversations found" or "Cannot access ~/.claude"
- Clean, friendly approach

## Q38: Session Metadata Display
**A:** Both visible + hover details:
- Sidebar shows: date + message count visible
- Hover tooltip: additional details (duration, size, etc.)
- Date format: relative (Today, Yesterday, Jan 3)

## Q39: Partial Loading Display
**A:** Show partial content:
- Display messages as they're parsed
- Live-update the view as more content loads
- User sees immediate feedback
- No blocking spinner

## Q40: Sidebar List Limits
**A:** Virtualized sidebar:
- Lazy-load sidebar items for large histories
- Support 100+ projects without performance issues
- Smooth scrolling regardless of data size
- LazyVStack or similar approach

## Q41: Search Match Highlighting
**A:** Accent color:
- Use system accent color for search highlights
- Consistent with macOS conventions
- Respects user's accent color preference
- Clear visibility without harsh yellow

