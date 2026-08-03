# Compact Skin Copy Design

## Goal

Keep every fixed skin's home copy short while removing dotted decoration only from `material-df6388daee46-e3486a16`.

## Design

- Render a compact theme title of at most 12 visible characters.
- Hide the inherited long home headline and the secondary tagline.
- Keep native project controls, suggestion cards, composer controls, and click behavior unchanged.
- Expose the validated theme ID as a root data attribute so CSS can target one approved skin.
- For the identified skin only, disable the environmental particle layer, sidebar texture, and card pattern.

## Verification

- Renderer regression verifies compact title generation and the safe theme-ID attribute.
- CSS regression verifies the global compact-copy rules and the single-skin decoration override.
- Shared assets are regenerated and macOS/Windows payload tests must pass.
