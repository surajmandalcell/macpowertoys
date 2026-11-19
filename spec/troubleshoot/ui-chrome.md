# UI Chrome Troubleshooting

Each entry gives the symptom, cause, rule, and check. `DESIGN.md` wins over
any value here. Signed-build review of every entry stays an open item with the
orchestrator; see "Open signed checks" at the end.

## Scene Canvas Overrides The View Canvas

- **Symptom:** The installed main window opens at 1240 x 840 and Input Devices
  at 1080 x 660, although both views ask for 820 x 660.
- **Cause:** `MacPowerToysApp.windowContent(id:)` applies its own
  `onePlusFixedCanvas`. The outer canvas wins. Offscreen renders skip the wrapper.
- **Rule:** The scene wrapper, the scene `defaultSize`, and
  `OnePlusWindowCanvas.appTool(_:)` name the same canvas for each window.
- **Check:** `WindowAccessorTests.testSceneContentUsesTheSameCanvasAsTheWindowLookup`.
  Compare installed window sizes with `winlist`.

## Panel Glyphs And Disclosure Captions

- **Symptom:** The Input Devices count drops toward the header divider. Main
  panel tab glyphs use the 12pt role.
- **Cause:** A clear Refresh placeholder supplies a bottom baseline. Tabs copy an old size.
- **Rule:** Center the disclosure accessory group in the 40pt header; keep
  Refresh's own target. Tabs, headers, and status items use each tool's template
  asset. Tab glyphs use the 13pt token in 26pt targets. A status canvas is 14pt
  with 11.2pt centered ink.
- **Check:** Glyph tests cover status bounds at 1x, 2x, 4x. The Input Devices
  header test measures title, count, Refresh, and disclosure centers in both
  appearances, using a light-ink threshold that includes the thin Refresh glyph.

## Deferred Chrome Checks Miss Their Main-Queue Pass

- **Symptom:** The full package suite sees close x9 and centerline y16 while
  focused chrome checks pass at x13.
- **Cause:** Nested run-loop waits use their deadline before queued chrome work
  runs after a large bitmap sweep; some test windows stay open.
- **Rule:** Yield the main actor during a bounded wait, close offscreen windows,
  drain each large bitmap case, wait for scene size (no fixed sleep). Keep the
  13pt inset and native hover and hit-test assertions.
- **Check:** The full package suite and the focused chrome checks agree.

## Scroll Edges

- **Symptom:** The lower cards of a page cut off above the window bottom.
- **Cause:** Fixed page bodies had bottom padding outside the scroll view, and
  scrolling-page footers sat in a separate row below the viewport.
- **Rule:** A page-owned scroll viewport reaches the window bottom; card
  scrollers clip at the card edge. The 24pt gutter and footer clearance live
  inside scroll content. Fixed headers, table headers, inspectors, and card-page
  footers stay fixed. Consume the inset once so nested editors and strips do not
  inherit it. Empty footer slots take no height.
- **Check:** OnePlusPageTests: clip geometry at all shared canvas sizes, footer
  clearance, fixed regions, applet scroll end at every height bound.

## Fixed Controls Around Scrolling Rows

- **Symptom:** A title, search field, status card, inspector, or footer moves
  when a table scrolls. Page switches pause while rows format.
- **Cause:** One scroll view wraps the whole page, or row presentation sorts,
  formats, or scans files in `body`.
- **Rule:** Page controls stay outside the scrolling region; only rows scroll.
  Prepare row data in a cancellable task off the main actor. Use stable row IDs;
  no per-cell help, geometry readers, or file checks in row bodies.
- **Check:** Scroll each populated page; controls do not move. Page switches show
  content within 100ms. No synchronous file or process scan on the main actor.

## Tab Paint And Complete Row Hover

- **Symptom:** Tab hover hugs the label. Row hover stops before values, charts,
  or nested actions. Single-row tile content starts at the top.
- **Cause:** Hover uses a label-sized background or padded content instead of
  the complete row. Tile frames use top alignment.
- **Rule:** Page tabs paint a raised radius-5 surface 8pt past the label and
  count horizontally and 4pt vertically; frames and underlines stay fixed.
  Shared row hover covers the full rectangle and leaves nested controls active.
  Center a single row in its tile.
- **Check:** `OnePlusRowAndTabGeometryTests`: fixed frames, extended paint,
  complete native table rows, disabled hover, centered tiles.

## Header Top Line And Native Hover Containers

- **Symptom:** Header icons and controls start at y16 while native lights start
  at y20. Close starts at x9. Status text sits above button labels.
- **Cause:** Header actions center on the title line box. Native chrome lacked an
  x inset.
- **Rule:** Follow `DESIGN.md` "The content top line". Use `OnePlusHeaderActions`
  in shared headers and nested toolbars. Preserve native button frames, move the
  enclosing titlebar container, refresh ancestor tracking, repair late resets.
- **Check:** OnePlusHeaderRowTests (centers within 0.5pt) and
  OnePlusChromeAlignmentTests (all canvas recipes, x13, zoom gap, hit tests).

## Menu Hosts Ignore App Appearance

- **Symptom:** Dark captures show light panels while tool windows are dark.
- **Cause:** Diagnostics copy the app-level environment with its color scheme.
  Independent native hosts retain the appearance set when they open. Setting only
  `NSApp.appearance` replaces neither.
- **Rule:** Shared window, panel, popup, and sheet roots use
  `onePlusAppAppearance()`: it sets the SwiftUI scheme, clears pinned
  ancestor-view overrides, and updates native windows. Configure native hosts on
  attachment; the app observer updates live windows. Never reconfigure from
  appearance callbacks or add a competing preferred color scheme (a popover can
  stay busy). App-lifetime observers, weak window references, no polling.
  Register accessibility display changes on the workspace notification center.
  Native panel hosts stay independent of `MacPowerToysApp`'s full scene
  environment; copying it rebuilt the bridge and cost 36-56ms per tab switch.
  Main Open App uses `ToolActionRouter`, so no host needs a copied `openWindow`.
- **Check:** `testPresentationRootsFollowAppAppearanceAndLiveChanges` (dark,
  light, dark, Automatic). An offscreen probe shows an unused environment change
  does not rebuild the host.

## Nested Menu Body Accessibility

- **Symptom:** Portman paints its empty state but XCTest cannot find it. A panel
  reopens with an empty accessibility body.
- **Cause:** The nested `NSHostingView` copies the outer representable
  environment in full; the AX group then has no children.
- **Rule:** Give the nested host its own environment. Forward only the used
  public panel settings. Use the existing router for body window actions.
- **Check:** Tray Fan and Portman UI jobs find the body controls.

## Shared Table Geometry And Row Surfaces

- **Symptom:** Compact tables have short rows, or custom lists omit stripes and
  paint hover and selection in only one cell.
- **Cause:** Callers keep raw heights or omit the display-row index. SwiftUI
  Table paints its own selection and reuses row views.
- **Rule:** Use the DESIGN H and I table tokens in every density. Pass the
  current row position with stable record identity and refresh reused native row
  indexes. Keep SwiftUI's table style, grid color, delegate, and cells; paint row
  backgrounds and separators through the shared skin; hover and selection paint
  over the full stripe. Full values stay in help or accessibility text when truncated.
- **Check:** OnePlusTableTests (both native implementations, GridTable, both
  densities and appearances, hover exit, emphasized selection). Compare bitmaps
  to an independent captured sRGB swatch; cache-display bitmaps carry the display profile.

## Shared Native Control State And Paint

- **Symptom:** Selected table metadata loses ink. Popup key monitors consume
  modified input. External text changes break marked text or undo. Field errors
  move controls in fixed rows.
- **Cause:** AppKit propagates cell backgroundStyle. Monitors skip the owning
  window check. Text assignment bypasses editing. Captions share the control column.
- **Rule:** Selected metadata uses ink and restores its role on deselect;
  warning and error ink stay semantic. Draw row fills from `isEmphasized`. Read
  the native contrast preference (this macOS normalizes high-contrast appearance
  names while it is off). Filter action modifiers and popup windows before
  dispatch. Defer text replacement during marked text; clear undo on resource
  change. Fields stay centered in 44 and 56pt rows; recovery messages go to the
  group banner. Textures stay below content.
- **Check:** OnePlusUI offscreen suites for native input, search, popup,
  contrast, table, setting row, native form, and texture. Selected paint reaches
  4.5:1; native small steppers measure 17x20 in 24 and 28pt hosts.

## Button Caps And Glyph Centers

- **Symptom:** Button text sits above or below frame center. Action glyphs look
  larger than the adjacent text.
- **Cause:** SwiftUI centers the full line box including descender space. Local
  icon and arrow fonts override the control text role.
- **Rule:** Shared controls center the label cap bounds and glyph visual bounds.
  A native Label inherits one size and weight; icon variants show the icon only.
  A 32pt action `OnePlusMenuTile` uses compact control type and centers its Label
  with no caller font or frame overrides. Keep symbol rotation inside the icon.
- **Check:** In `Packages/OnePlusUI`, run
  `swift test --filter OnePlusButtonAlignmentTests` (painted centers within 0.5pt,
  both appearances, 1x and 2x, no window ordered). Measure glyph masks as
  blue-minus-green coverage; an absolute blue cutoff drops faint dark-mode pin edges.

## Focus Chrome And Responders

- **Symptom:** A custom control shows a large blue rectangle, or an outline stays
  after clicking elsewhere. Portman keeps only the first typed SSH host character.
  Reactivation drops valid keyboard and accessibility responders.
- **Cause:** Plain SwiftUI controls keep the default focus effect. AppKit keeps
  the old first responder on a click that cannot take focus. The policy reset
  nontext responders on every key-window notification and read the app key window.
- **Rule:** Apply `onePlusFocusPolicy()` at the shared root; draw focus only when
  Full Keyboard Access or VoiceOver is on (`OnePlusFocusPolicy.shared.showsFocus`).
  No local unconditional `focusEffectDisabled()`; keep controls named and keyboard
  operable. Register each native window once and use the notification window.
  Clear ordinary opening focus once. Preserve active text editors, native
  selection controls, and valid visible responders; clear only detached, hidden,
  disabled, or fully clipped ones (intersect `visibleRect` with bounds). A pointer
  click outside text editors and selection controls clears the old first
  responder first; native tables and lists keep focus after a row click. Text
  clicks keep only the caret. Every compact applet initially focuses its invisible
  window accessor.
- **Check:** `OnePlusFocusPolicyTests` and the three native offscreen
  regressions. Fresh-open each applet: no outline; Tab still activates controls.
  `OnePlusMenuLabel` focus paint still needs its owner's policy gate.

## Custom Selectable Interaction States

- **Symptom:** A custom row, card, or tab looks inert under the pointer.
- **Cause:** A plain SwiftUI button removed the native surface without
  replacement hover and pressed states.
- **Rule:** Custom selectable rows, cards, and tabs use
  `UtilityInteractionButtonStyle` (0.06 hover, 0.1 pressed; disabled does not
  react). Native controls, icon actions, disclosures, breadcrumbs, and destructive
  text actions keep their own treatment; informational rows get none. A filled
  selected tab keeps its accent opaque with 0.10 hover and 0.18 pressed overlays.
- **Check:** Every enabled custom item shows hover and pressed feedback.

## Search Mouse-Down Responder Cycle

- **Symptom:** The app hangs after a search click; the sample repeats
  NSTextField, NSView, and OnePlusSearchView `mouseDown` 494 times.
- **Cause:** An unhandled child event returns to the wrapper through
  `nextResponder`, and the wrapper sends it back to the same child. Removing
  `makeFirstResponder` alone still loops.
- **Rule:** Native field clicks stay in AppKit. A search wrapper may focus its
  field but never sends `mouseDown` back to that child. Keep Find selection
  separate from pointer dispatch.
- **Check:** The bounded offscreen native-click regression fails on the old
  source without hanging. An Xcode "Abort trap: 6" after a `DARWIN_USER_CACHE_DIR`
  I/O error is an environment failure, not a code result.

## Search Field Density

- **Symptom:** A content search looks like the larger padded sidebar search.
- **Cause:** Content searches reused the sidebar component or its padding.
- **Rule:** `SidebarSearchField` only in workspace sidebars. Content, toolbar,
  sheet, and popover searches use the native small `NSSearchField` in the shared
  slot, with progress beside it when loading.
- **Check:** Only the launcher and Logs sidebar searches use the padded style.

## Thin Scroll Indicators

- **Symptom:** A scroll view reserves a thick track or shows a full-size
  indicator.
- **Cause:** A surface bypassed the shared configuration, the bridge picked the
  first sibling or an ancestor scroll view, or the lookup ran only in a deferred
  block before AppKit finalized geometry.
- **Rule:** Every SwiftUI `ScrollView`, `Form`, `TextEditor`, `List`, and `Table`
  uses `.thinScrollIndicators()`; native scroll views call
  `configureThinScrollIndicators()`. The shared scroller draws a 4pt thumb (6pt
  with Increased Contrast) over content, no track, hidden when idle, hidden after
  0.9 seconds with no fade, native-width hit region. Resolve the sibling that
  hosts the modified view synchronously and again from AppKit layout; skip every
  ancestor scroll view (a `TextEditor` in a scrolling page configures its own);
  `enclosingScrollView` is the last fallback.
- **Rule (Cloud Sync):** The ignore-pattern editor viewport is 128pt, with the
  shared 11pt vertical inset, so the resting lower edge cuts no line.
- **Check:** `rg` count of scrolling sources equals the shared-modifier count;
  `showsIndicators: false` is absent. `ScrollIndicatorTests` cover the two-sibling
  and modifier lookups with no fixed main-queue delay.

## Workspace Pane Seams

- **Symptom:** A line or gap appears between a workspace sidebar and its body.
- **Cause:** A root inserted a divider between panes that already meet.
- **Rule:** Sidebar and opaque body sit directly together in a zero-spacing
  stack. No divider or spacer at the boundary.
- **Check:** Inspect each sidebar workspace root.

## Quiet Structural Separators

- **Symptom:** Hairlines divide the interface more strongly than the content.
- **Cause:** Visual `Divider` views used full native separator strength.
- **Rule:** Pane, card, row, tab, header, and sheet hairlines use `QuietDivider`
  (0.35 opacity, 0.55 with Increased Contrast). Menu and command separators stay native.
- **Check:** `rg "Divider()"` finds only the shared implementation and native menus.

## Settings Row Alignment

- **Symptom:** Toggles, pickers, and option groups float mid-card or start on
  different edges row to row.
- **Cause:** Intrinsic-width controls sat in a centered stack, or grid cells kept
  default alignment.
- **Rule:** Settings stacks align leading. A labeled row spans the card with its
  control trailing, or all controls share one leading grid column. Center only
  deliberate empty states and heroes.
- **Check:** At default and minimum widths, labels share an edge, controls share
  the control-column edge, nothing floats at the card midpoint.

## Inline Metadata And Sparse Pages

- **Symptom:** A short category, path, count, kind, time, or total takes a second
  row, or independent cards fill one narrow column of a wide pane.
- **Cause:** Every secondary value used a vertical stack; card groups used a
  fixed single column.
- **Rule:** Short title and metadata pairs share a first-baseline row with a 6 to
  8pt gap; the primary text truncates first. Independent cards use an adaptive
  grid with a 320pt minimum. Help, errors, previews, commands, and long paths
  keep their own lines.
- **Check:** Audit leading stacks with 0 to 4pt spacing at default and minimum
  widths.

## Workspace Actions And Bottom Status

- **Symptom:** A menu and adjacent button differ in height or baseline, or a
  status card floats above empty space.
- **Cause:** Controls relied on different intrinsic sizes; a status card was
  appended to scroll content.
- **Rule:** Top-strip actions use the native small size and a 24pt minimum.
  Pane-wide work status sits in one bottom safe-area inset, never in scroll content.
- **Check:** Menus and buttons share one centerline on every workspace; status
  stays at the bottom while work runs.

## Sidebar Status And Version Chrome

- **Symptom:** A sidebar shows a build version or a colored online or offline dot.
- **Cause:** Daemon and sampler state was surfaced as sidebar chrome.
- **Rule:** No sidebar, sidebar footer, or menu-bar tab summary shows a version
  or status dot. Keep recovery actions (Cloud Sync `Reconnect`) and put state in
  content rows. About and Settings may show the version.
- **Check:** `rg` sidebar views for `CFBundleShortVersionString`, version labels,
  and tinted `Circle()` fills.

## Product Copy Boundary

- **Symptom:** A task screen shows tradeoffs, API limits, research notes, or
  design-conversation text.
- **Cause:** Engineering rationale became persistent interface help.
- **Rule:** Task screens show names, values, state, and recovery actions. A
  technical limit goes in About only when it changes a decision.
- **Check:** Search visible strings for `public API`, `does not expose`,
  `not bundled`, `intentionally`, `never captures`.

## Permission-Dependent Features

- **Symptom:** A feature silently falls back or tells the user to open System
  Settings without first asking for its permission.
- **Rule:** The process that uses a protected API owns its permission manager
  (`PermissionCenter`), requests at the first eligible in-context use, and starts
  the native service when macOS needs that to show the prompt. Each feature and
  its Settings page show Not Requested, Denied, Restricted, Allowed, or Needs
  Attention with the matching action. Helpers publish their own state. Allowed
  with data still unavailable is Needs Attention.
- **Check:** Reset each permission and enter the feature; test denial,
  restriction, later approval, and allowed-but-unavailable.

## Global Shortcut Recording

- **Symptom:** Recording Command-Shift-3 shows `⇧⌘#`, or shows correctly but
  macOS takes the screenshot and the app action never runs. A launch opens behind
  a Device Control and Data Access prompt.
- **Cause:** `charactersIgnoringModifiers` keeps Shift for number-row keys. macOS
  reserves Command-Shift-3, so a Carbon hotkey cannot override it. Launch created
  the reserved-shortcut event tap at once.
- **Rule:** Every custom shortcut uses `ShortcutRecorderField`, which normalizes
  number-row key codes to `0` through `9`. Defaults: Color Picker `⇧⌘3`, Text
  Extractor `⇧⌘2`. Reserved screenshot chords use a suppressing session event
  tap, never Carbon, created only after a prompt-free Accessibility trust check.
  Without access, show an access action beside the recorder, leave the screenshot
  unchanged, and do not run the shortcut. Re-enable the retained tap inside the
  callback on either tap-disabled event.
- **Check:** A Command-Shift event with the shifted symbol records the physical
  number label. Command-Shift-3 from another app opens Color Picker, no screenshot.
  A normal launch shows no permission dialog.

## Tool Icon Tile Template

- **Symptom:** One tool icon has sharper corners or a different tile silhouette.
- **Cause:** An SVG appearance bypassed the shared tile template, or a render path
  trusted asset clipping, or a stale installed build kept the defect.
- **Rule:** Every light and dark SVG tool icon uses a `512 x 512` view box and a
  full-canvas `clipPath id="tile"` rectangle (`rx="112"`) clipping ground and art.
  Bitmap icons are 512px RGBA with transparent rounded corners. Every launcher,
  sidebar, grid, and tray path uses `toolIconTile(size:)`, radius `size x 112 / 512`.
  No special cases. See `spec/icons.md`.
- **Check:** Template, corner, and shared-renderer tests pass over every tool-logo
  asset, PNG, and SVG. The installed commit equals `HEAD`.

## Mac Tweaks Has No Previews

- **Symptom:** Mac Tweaks paired each card with a mock desktop, Dock, or Finder
  preview, forcing two columns and fixed card heights.
- **Rule:** The owner removed every preview and texture. Mac Tweaks is 820 x 660
  with one full-width column of cards, like System Settings, on every page and in
  search. No fixed heights or second column. Never reintroduce
  `MacTweaksPreviewView` or preview assets. OnePlusUI omits `OnePlusWindowTexture()`
  for `.macTweaks`.
- **Check:** `rg -n "MacTweaksPreview|MacTweaksGrain|MacTweaksRibbon" powertoys`
  returns nothing. Each page shows one column at 820pt, no ribbon.

## Mac Tweaks Shared Control Callers And Column Edges

- **Symptom:** Dock and Screenshots segments start 17 to 19pt after their
  selects. The System sidebar caption sits too close to Apps. Modified headings
  sit 4pt from their row values.
- **Cause:** The card width reached the select but not the segmented wrapper.
  The sidebar used standard caption spacing.
- **Rule:** Pass the card width to `OnePlusSegmented(width:)` through
  `MacTweaksSegmentedControl`. Use the shared section-start caption for System
  only. No transparent control frames or custom sidebar spacers. A Modified table
  (if shown) uses 16pt insets, 8pt gaps, 170pt value columns, a 28pt reset lane,
  and a fixed header.
- **Check:** Select and segment edges match in Dock and Screenshots in both
  appearances (package width regression: 160 and 180pt tracks). Setting, Current,
  and Original text edges align.

## Color Picker Settings Natural Height

- **Symptom:** Applet Settings stays 460pt tall with a gap after the last card.
- **Cause:** The page switch returned the maximum canvas height for Settings.
- **Rule:** Height is the measured card stack plus the 40pt titlebar, 16pt top
  gap, and 24pt bottom gutter, clamped to 250 to 460pt. Measure in the applet
  host so embedded Settings inherits its caller's geometry and density.
- **Check:** A 296pt stack requests 376pt; empty and long content stay in range.
  Check permission notices and scrolling at the cap.

## Applet Settings Embedding And Placement

- **Symptom:** Embedded settings collapse or gain extra gutters when page and
  settings both own scrolling and padding.
- **Rule:** Awake, Color Picker, Text Extractor, and Portman each expose one
  cards-only settings stack with 16pt gaps and inherited density. Only the main
  tool page renders it. Awake has no window; every Awake open route selects its
  main tool page. An applet or Portman gear and Command-comma call
  `ToolActionRouter.openMainPage(toolID:)`; applets keep only work pages (owner,
  2026-11-18). Where an applet still shows Settings, the gear is
  `OnePlusAppletSettingsButton` in the titlebar, left of the primary action,
  selected while open; Settings replaces the body from directly below the
  titlebar. Nothing floats over content; scrolling content ends 24pt above the
  window bottom as scroll padding. Cards fill the width between 16pt gutters.
- **Check:** `rg onePlusFloatingSettings` returns nothing. Check every card and
  the last control on the main tool page; the last card clears the bottom when
  scrolled to the end.

## Compact Applet Titlebar

- **Symptom:** Titlebar items sit high, actions differ in size, traffic lights
  align then jump 6pt up, or an applet can be resized.
- **Cause:** Native toolbar defaults bypassed the shared titlebar. AppKit restores
  its 16pt centerline after the startup passes. The title used its intrinsic
  height while actions used 24pt frames.
- **Rule:** Use the shared compact titlebar (`DESIGN.md` "Compact applets"): one
  40pt row, one 4pt top inset on the row and none on items, title and action
  frames both 24pt on the 22pt centerline, text-only title 60pt from the left,
  flat 24pt actions with the 6pt radius, accent fill on the primary only, no
  bottom separator. Hide zoom, remove the resizable style, give each applet a
  fixed root frame. Reapply the traffic-light offset after delayed layout and on
  every key-window change; never stack relative offsets.
- **Check:** Accessibility midpoints of close, title, and actions stay within 1pt
  of top + 22pt before and after a focus switch. The unit seam restores 22pt
  after a native reset to 16pt. Manual resizing fails.

## Settings Page Replacement

- **Symptom:** Home tabs stay above settings, or settings gains a false top margin.
- **Cause:** Home navigation rendered outside the page switch.
- **Rule:** Settings replaces applet home navigation and begins directly below
  the titlebar. The gear remains available to exit.
- **Check:** Enter settings from every home page; home navigation is absent, then
  returns on toggle.

## Menu Panel First Layout

- **Symptom:** Portman first appeared at 74pt then grew to 977pt. Tab changes
  first used the prior content height.
- **Cause:** Visibility mounted the body later. Geometry preferences changed
  height in a later SwiftUI update. Requested pages were selected after show.
- **Rule:** Keep layout mounted; visibility gates live work only. Measure the
  natural body height synchronously with fixed regions outside the scroller, cap
  scrolling at 90 percent of the visible screen, no layout animation. Native
  hosts consume `onOnePlusMenuHeightChange` in the final layout pass. Select
  pages and measure before presentation. Diagnostic Portman opens use
  `activateApp: false`.
- **Check:** `testTabSwitchCommitsOnlyTheDestinationHeight`, plus the hidden
  layout, fixed-region, and screen-cap tests.

## Panel Tab Icons Roll On Switch

- **Symptom:** Switching combined panel tabs rolls the icons and key for about
  170 ms.
- **Cause:** `OnePlusLinearIconTabs` set a 180 ms animation that overrode the
  host's disabled transaction, and the soft key used `matchedGeometryEffect`,
  which moves in window coordinates while the panel height changes.
- **Rule:** Panel tab key, glyph colors, and dividers change at once (OnePlusUI
  1.3.13). No matched geometry or animation on panel tabs.
- **Check:** An offscreen probe (hosting controller plus the resize callback,
  460 to 180 pt) comparing the tab bar every 16 ms shows zero changed pixels
  from the first frame.

## Awake Healthy Status Ink

- **Symptom:** The steady running sentence shows green.
- **Cause:** `AwakeStatusRow` maps an active session to the success state.
- **Rule:** Map steady healthy sessions to the online state: neutral row text,
  4pt filled dot, trailing Turn Off. Off is hollow and muted. Assertion errors
  keep error ink.
- **Check:** Recapture active, off, and error Home states in both appearances.

## Shared Control Accessibility

- **Symptom:** A sidebar lost its title identifier. Segment clicks missed the
  visible choice. Mac Tweaks choices lost identifiers.
- **Cause:** The sidebar's parent identifier replaced child metadata. A fake
  accessibility Picker used geometry different from the visible buttons.
- **Rule:** Make the sidebar a child-containing accessibility group. Keep each
  title and choice identifier. Expose the real segment buttons with selected
  traits, a group label, and arrow-key behavior.
- **Check:** Mac Tweaks and Tray Fan UI jobs pass.

## RSync UI Connector Labels

- **Symptom:** Long connector names scroll continuously while Add Remote is idle.
- **Cause:** The label used a repeating marquee animation.
- **Rule:** Truncate at the available width; expose the full name through the
  tooltip and accessibility value. The picker animates nothing while idle.
- **Check:** Leave Add Remote open with a long name: no label moves.

## Portman Panel Routing And Launch

- **Symptom:** A reopen returns to Servers. A diagnostic request for Servers shows
  the saved Settings tab. A cold `--open portman` launch shows no panel.
- **Cause:** The page lived in transient `@State`; diagnostics wrote the page
  preference after presentation. Scene routing ran before the status item had a
  visible window, and AppKit ignored the early show.
- **Rule:** One full menu-bar panel and a count-bearing status item, one route
  from the launcher, Raycast, Spotlight shortcut, and deep link. The default list
  shows user-owned development listeners; Settings can include others. Pages:
  overview, detail, cleanup, searchable settings, SSH forwarding. No alerts or
  notifications (owner choice). Save the selected page across panel recreation
  (Forward's pending scan selection stays transient); select the requested page
  and consume queued requests before building the host; deliver to a visible
  view. Settings state and editor discovery live in the panel owner; hosted
  content is released on close. Route the startup argument from the app delegate
  and present once after normal initialization: wait for a visible button window,
  a nonempty visible rect, and nonzero width, retry up to ten seconds, never poll
  while idle. An explicit tool route keeps the launcher closed.
- **Check:** Page-routing and Settings-state regressions on hosted CI. The hosted
  UI run opens `--open portman`, finds Servers before checking rows, and passes
  all four Portman cases. Open every entry route.

## Portman Overview Layout

- **Symptom:** The Memory scope label wraps. A server row, CPU summary, or Clean
  up clips below the panel; the empty overview clips or leaves a blank tail. Tabs
  and rows react only on their text.
- **Cause:** The segmented picker rendered a redundant label in a narrow slot.
  Height budgets were guesses. Each row added padding inside the overview gutter.
- **Rule:** Show listening-process memory (never whole-Mac), server rows, and the
  footer within the screen-height cap. The empty overview is 300pt with both card
  lines and `0 KB`. The memory bar and row hover share outer edges; rows pad their
  own text. Tabs and rows have full-width hit and hover regions. Servers, Forward,
  Settings are equal-width tabs; underline and label change at once. The footer
  holds server count, CPU, Sort by (Port ascending by default, Memory, Name, CPU
  descending), and Clean up. Settings uses the shared native small search field.
- **Check:** At 400pt with one, four, and many servers and the empty state: no
  clipping, row and bar frames match, Sort by works, searching Scan in Settings
  hides unrelated controls.

## Portman Rows, Hover, And Identity

- **Symptom:** A row repeats the node in title and subtitle, lacks process
  artwork, and shows gray port numbers beside colored bars. Link and Stop show on
  every row. Ports show as `:9,000`.
- **Cause:** Title and subtitle read the same fields; the projection dropped the
  executable identity. The mono text role overrides row color. The action
  condition treated the global focus policy as per-row focus. SwiftUI localized
  integer interpolation.
- **Rule:** Title is the project folder or launch command (process name if
  neither exists); subtitle is uptime plus a branch only when nonempty and
  distinct. Prepare strings in the background projection; read the executable
  path in the existing process scan; reuse the bundle artwork loader. Terminal
  glyph only for absolute executable paths outside app bundles; reserve a 15pt
  slot otherwise. Keep the 44pt port lane, 52pt row, 134pt metrics slot, and
  complete-row hover. One fixed trailing slot: graph plus memory at rest, link
  plus stop only on hover or that row's own keyboard or accessibility focus
  (memory and uptime stay in the details button's accessibility value). Port
  labels, memory segments, and sparklines use `OnePlusColor.portmanSeries`,
  passed to the port text's own `onePlusText` modifier. Memory legends use mono
  type with `OnePlusColor.metricCaption`. Render ports and PIDs as literal strings.
- **Check:** PortmanTests (app bundles, nested helpers, command-line and unknown
  paths, missing artwork, cache reuse and eviction), the action-condition test,
  and both appearances with one and many servers and four- and five-digit ports.

## Portman Detail Charts And Short Screens

- **Symptom:** The detail CPU chart spills past its plot and a hover timestamp
  moves the layout. A new detail has no chart until a second scan. Selected-cleanup
  Stop renders gray. A short-screen detail ends above Open localhost.
- **Cause:** The chart assumed a 100 percent ceiling and inserted its time label
  conditionally. The destructive role gave no red prominence.
- **Rule:** Detail charts use shared hover, a CPU ceiling covering all samples,
  fixed trailing axes, and a permanent timestamp row; show context from the first
  sample. The header holds localhost and more-actions with no menu chevron.
  Selected-cleanup Stop has an explicit prominent red style. Scroll when the
  screen-capped popover cannot fit the route.
- **Check:** At 400pt in both appearances: a CPU sample above 100 percent, chart
  alignment during hover, one and several samples, red Stop, Open localhost reachable.

## Portman Forward

- **Symptom:** Stale or false scan state: `Listening on` with no host, a port
  list under a blank host after reopen, a floating spinner, selection kept across
  tabs. The Failed row clips the SSH error. A `user@IP` host lacks password login.
- **Cause:** `discoveredHost` was set before the request finished, the previous
  result stayed in the shared service, and empty strings compared equal. Selection
  had no tab-exit reset. Both SSH paths forced key login.
- **Rule:** Results support checkbox, Shift-click range, Select all, Clear scan.
  Leaving Forward cancels the scan and clears selection; only Servers owns fast
  monitoring. One inline progress row with Cancel; clear the old result at scan
  start; set the host only after a successful response for the current host; show
  the port list only when a nonempty host matches the last scan. Active mappings
  stay visible. A failed row keeps the local endpoint and actions, with remote
  endpoint and error on separate lines (full text in the tooltip). Accept
  `user@IP`; use the in-memory askpass channel for a password, allow retry, clear
  the secret when Forward or the panel closes, never expose askpass paths. Link
  and Stop share native button dimensions.
- **Check:** Hosted: range select, leave and return; success, empty, invalid
  host, Cancel; scan, tunnel, close, reopen Forward; Failed Forward at real width.

## Portman Cleanup Settings

- **Symptom:** Clicking the idle threshold `4`, Delete, then `6` gave `64`.
- **Cause:** The test did not select the value; the caret sat before the digit.
  This alone does not prove a binding defect.
- **Rule:** Keep the cleanup threshold as a text draft while editing. On Return
  save only an integer in that setting's range; invalid text stays visible with an
  error. The three cleanup number fields share this. Automatic cleanup excludes
  high-usage servers.
- **Check:** Select `4`, type `6`, Return: shown and saved value is `6`. Enter
  `99`: draft and range error stay, saved value unchanged.

## Portman Closed-Menu Scan Cost

- **Symptom:** The menu-only owner ran a full socket and process scan every two
  seconds while the panel was closed.
- **Cause:** The live interval also drove the persistent status item.
- **Rule:** Use the chosen interval while the panel is open and at least 30
  seconds while only the status item shows. Opening triggers a fresh scan;
  disabling Portman releases its monitor.
- **Check:** Interval-policy regression; idle CPU with the panel open, closed,
  and disabled.

## Panel tab row hover flush with the text

- **Symptom:** Input Devices tab rows (Mouse, Trackpad, Scroll device) drew
  their hover and selected fill flush with the text.
- **Cause:** The tab used version 14 rows whose hover fill ran from the text
  edge with no inset.
- **Rule:** Every panel tab row uses `linearRowHover` (through OnePlusUI rows
  such as `OnePlusLinearDisclosureRow`) with text on `panelRowInset`, so the
  fill overflows the text by 6 pt on each side and nothing moves.
- **Check:** Offscreen render of each tab with a hovered row beside Home's
  Top processes hover.

## Open signed checks

The signed build still needs review in both appearances: canvas sizes, header
top lines and x13, hover paint, table scroll and reuse, applet centerline, focus
modes (none, Full Keyboard Access, VoiceOver), panel tab latency, Portman routes
and Forward, Mac Tweaks pages, the Cloud Sync editor, and Command-Shift-3.
