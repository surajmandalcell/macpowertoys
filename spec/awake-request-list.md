# Awake Request List

Reviewed against app source commit `a7bcb12` on 2026-07-14.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Keep the Awake window fixed instead of allowing it to grow. | `AwakeView` has a fixed 560pt by 500pt frame, its scene uses content-size resizability, and `WindowAccessor` removes the AppKit resizable style. | None. |
| Done | Vertically align Awake's titlebar items. | The shared 40pt `CompactTitlebar` centers its title and switch on the same 20pt centerline. | None. |
| Done | Move the traffic lights down for more breathing room. | `WindowAccessor` reapplies the shared 4pt downward offset after SwiftUI's delayed layout pass. | None. |
| Done | Remove the green expand control. | `WindowAccessor` hides the zoom button for Awake and every compact applet. | None. |
| Done | Keep the compact Awake titlebar aesthetically consistent. | Awake uses the shared flat titlebar with a text-only title, one discrete switch, balanced spacing, and no extra decorative chrome. | None. |
| Done | Make the existing `Keep Display On` titlebar switch configurable in Passive mode. | The enabled titlebar binding calls `AwakeService.setKeepDisplayOn`, which saves the setting even when no power assertion is active. The UI regression test toggles it in both directions. | None. |
| Done | Do not add a separate display button. | The Awake titlebar contains only the existing `Keep Display On` switch as its display control. | None. |
| Done | Remove the large focus outline shown around `Keep Display On` when Awake opens. | The switch disables the default focus effect, and the Awake window routes initial focus to its invisible window accessor. | None. |
| Done | Remove the titlebar bottom border. | The shared `CompactTitlebar` renders no divider or separator. | None. |
| Done | Make the Awake app name bold. | Awake applies bold weight to its 13pt compact titlebar title. | None. |
