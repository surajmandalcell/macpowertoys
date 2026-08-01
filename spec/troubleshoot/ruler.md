# Ruler Troubleshooting

## FreeRuler Parity Drift

- **Symptom:** The MacPowerToys Ruler has different geometry, controls,
  shortcuts, defaults, persistence, or settings from the pinned FreeRuler
  reference.
- **Cause:** A MacPowerToys customization was reintroduced or an upstream
  source file was edited inside the vendor directory.
- **Invariant:** Ruler product behavior follows FreeRuler commit
  `d38ca4f673f16c51485940e63eeee68babfbfeed`. The only permitted differences
  are MacPowerToys branding, on-demand host launch, host routing, and exclusion
  of standalone updater, app-icon, help, and App Store infrastructure.
- **Check:** Run `RulerCoreTests`, compare all 15 direct-copy Swift files with
  the pinned source using `cmp`, then compare the normal signed MacPowerToys
  ruler and settings windows with a same-machine build of the pinned commit.

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
