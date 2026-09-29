# Design Tokens (MUST FOLLOW)

All colors, type sizes, spacing, radii, geometry, window sizes, and motion
values live in one place: the `DESIGN.md` front matter, implemented by the
`OnePlusUI` package tokens. Do not restate them here or in code.

- Use OnePlusUI tokens and components. Never write raw colors, opacities, font
  sizes, radii, or paddings in app views.
- A value missing from the scale is a design change: add it to `DESIGN.md` and
  OnePlusUI first, then use it.
