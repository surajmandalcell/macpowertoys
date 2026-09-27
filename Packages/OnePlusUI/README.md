# OnePlusUI

OnePlusUI is the shared SwiftUI component package for Suraj's macOS apps. It
contains the stable visual primitives extracted from Task Manager: the dark
palette, fixed titlebar geometry, panels, ordered dither, buttons, selects,
search, and segmented controls. `OnePlusUIShowcase` renders every component and
its common states in one fixed macOS window.

MacPowerToys uses the package through the checked-in local package reference:

```swift
import OnePlusUI
```

A fixed macOS tool window declares one content size in its scene and applies the
shared lifecycle-safe AppKit policy at the root:

```swift
Window("Task Manager", id: "task-manager") {
    TaskManagerView()
        .frame(width: 1080, height: 660)
        .background(OnePlusFixedWindowChrome(contentSize: CGSize(width: 1080, height: 660)))
}
.windowResizability(.contentSize)
```

Run the showcase from this directory with:

```sh
swift run OnePlusUIShowcase
```

The package stays inside MacPowerToys while it has one production consumer.
This keeps clean clones and hosted builds self-contained. When a second app
adopts it, move this directory to a dedicated `OnePlusUI` Git repository, tag a
semantic version, and replace the local Xcode package reference with its URL.
The product and module names do not change during that move.
