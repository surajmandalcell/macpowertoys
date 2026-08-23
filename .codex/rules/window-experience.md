# Window Experience

Every top-level tool window must have a stable identifier and restore its last
display and position before it becomes visible. Resizable windows also restore
their last user-selected size. Fixed applets restore their defined size.

Treat window persistence as part of every new tool, not as later polish. Verify
restoration after relaunch, after display-layout changes, and with negative or
large multi-monitor coordinates.

Titlebars and bodies must form one coherent surface. Never ship an unintended
clear strip, opaque patch, focus-only material change, or visible restore jump.

Keep expensive tool work on demand. A closed tool window must not retain its
samplers, scans, event monitors, timers, or large caches unless a lightweight
menu-bar feature is explicitly enabled.
