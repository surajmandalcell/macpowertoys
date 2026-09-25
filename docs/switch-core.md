# Switch Core in MacPowerToys

Switch is a built-in MacPowerToys workspace backed by the versioned
`AIManagerCore` Swift package from the separate Switch repository. Switch.app is
optional. The two apps have different SwiftUI interfaces and share only Core.

```text
Switch repository                         MacPowerToys repository
├── packages/core/                        ├── powertoys/Views/Switch/
│   └── Sources/AIManagerCore/ ──package─▶│   ├── SwitchWindowView.swift
├── packages/mac-gui/                     │   └── SwitchWorkspaceModel.swift
│   └── Switch.app UI                     ├── powertoys/Models/Tool.swift
└── packages/tui/                         └── powertoys.xcodeproj/
    └── Switch TUI                            └── AIManagerCore dependency
```

Both interfaces use Core's standard paths and cross-process operation lock.
Existing `~/Library/Application Support/AI Manager` data keeps that path for
compatibility; the repository and product are named Switch. MacPowerToys does
not launch Switch.app or depend on its GUI/TUI targets.

The Xcode project pins `AIManagerCore` to the Switch `3.2.1` package release.
To ship a Core change in both apps, release a new Switch package version, bump
the exact version in `powertoys.xcodeproj/project.pbxproj`, resolve and review
`Package.resolved`, run the isolated Core and MacPowerToys tests, then release
MacPowerToys. Updating an installed Switch.app alone cannot update an already
installed MacPowerToys binary.

Automated MacPowerToys tests set `AI_MANAGER_ROOT` to a disposable directory.
They do not inspect real auth files or the user's login Keychain. The normal
workspace uses Core's standard paths only when the user opens Switch.
