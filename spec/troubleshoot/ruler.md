# Ruler Troubleshooting

## FreeRuler Parity Drift

- **Symptom:** The MacPowerToys Ruler overlay has different geometry, controls,
  shortcuts, defaults, or persistence from the pinned FreeRuler reference.
- **Cause:** A MacPowerToys customization was reintroduced or an upstream
  source file was edited inside the vendor directory.
- **Invariant:** Ruler product behavior follows FreeRuler commit
  `d38ca4f673f16c51485940e63eeee68babfbfeed`. The only permitted differences
  are MacPowerToys branding, on-demand host launch, host routing, utility-token
  styling for both settings windows, independent Settings placement,
  adjustable border opacity, the default disabled shadow, and exclusion of
  standalone updater, app-icon, help, and App Store infrastructure.
- **Check:** Run `RulerCoreTests`. Compare the vendored Swift files with the
  pinned source and audit each difference against the permitted list. Then
  compare the normal signed MacPowerToys overlay with a same-machine build of
  the pinned commit.

## Ruler Settings Utility Chrome

- **Symptom:** Ruler Settings or Ruler Defaults returns to a narrow flat form,
  a transparent native titlebar, a bordered Defaults group, or duplicate body
  title.
- **Cause:** The pinned FreeRuler settings nib was treated as a visual source of
  truth after settings chrome moved to MacPowerToys utility tokens.
- **Invariant:** Both fixed 420pt windows use active HUD material in the body
  and opaque native titlebars. Do not add a custom titlebar material or drag
  overlay. They use 20pt outer edges, 16pt section gaps, 8pt
  heading gaps, and 14pt card insets. Cards use a 10pt radius and dynamic label
  color at 5%.
  Settings uses trailing secondary and primary actions. Defaults uses one quiet
  destructive action. Both windows keep their autosaved positions and displays.
  Settings never attaches to or follows a ruler. It keeps a target reference so
  controls update the intended ruler. Closing Settings leaves the ruler open.
  The native color panel can remain a child of Settings.
- **Check:** Compile all three XIBs. Run `RulerCoreTests` and the focused signed
  Ruler UI flow. Inspect light, dark, increased-contrast, reduced-transparency,
  English, German, and Japanese states. Confirm each native titlebar remains
  opaque and visibly distinct from the HUD body, with no overlap, 24pt hit frames,
  the complete key loop, Command-W dismissal, and focus return to the ruler.
  Move Settings from the native titlebar, move the ruler, and confirm that the
  Settings window stays in place.
  Close Settings and confirm that the ruler stays open.

## Ruler Border And Shadow Defaults

- **Symptom:** A new ruler has a strong border or a shadow, a saved shadow
  choice is lost, or Settings and Defaults show different border values.
- **Cause:** Drawing used a fixed 50% border, or one persistence and reset path
  did not include the new border value.
- **Invariant:** New and factory-reset rulers use a 25% border and no shadow.
  A saved shadow choice remains unchanged. Border Opacity uses one 0% to 100%
  value across per-ruler settings, defaults, JSON, drawing, reset, and
  save-as-default paths. Legacy per-ruler JSON uses 25% when the key is absent.
- **Check:** Run `RulerCoreTests`. Change Border Opacity in Settings and confirm
  an immediate border update. Save it as the default, create a ruler, reset the
  current ruler, and run the factory reset. Confirm each expected value. Enable
  the shadow, relaunch, and confirm that the saved choice remains enabled.

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
