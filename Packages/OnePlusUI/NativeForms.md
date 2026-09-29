# Compact and native form variants

`OnePlusTabStrip(layout: .applet)` uses the 16 pt applet gutter.
The default workspace gutter stays unchanged.
`OnePlusMenuTab` accepts an optional accessibility identifier for native tests.

Set `environment(\.onePlusControlHeight, OnePlusMetrics.controlHeight)`
to use 28 pt fields, select menus, segmented controls, and regular buttons
inside a compact menu panel. Small buttons remain 24 pt.

Native XIB forms can use these classes with module `OnePlusUI`:

- `OnePlusNativeWindowView`: opaque window body with window tokens.
- `OnePlusNativeCardView`: panel fill, border, and 8 pt radius.
- `OnePlusNativeCaptionLabel`: section caption style.
- `OnePlusNativeSwitchButton`: NSButton state and target/action with a switch.
- `OnePlusNativeStepperField`: editable number and native stepper. The
  existing number formatter supplies its limits. Target/action stays intact.

Call `OnePlusNativeForm.style` after loading a reusable controls nib.
Native titles, localization, accessibility labels, and key loops stay in
the owning application. These variants add no timers or observers.
