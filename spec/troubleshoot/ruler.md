# Ruler Troubleshooting

## FreeRuler Parity Drift

- **Symptom:** The MacPowerToys Ruler overlay has different geometry, controls,
  shortcuts, defaults, or persistence from the pinned FreeRuler reference.
- **Cause:** A MacPowerToys customization was reintroduced or an upstream
  source file was edited inside the vendor directory.
- **Invariant:** Ruler product behavior follows FreeRuler commit
  `d38ca4f673f16c51485940e63eeee68babfbfeed`. The only permitted differences
  are MacPowerToys branding, on-demand host launch, host routing, utility-token
  styling for both settings windows, and exclusion of standalone updater,
  app-icon, help, and App Store infrastructure.
- **Check:** Run `RulerCoreTests`, compare all 15 direct-copy Swift files with
  the pinned source using `cmp`, then compare the normal signed MacPowerToys
  overlay with a same-machine build of the pinned commit.

## Ruler Settings Utility Chrome

- **Symptom:** Ruler Settings or Ruler Defaults returns to a narrow flat form,
  a transparent native titlebar, a bordered Defaults group, or duplicate body
  title.
- **Cause:** The pinned FreeRuler settings nib was treated as a visual source of
  truth after settings chrome moved to MacPowerToys utility tokens.
- **Invariant:** Both fixed 420pt windows use active HUD material through the
  body and behind their transparent native titlebars; never substitute a generic
  window-background slab. They use 20pt outer edges, 16pt section gaps, 8pt
  heading gaps, and
  14pt card insets. Cards use a 10pt radius and dynamic label color at 5%.
  Settings uses trailing secondary and primary actions. Defaults uses one quiet
  destructive action. Both windows keep their autosaved standalone positions;
  attached Settings continues to follow its persisted ruler. FreeRuler actions,
  outlets, persistence, shortcuts, localization keys, child attachment, and
  overlay behavior remain unchanged.
- **Check:** Compile all three XIBs. Run `RulerCoreTests` and the focused signed
  Ruler UI flow. Inspect light, dark, increased-contrast, reduced-transparency,
  English, German, and Japanese states. Confirm each native titlebar remains
  visibly distinct from the HUD body, with no overlap, 24pt hit frames,
  the complete key loop, Command-W dismissal, and focus return to the ruler.

## Ruler Launch Ownership

- **Symptom:** A ruler opens when MacPowerToys starts, or the launcher opens a
  blank SwiftUI Ruler window.
- **Cause:** FreeRuler's standalone startup behavior or the deleted
  `Window(id: "ruler")` scene was restored.
- **Invariant:** MacPowerToys owns discovery and launches FreeRuler on demand
  through `ToolActionRouter`. FreeRuler owns every ruler and Ruler settings
  window after launch.
- **Check:** Launch MacPowerToys with no restored windows, confirm no
  `ruler-window` exists, then open tool ID `ruler` and confirm one
  `ruler-window` with both ruler views appears.

## Command-W Closes The Ruler Once

- **Symptom:** Command-W closes the ruler and then also closes the MacPowerToys
  host window, or feels delayed while a ruler is active.
- **Cause:** A local-event-monitor adapter used
  `handler(event) ?? event`. The ruler handler intentionally returned `nil` to
  consume Command-W, but the nil-coalescing expression resurrected the same
  event. AppKit then dispatched it again after the ruler had closed, with the
  host window newly key.
- **Invariant:** The monitor returns the handler result verbatim while its
  delegate exists; `nil` means consumed. If the delegate has deallocated, it
  returns the original event. Exact Command-W closes the captured ruler
  synchronously, while additional modifiers pass through. Native command state
  publishes only when its rendered value changes during ruler interaction.
- **Check:** Unit-test the installed monitor closure, not only its downstream
  handler: exact Command-W returns nil, extra-modifier Command-W returns the
  identical event, the key-window transition leaves the host open, and a
  deallocated delegate returns the event. In the signed UI build, confirm the
  ruler disappears while MacPowerToys remains running with its host window.
