# Design Tokens (MUST FOLLOW)

All spacing, colors, radii, and typography values are standardized. Do not deviate.

## Spacing

### Sidebar Layout
- Title: `.padding(.leading, 84)`, `.padding(.top, 8)`
- Search field container: `.padding(.top, 52)`, `.padding(.bottom, 12)`, `.padding(.horizontal, 12)`
- Search field inner: `.padding(8)`

### Content Area
- Top padding: `.padding(.top, 52)` - aligns with sidebar search bar top
- Content and search bar start at the same vertical position

## Colors

### Hover States
- **Standard hover**: `Color.primary.opacity(0.06)` - use this ALWAYS
- NEVER use: 0.05, 0.08, 0.12 for hover backgrounds

### Selection States
- Light selection: `Color.accentColor.opacity(0.1)`
- Strong selection: `Color.accentColor.opacity(0.2)`
- Only use 0.1 or 0.2 - no other values

### Backgrounds
- Content area: `Color(nsColor: .windowBackgroundColor)`
- Sidebar: `NSVisualEffectView` with `.sidebar` material

## Corner Radius Scale

Use only these values:
- **4pt**: Small buttons, toggles
- **6pt**: Text fields, search inputs
- **8pt**: List rows, message bubbles
- **12pt**: Cards, panels, large containers

## Typography

### Sidebar
- Title: `.system(size: 13, weight: .medium)`
- Row text: `.system(size: 13)`
- Section headers: `.system(size: 10, weight: .medium)`, `.foregroundStyle(.secondary)`

### Content
- Body text: `.system(size: 13)`
- Captions: `.system(size: 11)`
- Code: `.system(size: 12, design: .monospaced)`
