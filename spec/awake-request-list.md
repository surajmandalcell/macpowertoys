# Awake Request List

Reviewed against app source commit `a7bcb12` on 2026-07-14.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Keep the Awake window fixed instead of allowing it to grow. | `AwakeView` has a fixed 560pt by 500pt frame, its scene uses content-size resizability, and `WindowAccessor` removes the AppKit resizable style. | None. |
| Done | Vertically align Awake's titlebar items. | The shared 40pt `CompactTitlebar` applies one 4pt row inset and centers its title and switch on the same 22pt centerline. Unit coverage and the normal signed `98f35f6` build confirmed the alignment. | None. |
| Done | Move the traffic lights down for more breathing room. | `WindowAccessor` reapplies the shared 6pt downward offset after SwiftUI's delayed layout pass. Unit coverage and the normal signed `98f35f6` build confirmed the shared centerline. | None. |
| Done | Remove the green expand control and reuse its space. | `WindowAccessor` hides zoom, and the shared title inset moves from 84pt to 60pt so Awake occupies the vacated position. The normal signed `98f35f6` accessibility tree contained only close and minimize, with the title in the reclaimed space. | None. |
| Done | Keep the compact Awake titlebar aesthetically consistent. | Awake uses the shared 24pt controls, titlebar-only 6pt radius, complete-row inset, and borderless chrome. The normal signed `98f35f6` build matched the other three recent applets. | None. |
| Done | Make the existing `Keep Display On` titlebar switch configurable in Passive mode. | The enabled titlebar binding calls `AwakeService.setKeepDisplayOn`, which saves the setting even when no power assertion is active. The UI regression test toggles it in both directions. | None. |
| Done | Do not add a separate display button. | The Awake titlebar contains only the existing `Keep Display On` switch as its display control. | None. |
| Done | Remove the large focus outline shown around `Keep Display On` when Awake opens. | The switch disables the default focus effect, and every compact applet routes initial focus to its invisible window accessor. Fresh-open and cross-window focus checks in the normal signed `98f35f6` build showed no outline. | None. |
| Done | Remove the titlebar bottom border. | The shared `CompactTitlebar` renders no divider or separator. | None. |
| Done | Make the Awake app name bold. | Awake applies bold weight to its 13pt compact titlebar title. | None. |
