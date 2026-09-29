# MacPowerToys App and Tool Icons

Moved verbatim from DESIGN.md on 2026-09-29. DESIGN.md links here.


Icons follow the bold, friendly-flat language of current independent macOS
utilities. Each tool gets one oversized metaphor and enough personality to
remain recognizable without a label. The family has three approved treatments:
the tool's **Chosen Color** identity plus the neutral **Midnight** and
**Porcelain** appearance families.

## Appearance Strategy

The neutral appearance rule is intentionally inverted against the surrounding
desktop for stronger Dock separation:

- **Light macOS appearance uses Midnight.** The dark tile remains clearly bounded
  against a light desktop and light launcher surfaces.
- **Dark macOS appearance uses Porcelain.** The light tile remains clearly bounded
  against a dark desktop and dark launcher surfaces.
- A tool may explicitly keep its Chosen Color identity in one or both
  appearances. These exceptions are product decisions, not automatic palette
  substitutions.
- Appearance changes are implemented through asset-catalog luminosity variants.
  SwiftUI and AppKit always request the same named image. Do not add per-view or
  per-window theme branches.

#### Neutral Palette

| Family | Ground | Echo | Primary glyph | Contrast detail |
|---|---|---|---|---|
| Midnight | `#1C1D22` | `#5B5D66` | `#F4F4F5` | `#25262B` |
| Porcelain | `#E7E7EA` | `#A6A8AF` | `#25262B` | `#F4F4F5` |

Contrast detail is the optional opposing-color mark inside the primary glyph,
such as a cutout, screen, or graduation. It is never a ground, outline, or
second echo. Omit it when the metaphor does not need an internal detail.

Use these exact neutral shades. They are not aliases of the warmer Chosen Color
ink `#23272E` and paper `#F7F5F0`. Mixing the two neutral families within one
variant weakens the deliberate temperature and contrast difference.

#### Tool Appearance Matrix

| Tool | Light appearance | Dark appearance | Decision |
|---|---|---|---|
| Cloud Sync | Midnight | Chosen Color | Preserve the blue cloud echo in dark mode |
| Logs | Midnight | Porcelain | Use the neutral contrast inversion without an exception |
| Ruler | Chosen Color | Chosen Color | Orange identity is fixed in both appearances |
| Awake | Chosen Color | Chosen Color | Yellow eye identity is fixed in both appearances |
| Color Picker | Chosen Color | Chosen Color | Eyedropper with attached color samples |
| Text Extractor | Chosen Color | Chosen Color | Capture card with a selected text strip |
| Input Devices | Chosen Color | Chosen Color | Ivory mouse with a violet scroll wheel |
| System Care | Chosen Color | Chosen Color | Cleanup tray with one removable block |
| Disk Explorer | Chosen Color | Chosen Color | Owner-selected Sector platter |
| Task Manager | Chosen Color | Chosen Color | Midnight-blue display-and-metrics identity is fixed |
| NetToys | Chosen Color | Chosen Color | Network module with a connected coral port |
| Portman | Midnight | Porcelain | Neutral network-port glyph in both appearances |
| Switch | Original Switch mark | Original light and dark neutral tiles | Approved standalone Switch icon artwork |
| Mac Tweaks | Chosen Color | Chosen Color | Owner-selected 01 Faders in both appearances |

The 2026-09-25 owner request in `spec/icon-refresh-request-list.md` replaces
the prior identities for these six tools. They use 512px PNG image sets with
transparent rounded corners and one universal appearance. Their detailed
material finish follows the owner-selected Sector platter. All remaining tool
icons continue to follow the SVG construction rules below.

For SVG tools, the base `icon.svg` entry is the light-appearance asset. Add `icon-dark.svg`
with a `luminosity: dark` appearance only when the matrix calls for a different
dark asset. Tools that use Chosen Color in both modes keep one universal SVG.

Every new plugin adds its approved light and dark treatment to this matrix
before icon work begins. If its product brief has no approved Chosen Color
identity, use Midnight in light appearance and Porcelain in dark appearance.
An absent matrix row is a blocking metadata defect, never permission to guess a
palette or reuse another tool's semantic hue.

## Construction

- Every active SVG tool-icon appearance uses the same outer SVG template. This
  applies to every remaining SVG tool and light and dark variant.
- Use a `512 × 512` SVG view box and a full-canvas tile.
- Define `clipPath id="tile"` with a `512 × 512` rectangle and `rx="112"`.
  Wrap the ground and all artwork in `<g clip-path="url(#tile)">`.
- Every launcher, sidebar, grid, and tray rendering path also applies the shared
  `toolIconTile(size:)` mask. Its corner radius is `size × 112 ÷ 512`.
- Do not use a local corner radius or rely on the ground shape to clip later
  artwork. A bleeding glyph or band must never replace a rounded corner with a
  sharp one.
- Let the glyph occupy 60–72% of the tile width. Structural elements may bleed
  through the tile edge so the subject feels large instead of sticker-like.
- Build one literal metaphor from the fewest recognizable shapes. Prefer broad
  closed silhouettes and 28–64pt bands over detailed illustration or floating
  linework.
- Every exposed stroke uses `stroke-linecap="round"` and
  `stroke-linejoin="round"`. Round the ends of filled shapes too.
- Chosen Color icons normally create depth with meaningful overlap, such as one
  object passing behind another. Midnight and Porcelain use the approved solid
  echo construction below.
- Use punch-through details sparingly and only when they clearly read as a
  physical cutout. Never use one for a catchlight or decorative control.
- New Chosen Color icons use warm off-white `#F7F5F0` and charcoal `#23272E`,
  never pure white or black. The Chosen Color palette table is the binding
  legacy exception: Cloud Sync and Logs retain their listed
  `#FFFFFF` foregrounds. Neutral Midnight/Porcelain assets always use their own
  closed glyph tokens rather than either white.
- SVG icons use no decorative outline, gloss, blur, rim light, or soft drop
  shadow. A gradient is allowed only when color itself is the metaphor or part
  of an approved legacy Chosen Color asset. The six bitmap icons above keep
  their shallow material lighting from the approved visual direction.

The base application icon is the deliberate exception to the tool/plugin SVG
construction rules above. `powertoys/AppIcon.icon` uses Icon Composer's
`1024 × 1024` layered source canvas and solid document fill; its SVG layers
must not bake in the rounded-square ground or any lighting effect. The symbol
uses the same Lucide-derived outline flexed-arm geometry as the menu-bar glyph,
centered at roughly 58% of the source-canvas width so it remains clear at Dock
and Raycast sizes. Its secondary layer keeps the `52px` right/down echo offset
at that scale (`26px` on a 512 canvas), rather than adopting the tool-icon
`18 × 22` echo. Icon Composer supplies the system enclosure, lighting, and
prior-generation fallback.

## Solid Echo Construction

Midnight and Porcelain derive their depth from one flat copy of the semantic
glyph behind the foreground:

1. Construct the complete semantic foreground silhouette first.
2. Duplicate that silhouette once and place the copy behind the foreground.
3. Offset the echo by exactly `18px` right and `22px` down with
   `transform="translate(18 22)"`.
4. Fill or stroke the complete echo with the family echo token. Neutral echoes
   are fully opaque. They never use blur, gradients, blend modes, or multiple
   offsets.
5. Keep the echo's geometry, scale, rotation, line caps, and line joins identical
   to the foreground. Only its position and color differ.
6. The echo may be clipped by the rounded-square ground. Do not shrink the glyph
   merely to keep the echo inside the tile.

Compound glyphs must behave as one silhouette. Put all echo pieces inside one
`<g>` with one shared fill or stroke. When a Chosen Color legacy icon uses a
translucent semantic echo, apply `opacity` to the group, never to overlapping
children. This prevents darker seams where parts overlap.

At 32px the echo should read as a narrow lower-right depth cue, not a duplicate
icon. If it becomes a second symbol, the foreground is too small or the offset
has been changed.

## Chosen Color Palette

| Tool | Ground | Foreground | Semantic accent |
|---|---|---|---|
| Cloud Sync | `#1C1D22` | `#FFFFFF` at `.92` | `#5B8DEF` cloud echo at `.30` |
| Logs | `#475569` to `#0F172A` | `#FFFFFF` | Terminal prompt |
| Ruler | `#F04E23` | `#23272E` | Cream graduation cutouts |
| Awake | `#F5B71E` | `#23272E`, `#F7F5F0` | Cream eye catchlight |
| Task Manager | `#002B26` | `#E0FFF8` | M02 Scope trace identity |
| Mac Tweaks | `#25262B` and `#32333A` panel | `#F7F5F0` faders | `#AC86E8` center handle |

The six bitmap identities in the appearance matrix take their colors from
their approved `icon.png` assets, rather than this SVG palette table.

New Chosen Color tools should receive their own semantic hue unless a documented
product decision deliberately links them to an existing color. Neutral
appearance variants always use the closed Midnight or Porcelain palette instead
of inventing tool-specific grays.

## Asset Catalog Structure

An image set with different appearance assets uses this shape:

```json
{
  "images": [
    {
      "filename": "icon.svg",
      "idiom": "universal"
    },
    {
      "appearances": [
        {
          "appearance": "luminosity",
          "value": "dark"
        }
      ],
      "filename": "icon-dark.svg",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true
  }
}
```

- `icon.svg` is always the light-appearance result from the matrix.
- `icon-dark.svg` is always the dark-appearance result from the matrix.
- Both files remain vector SVGs at a `512 × 512` view box.
- Keep `preserves-vector-representation` enabled for appearance-aware image
  sets.
- If both appearances use the same Chosen Color icon, keep a single universal
  image entry (`icon.svg` or an approved `icon.png`). Do not duplicate an
  identical dark file.
- Launcher cards and the Dock use the same named asset. Do not create a separate
  Dock-only color treatment.

## Generation Workflow

The steps below apply to SVG tool icons. The six bitmap icons named in the
appearance matrix use 512px RGBA PNG sources, one universal image entry per
image set, transparent corners, and 512/64/32/16px visual checks.

1. Pick one literal object or action for the tool. Do not combine metaphors.
2. Sketch and approve one master semantic glyph at 512px using rounded filled
   shapes and broad round-capped bands. Make it larger than feels initially
   comfortable. Geometry is approved independently of its appearance palette.
3. Look up the tool in the appearance matrix. For a new plugin, add the required
   row using the rule above before continuing. Never assume every tool receives
   both neutral families.
4. Follow the matrix branch. If Chosen Color is approved, apply its documented
   palette to the master glyph. For each Midnight or Porcelain result, preserve
   the same master geometry and apply only the closed neutral palette plus the
   `18 × 22` solid echo. A neutral-only plugin produces Midnight and Porcelain
   directly and has no Chosen Color asset or invented semantic hue. Never
   redesign the metaphor between appearances.
5. Save the light result as
   `Assets.xcassets/<Tool>Logo.imageset/icon.svg`. Add `icon-dark.svg` and the
   luminosity appearance entry only when the dark result differs.
6. Validate every referenced SVG and preview each appearance from the repository
   root:

   ```sh
   xmllint --noout powertoys/Assets.xcassets/<Tool>Logo.imageset/icon.svg
   xmllint --noout powertoys/Assets.xcassets/<Tool>Logo.imageset/icon-dark.svg
   sips -s format png powertoys/Assets.xcassets/<Tool>Logo.imageset/icon.svg \
     --out /tmp/<Tool>-icon-light.png
   sips -s format png powertoys/Assets.xcassets/<Tool>Logo.imageset/icon-dark.svg \
     --out /tmp/<Tool>-icon-dark.png
   ```

7. Inspect every active appearance at 512, 64, 32, and 16px. The metaphor must
   still read at 32px, and the echo must remain a depth cue. At 16px the glyph
   may simplify, but it must not collapse into visual noise.
8. Build the app so `actool` validates `Contents.json`, both luminosity slots,
   and vector preservation. Check the icon once on a light desktop and once on a
   dark desktop before release.

Menu bar icons are the exception: use a single-color template silhouette of the
same metaphor because macOS controls their tint.

