# SwiftUI UI polish research

Reviewed on 2026-08-23 against Apple documentation and the current
MacPowerToys source.

## Findings

1. Use one system control size for adjacent controls. SwiftUI propagates
   `controlSize(_:)` through a view hierarchy. The `.small` size is for compact
   interfaces. Apply it to the complete workspace action group instead of to
   only some buttons.
2. Replace deprecated `borderlessButton` menu styling. Apple directs apps to
   use `.menuStyle(.button)` with `.buttonStyle(.borderless)`.
3. Keep branded sidebar artwork in original-rendering mode. SF Symbols can use
   the native selected foreground. A full-color tool tile must not become a
   one-color template when its row becomes selected.
4. Keep SwiftUI's semantic `Divider`, but lower its shared opacity. This keeps
   platform separator behavior while reducing repeated visual weight.
5. Put transient workspace status at the bottom safe-area inset. The inset
   reserves space for its content and anchors it to the specified edge. Do not
   place the status card after a fixed-height empty state inside a scroll view.
6. Use `animation(_:value:)` for state-driven changes. Keep motion short and
   limited to layout or content-state changes. Disable it when
   `accessibilityReduceMotion` is true.
7. Use explicit alignment guides and one shared control-group frame. Do not
   depend on different intrinsic heights to align a borderless menu with a
   bordered button.

## Sources

- [SwiftUI control sizes](https://developer.apple.com/documentation/swiftui/view/controlsize(_:))
- [SwiftUI small control size](https://developer.apple.com/documentation/swiftui/controlsize/small)
- [SwiftUI borderless menu migration](https://developer.apple.com/documentation/swiftui/menustyle/borderlessbutton)
- [SwiftUI Divider](https://developer.apple.com/documentation/swiftui/divider)
- [SwiftUI separator shape style](https://developer.apple.com/documentation/swiftui/shapestyle/separator)
- [SwiftUI safe-area inset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:))
- [SwiftUI alignment](https://developer.apple.com/documentation/swiftui/alignment)
- [SwiftUI animations](https://developer.apple.com/documentation/swiftui/animations)
- [SwiftUI Reduce Motion environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- [Apple sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple icon guidance](https://developer.apple.com/design/human-interface-guidelines/icons)
- [Apple button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons)
