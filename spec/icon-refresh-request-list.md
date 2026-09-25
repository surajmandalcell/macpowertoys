# Tool icon refresh request list

Requested on 2026-09-25. The owner selected Disk Explorer option 02,
**Sector platter**, from `tmp/disk-explorer/index.index2.html` and asked for
System Care, Text Extractor, Input Devices, NetToys, and Color Picker to be
redesigned in a similarly crafted macOS icon language. This supersedes the
previously locked identities for those five tools.

| Status | Request | Acceptance |
|---|---|---|
| Verify | Promote Sector platter as Disk Explorer's icon. | The selected platter is a 512px RGBA asset and is wired into the launcher, Dock, and Raycast. |
| Verify | Redesign System Care. | A removable coral block leaves an empty slot in a cleanup tray. |
| Verify | Redesign Text Extractor. | A violet selection band lifts one text strip from an ivory card. |
| Verify | Redesign Input Devices. | An ivory mouse gives its violet scroll wheel the visual focus. |
| Verify | Redesign NetToys. | Three recessed network ports connect to one coral cable. |
| Verify | Redesign Color Picker. | An eyedropper touches a cluster of violet, coral, and cyan samples. |

The six icons should share rounded tiles, strong physical silhouettes, a
restrained material finish, and useful contrast at launcher and Dock sizes.
Preview each on light and dark surfaces and at 64 px and 16 px. The tool name
remains readable even if the smallest icon loses detail.

All six sources and Raycast copies are 512px PNGs. The focused Dock/icon tests,
Raycast icon sync check, Raycast lint, and Raycast build pass. The comparison
page is `tmp/icon-refresh/index.html`. Final acceptance still needs the clean,
signed installed app checked in the launcher and Dock.

## Second-round choices

On 2026-09-25, the owner rejected the current Portman, System Monitor, and Text
Extractor icon directions and requested ten distinct choices for each. No new
production icon is approved. Keep their current assets in place until the owner
selects replacements. Present all 30 choices together at full size and at
small launcher sizes, with no preselected option.

The owner also proposed shorter, wider launcher cards in two columns. Show a
reviewable comparison against the specified four-column layout before changing
the launcher. The proposed layout is a design option, not yet an approved
production change.

The 30 individually generated 512px RGBA choices and the switchable layout
study are in `tmp/icon-round-2/index.index2.html`; `prompts.md` records every
concept. A headless desktop render loaded every option and the compact layout,
and all 30 sources have transparent tile corners. At the standard 980pt content
width, the modeled four-column grid shows 12 of 13 built-in cards completely;
the proposed 80pt, two-column rows show all 13. The gallery keeps each 512px
source one click away and displays it at 64px and 16px. No icon or layout had
been selected at that review point.

## Owner selection and third-round review

On 2026-09-25, the owner selected **P01 Patch socket** for Portman. Promote
that exact 512px icon to the production asset; this icon choice is final.
System Monitor remains undecided. Generate two further variations each from
M02 Scope trace, M03 Core pulse, and M08 Fan sensor, exploring different
accent palettes and material treatments without losing each silhouette.
Text Extractor remains undecided. Generate two further variations each from
T01 Scan beam, T02 Lifted strip, and T03 Capture corners. Make the act of
scanning a line or sentence clear at small size; avoid decorative AI motifs.

The owner's current launcher screenshot has **three** columns, despite the
four-column specification and earlier gallery model. Diagnose that mismatch
and make a four-column comparison based on the real pane width. Keep the
short two-column layout as a separate option until the owner chooses.

P01 is now the exact production `PortmanLogo` source. The new comparison at
`tmp/icon-round-3/index.index2.html` shows the six references, twelve new
variations, and switchable three-, four-, and two-column launcher previews.
The old adaptive grid needed 976pt to fit four 220pt cards in the 980pt pane;
the observed scroller reservation leaves about 964pt before padding. An
offscreen SwiftUI repro places four sample cards on two rows at the resulting
916pt grid width. Four flexible columns place them on one row. The corrected
four-column launcher is a trial pending the owner's layout decision.
