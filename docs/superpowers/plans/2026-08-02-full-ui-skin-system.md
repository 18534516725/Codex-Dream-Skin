# Codex Full UI Skin System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the original 12 skins and add 6 original cartoon/pixel skins so all 18 alter the real Codex home, sidebar, composer, surfaces, selection states, texture, and motion while preserving native functionality.

**Architecture:** Extend the existing trusted `theme.json.visual` contract with validated layout and component-style fields. The renderer converts that profile into root data attributes and CSS variables; a single synchronized CSS runtime applies the selected home layout, surface system, sidebar/composer styling, and bounded decorative motion on both macOS and Windows. High-resolution artwork remains a separate, versioned asset set and never contains fake UI text.

**Tech Stack:** Swift menu-bar app, Bash and Node.js theme writers, PowerShell 5.1 Windows installer, DOM/CSS runtime injection, Node test runner, ImageGen-generated WebP assets, React/Vite admin preview.

---

## File map

- `macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift`: macOS fixed-theme catalog and strongly typed deep-theme profile.
- `macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift`: forwards the selected profile to the installed theme loader.
- `macos/scripts/load-image-theme-macos.sh`: accepts profile flags and invokes the writer.
- `macos/scripts/write-theme.mjs`: validates and serializes the extended `visual` profile.
- `windows/scripts/theme-windows.ps1`: Windows fixed-theme catalog with the same 18 profiles.
- `windows/scripts/apply-community-theme.ps1`: serializes the Windows profile into `theme.json`.
- `runtime/renderer-inject.js`: maps profile values to bounded root attributes and CSS variables.
- `runtime/dream-skin.css`: real Codex home/sidebar/composer layout, surface styling, motion, fallbacks, and reduced-motion rules.
- `macos/assets/dream-skin.css`, `windows/assets/dream-skin.css`, `macos/assets/renderer-inject.js`, `windows/assets/renderer-inject.js`: generated synchronized runtime copies.
- `artwork/masters/*.png`: selected lossless 4K working masters for 18 themes.
- `artwork/palettes/*.json`: explicit color and pixel-grid constraints for each theme.
- `frontend/public/codex-skins/originals/*.webp`: production 4K skin artwork.
- `frontend/public/codex-skins/previews/*.webp`: lightweight admin gallery previews.
- `frontend/src/pages/CodexSkins/skinCatalog.ts`: 18-theme public catalog metadata.
- `frontend/scripts/validate-codex-skin-assets.mjs`: exact asset count, dimensions, size, and pixel-theme checks.

### Task 1: Define the extended deep-theme contract

**Files:**
- Modify: `macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift`
- Modify: `macos/tests/nexo-vivid-profile.test.mjs`
- Modify: `windows/tests/nexo-vivid-profile.test.mjs`

- [ ] **Step 1: Write failing contract tests**

Add assertions for the new fields and 18 exact profiles:

```js
for (const field of [
  "layoutVariant", "surfaceStyle", "cornerStyle", "motionPreset",
  "sidebarStyle", "composerStyle", "textureStyle",
]) {
  assert.match(contract, new RegExp(`public let ${field}: String`));
}
assert.equal([...contract.matchAll(/^\s*"[a-z0-9-]+":\s*\.init\(/gm)].length, 18);
for (const id of [
  "post-raccoon", "night-shift-penguin", "workshop-otter",
  "moon-platform-cat", "floppy-wizard", "deep-sea-repair",
]) assert.match(contract, new RegExp(`"${id}"`));
```

- [ ] **Step 2: Run tests and verify the old 12-field contract fails**

Run: `node macos/tests/nexo-vivid-profile.test.mjs && node windows/tests/nexo-vivid-profile.test.mjs`

Expected: FAIL because the new fields and six IDs are absent.

- [ ] **Step 3: Extend the Swift profile and populate 18 explicit records**

Use a bounded struct rather than free-form CSS:

```swift
public struct NexoSkinVisualProfile: Equatable, Sendable {
  public let accentRGB: String
  public let secondaryRGB: String
  public let panelRGB: String
  public let glowStrength: Double
  public let signature: String
  public let focusX: Double
  public let focusY: Double
  public let layoutVariant: String
  public let surfaceStyle: String
  public let cornerStyle: String
  public let motionPreset: String
  public let sidebarStyle: String
  public let composerStyle: String
  public let textureStyle: String
}
```

Populate every record directly. The six new records use these IDs and primary styles:

```swift
"post-raccoon": .init(accentRGB: "218 67 66", secondaryRGB: "241 190 92", panelRGB: "18 29 48", glowStrength: 0.54, signature: "POST RACCOON", focusX: 0.74, focusY: 0.48, layoutVariant: "poster-right", surfaceStyle: "paper", cornerStyle: "ticket", motionPreset: "mail", sidebarStyle: "postal", composerStyle: "label", textureStyle: "halftone"),
"night-shift-penguin": .init(accentRGB: "224 182 80", secondaryRGB: "250 225 151", panelRGB: "17 16 14", glowStrength: 0.48, signature: "NIGHT SHIFT", focusX: 0.70, focusY: 0.46, layoutVariant: "stage", surfaceStyle: "metal", cornerStyle: "round", motionPreset: "spotlight", sidebarStyle: "setlist", composerStyle: "mixer", textureStyle: "vinyl"),
"workshop-otter": .init(accentRGB: "43 179 163", secondaryRGB: "239 132 73", panelRGB: "24 39 40", glowStrength: 0.50, signature: "WORKSHOP OTTER", focusX: 0.72, focusY: 0.47, layoutVariant: "collage", surfaceStyle: "paper", cornerStyle: "tape", motionPreset: "doodle", sidebarStyle: "notebook", composerStyle: "workbench", textureStyle: "crayon"),
"moon-platform-cat": .init(accentRGB: "241 170 72", secondaryRGB: "105 133 211", panelRGB: "13 18 43", glowStrength: 0.46, signature: "MOON PLATFORM", focusX: 0.75, focusY: 0.50, layoutVariant: "pixel-platform", surfaceStyle: "pixel", cornerStyle: "pixel", motionPreset: "pixel-rain", sidebarStyle: "station", composerStyle: "pixel-console", textureStyle: "dither"),
"floppy-wizard": .init(accentRGB: "169 105 237", secondaryRGB: "82 213 224", panelRGB: "22 15 42", glowStrength: 0.60, signature: "FLOPPY WIZARD", focusX: 0.69, focusY: 0.45, layoutVariant: "pixel-desktop", surfaceStyle: "pixel", cornerStyle: "pixel", motionPreset: "cursor", sidebarStyle: "file-tree", composerStyle: "dialog", textureStyle: "scanline"),
"deep-sea-repair": .init(accentRGB: "54 190 182", secondaryRGB: "241 112 85", panelRGB: "10 31 39", glowStrength: 0.52, signature: "DEEP SEA REPAIR", focusX: 0.72, focusY: 0.50, layoutVariant: "pixel-console", surfaceStyle: "pixel", cornerStyle: "pixel", motionPreset: "sonar", sidebarStyle: "submarine", composerStyle: "sonar", textureStyle: "dither"),
```

- [ ] **Step 4: Mirror the 18 records in the Windows catalog test fixture**

Require the same enumerated values and reject unknown style strings.

- [ ] **Step 5: Run both profile tests**

Expected: both print their `passed` messages.

- [ ] **Step 6: Commit**

```bash
git add macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift macos/tests/nexo-vivid-profile.test.mjs windows/tests/nexo-vivid-profile.test.mjs
git commit -m "feat: define eighteen deep skin profiles"
```

### Task 2: Serialize the extended profile safely on macOS and Windows

**Files:**
- Modify: `macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift`
- Modify: `macos/scripts/load-image-theme-macos.sh`
- Modify: `macos/scripts/write-theme.mjs`
- Modify: `windows/scripts/theme-windows.ps1`
- Modify: `windows/scripts/apply-community-theme.ps1`
- Test: `macos/tests/nexo-vivid-profile.test.mjs`
- Test: `windows/tests/nexo-vivid-profile.test.mjs`

- [ ] **Step 1: Add failing serialization assertions**

For each field, assert the Swift app passes a CLI flag, the Bash loader accepts it, and the writer emits it. Assert Windows emits the identical property names.

```js
for (const [flag, field] of [
  ["--layout-variant", "layoutVariant"], ["--surface-style", "surfaceStyle"],
  ["--corner-style", "cornerStyle"], ["--motion-preset", "motionPreset"],
  ["--sidebar-style", "sidebarStyle"], ["--composer-style", "composerStyle"],
  ["--texture-style", "textureStyle"],
]) {
  assert.match(appDelegate, new RegExp(`"${flag}"[\\s\\S]*entry\\.visual\\.${field}`));
  assert.match(loader, new RegExp(flag));
  assert.match(writer, new RegExp(field));
}
```

- [ ] **Step 2: Run tests and verify failure**

Expected: missing-flag assertions fail.

- [ ] **Step 3: Implement enum validation in `write-theme.mjs`**

```js
const enumValue = (key, allowed, fallback) => {
  const value = valueFor(key) || fallback;
  if (!allowed.includes(value)) fail(`${key} is invalid`);
  return value;
};
visual.layoutVariant = enumValue("layout-variant", ["poster-right", "stage", "collage", "editorial", "console", "pixel-platform", "pixel-desktop", "pixel-console"], "editorial");
visual.surfaceStyle = enumValue("surface-style", ["glass", "paper", "metal", "ink", "pixel"], "glass");
visual.cornerStyle = enumValue("corner-style", ["round", "cut", "ticket", "tape", "stamp", "pixel"], "round");
```

Apply the same whitelist principle to motion, sidebar, composer, and texture fields.

- [ ] **Step 4: Forward all fields from Swift and Bash**

Append the seven fixed flags to the loader argument list. Do not accept raw CSS or URLs.

- [ ] **Step 5: Mirror fields in PowerShell**

Each catalog entry gets the same field names, and `apply-community-theme.ps1` writes them under `visual`.

- [ ] **Step 6: Run profile and PowerShell syntax tests**

Run:

```bash
node macos/tests/nexo-vivid-profile.test.mjs
node windows/tests/nexo-vivid-profile.test.mjs
bash -n macos/scripts/load-image-theme-macos.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add macos windows
git commit -m "feat: serialize deep skin presentation profiles"
```

### Task 3: Map profiles into renderer state

**Files:**
- Modify: `runtime/renderer-inject.js`
- Create: `macos/tests/deep-skin-renderer-profile.test.mjs`

- [ ] **Step 1: Write a failing renderer contract test**

Assert bounded attributes and no raw profile string interpolation:

```js
for (const attr of [
  "data-dream-layout", "data-dream-surface", "data-dream-corners",
  "data-dream-motion", "data-dream-sidebar-style", "data-dream-composer-style",
  "data-dream-texture",
]) assert.match(renderer, new RegExp(attr));
assert.match(renderer, /const PROFILE_ENUMS\s*=\s*Object\.freeze/);
```

- [ ] **Step 2: Run and verify failure**

Run: `node macos/tests/deep-skin-renderer-profile.test.mjs`

- [ ] **Step 3: Implement enum-to-attribute mapping**

```js
const PROFILE_ENUMS = Object.freeze({
  layoutVariant: ["poster-right", "stage", "collage", "editorial", "console", "pixel-platform", "pixel-desktop", "pixel-console"],
  surfaceStyle: ["glass", "paper", "metal", "ink", "pixel"],
  cornerStyle: ["round", "cut", "ticket", "tape", "stamp", "pixel"],
  motionPreset: ["none", "petals", "rain", "scan", "sparks", "orbit", "mist", "ink", "mail", "spotlight", "doodle", "pixel-rain", "cursor", "sonar"],
});
function setProfileAttribute(root, attribute, key, fallback) {
  const allowed = PROFILE_ENUMS[key];
  const value = allowed.includes(VISUAL[key]) ? VISUAL[key] : fallback;
  root.setAttribute(attribute, value);
}
```

Also set sidebar, composer, and texture from their enumerated maps.

- [ ] **Step 4: Run the renderer test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add runtime/renderer-inject.js macos/tests/deep-skin-renderer-profile.test.mjs
git commit -m "feat: expose deep skin profile to the renderer"
```

### Task 4: Build the real Codex full-interface theme layer

**Files:**
- Modify: `runtime/dream-skin.css`
- Modify: `macos/tests/signature-skin-css.test.mjs`
- Create: `macos/tests/deep-skin-layout-css.test.mjs`

- [ ] **Step 1: Write failing CSS behavior tests**

Assert all three home layout families, five surfaces, six corner systems, themed sidebar/composer selectors, task-page reading veil, and reduced motion.

```js
for (const value of ["poster-right", "stage", "collage", "pixel-platform", "pixel-desktop", "pixel-console"]) {
  assert.match(css, new RegExp(`data-dream-layout="${value}"`));
}
for (const value of ["paper", "metal", "ink", "pixel"]) {
  assert.match(css, new RegExp(`data-dream-surface="${value}"`));
}
assert.match(css, /prefers-reduced-motion:\s*reduce[\s\S]*animation:\s*none/);
```

- [ ] **Step 2: Run and verify failure**

Run: `node macos/tests/deep-skin-layout-css.test.mjs`

- [ ] **Step 3: Add the shared component token layer**

Define tokens only; do not duplicate complete rules for every skin:

```css
html[data-dream-skin="active"] {
  --ds-card-radius: 18px;
  --ds-card-border: rgb(var(--ds-accent-rgb) / .34);
  --ds-card-shadow: 0 18px 46px rgb(0 0 0 / .28);
  --ds-reading-veil: .24;
  --ds-sidebar-texture-opacity: .16;
}
html[data-dream-corners="pixel"] { --ds-card-radius: 0px; --ds-card-shadow: 6px 6px 0 rgb(0 0 0 / .42); }
html[data-dream-corners="ticket"] { --ds-card-radius: 8px 18px 8px 18px; }
```

- [ ] **Step 4: Implement home layout variants using real native nodes**

Use existing home and suggestion selectors. Reflow native buttons into themed cards and keep their original click handlers.

```css
html[data-dream-layout="poster-right"] __DREAM_SELECTOR_HOME_ROUTE__ > div:first-child > div:first-child {
  grid-template-columns: minmax(420px, .9fr) minmax(520px, 1.1fr);
  align-items: end;
}
html[data-dream-layout="pixel-desktop"] __DREAM_SELECTOR_HOME_SUGGESTIONS__ {
  display: grid !important;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  image-rendering: pixelated;
}
```

- [ ] **Step 5: Implement surface, sidebar, composer, and selection systems**

Add paper grain/halftone using CSS gradients, metal inset borders, ink wash, pixel/dither patterns, sidebar motif separators, composer frames, focus glow, and theme-consistent native button styling. Decorative pseudo-elements must use `pointer-events: none`.

- [ ] **Step 6: Implement restrained task-page mode**

On non-home routes, preserve wallpaper but apply the profile-colored reading veil and remove large hero decorations. Sidebar and composer styling remain active.

- [ ] **Step 7: Add bounded motion presets**

Implement motion with pseudo-elements and `transform`/`opacity` only. Each preset exposes at most one continuous environmental animation and hover/focus micro-interactions.

- [ ] **Step 8: Run CSS tests**

Run:

```bash
node macos/tests/deep-skin-layout-css.test.mjs
node macos/tests/signature-skin-css.test.mjs
node macos/tests/native-immersive-css.test.mjs
```

Expected: PASS.

- [ ] **Step 9: Synchronize runtime assets and verify**

Run:

```bash
node tools/sync-runtime-assets.mjs
node tools/sync-runtime-assets.mjs --check
```

- [ ] **Step 10: Commit**

```bash
git add runtime macos/assets windows/assets macos/tests
git commit -m "feat: theme the complete native Codex interface"
```

### Task 5: Produce the two benchmark themes

**Files:**
- Create: `artwork/masters/13-post-raccoon.png`
- Create: `artwork/masters/16-moon-platform-cat.png`
- Create: `artwork/palettes/13-post-raccoon.json`
- Create: `artwork/palettes/16-moon-platform-cat.json`
- Create: `macos/tests/artwork-quality.test.mjs`

- [ ] **Step 1: Write failing artwork validation**

Validate 4K dimensions, exact reviewed filenames, max 10 MiB WebP derivatives, and pixel-grid metadata:

```js
assert.equal(raccoon.width, 3840);
assert.equal(raccoon.height, 2400);
assert.equal(pixelPalette.pixelGrid, 8);
assert.ok(pixelPalette.colors.length <= 32);
```

- [ ] **Step 2: Generate the Post Raccoon benchmark with built-in ImageGen**

Prompt:

```text
Use case: illustration-story
Asset type: 4K Codex home and task background master
Primary request: an original raccoon postal courier developer in a hand-drawn 1990s cel-animation workspace, sorting code cards and stamped envelopes beside a compact terminal
Composition: wide 16:10 scene, dark navy negative space on the left for real UI, character and postal desk on the right, clear foreground/midground/background
Style: limited navy, postal red and warm cream palette, clean ink contours, flat painted shadows, subtle paper registration texture, authored animation-background feel
Constraints: no interface screenshot, no readable text, no logo, no watermark, no glossy 3D, no generic gradient, no resemblance to existing commercial characters
```

- [ ] **Step 3: Generate the Moon Platform Cat benchmark with built-in ImageGen**

Prompt:

```text
Use case: stylized-concept
Asset type: true pixel-art 4K Codex background master
Primary request: an original cat stationmaster waiting on a small moonlit railway platform with a terminal and signal lantern
Composition: 16:10 side-view scene, quiet dark platform across the lower third, empty indigo sky and station wall on the left for real UI, character at the right third
Style: authentic 16-bit pixel art built on an 8px logical grid, hard clusters, deliberate dithering, 24-color indigo/amber palette, no antialiasing, no postprocessed smooth illustration
Constraints: no interface screenshot, no text, no logo, no watermark, no smooth brushwork, no 3D
```

- [ ] **Step 4: Inspect both masters and make one targeted correction per failing invariant**

Reject cartoon output with glossy 3D shading or generic centered composition. Reject pixel output if edges contain antialiasing or inconsistent pixel sizes.

- [ ] **Step 5: Save palette constraints**

```json
{"id":"moon-platform-cat","medium":"16-bit-pixel","pixelGrid":8,"colors":["#0b1026","#18204a","#2f3a70","#f0a94a"],"antialias":false}
```

- [ ] **Step 6: Run artwork validation and commit**

```bash
node macos/tests/artwork-quality.test.mjs
git add artwork macos/tests/artwork-quality.test.mjs
git commit -m "feat: add cartoon and pixel benchmark artwork"
```

### Task 6: Rebuild the other 16 artwork masters

**Files:**
- Create/Modify: `artwork/masters/01-*.png` through `artwork/masters/18-*.png`
- Create: `artwork/palettes/01-*.json` through `artwork/palettes/18-*.json`

- [ ] **Step 1: Use the exact 16-theme prompt matrix**

For each row, build the final prompt by joining the row fields with this fixed header and constraint suffix. This is the complete prompt contract; do not add extra characters, text, logos, or UI panels.

```text
Use case: stylized-concept
Asset type: 3840×2400 Codex home and task background master
Scene and subject: <scene>
Style and medium: <medium>
Composition: <composition>
Color palette: <palette>
Constraints: wide 16:10 image; preserve a calm UI-safe area; clear foreground, midground and background; no interface screenshot; no readable text; no logo; no watermark; no glossy 3D; no generic gradient; no resemblance to existing commercial characters.
```

| ID | Scene | Medium | Composition | Palette |
|---|---|---|---|---|
| stellar-voyager | Small original maintenance robot beside an orbital observatory window, instruments and brass railings | European science-fiction book-cover gouache with etched linework | Dark starfield negative space left; observatory and robot right | midnight navy, electric blue, aged brass, small teal lights |
| sakura-signal | Original wandering courier at a cliffside relay station beneath cherry branches | Japanese travel-poster screen print with visible paper grain and flat ink layers | Quiet twilight sea left; courier and tree right | plum navy, dusty rose, muted violet, warm lantern cream |
| neon-courier | Original fox mechanic resting outside a rain-soaked repair kiosk | 1980s hand-painted anime background with cel character and rain reflections | Dark wet alley left; kiosk and fox right | ink black, cyan, magenta, small amber highlights |
| mist-beacon | Solitary lighthouse above a layered fog forest and distant coast | Nordic woodblock print with restrained watercolor washes | Open mist valley left; lighthouse on right ridge | fog blue, pine green, parchment, muted gold |
| rain-harbor | Quiet industrial harbor with cranes, lamps and rain-slick steps | Hand-painted graphic novel environment with ink contour and gouache | Low-detail rain and water left; lit harbor structures right | deep marine blue, slate, warm amber, muted teal |
| crimson-forge | Original masked craftsperson shaping a glowing mechanical ring in a monumental forge | Dark fantasy linocut with selective red-orange ink and rough paper | Near-black forge void left; craftsperson and machinery right | coal black, iron gray, furnace red, old gold |
| cloud-antler | Original spirit deer on a floating mountain ledge above cloud temples | Chinese mineral-pigment painting with silk texture and disciplined linework | Generous warm parchment left; deer and ledge right | rice paper cream, jade, pale gold, smoky green |
| midnight-terminal | Owl maintenance drone in a narrow industrial terminal shaft | Architectural concept drawing with hard graphite, matte black paint and sparse status lights | Near-black equipment field left; shaft and owl right | carbon, blue-black, terminal green, cold steel |
| retro-orbit | Two tiny astronauts watching a ringed planet from a station balcony | Authentic 16-bit pixel art on an 8px logical grid, 28-color palette, hard clusters, no antialiasing | Empty starfield left; balcony and planet right | navy, cobalt, violet, peach, warm station lights |
| strategy-atrium | Empty modern design atrium with a folded-metal sculpture and measured light paths | Editorial architectural collage with cut paper, ink ruler lines and subtle foil accents | Shadowed concrete left; glass atrium and sculpture right | charcoal blue, stone gray, copper, muted moss |
| aurora-leviathan | Luminous whale-shaped aurora crossing an arctic sea above tiny observatory lights | Layered silk-screen print with fluorescent ink edges and paper texture | Dark ocean and sky left; whale arc center-right | midnight cyan, ultraviolet, turquoise, faint rose |
| ink-ridge-guardian | Original antlered stone guardian above a mountain pavilion in storm clouds | Chinese woodcut and ink wash with carved line rhythm | Dense ink cloud left; guardian and pavilion right | soot black, blue gray, oxidized teal, seal red |
| night-shift-penguin | Original penguin musician-programmer at a small late-night stage desk with laptop, microphone and record player | Black-and-gold editorial illustration with ink outlines, screen-printed spot colors and vinyl texture | Dark stage and soft waveform space left; penguin under spotlight right | warm black, antique gold, ivory, tiny burgundy accents |
| workshop-otter | Original otter inventor surrounded by clipped paper prototypes, tools and taped sketches | Hand-cut magazine collage with colored pencil, crayon marks and imperfect paper edges | Calm kraft-paper workspace left; otter and lively workbench right | teal, tangerine, butter yellow, kraft brown, off-white |
| floppy-wizard | Original tiny wizard operating a CRT computer with floating floppy-disk spell windows | Authentic 16-bit desktop pixel art on an 8px grid, 30-color palette, hard window borders, no antialiasing | Dark empty CRT desktop left; wizard and stacked windows right | dark violet, cobalt, cyan, lavender, warm pixel white |
| deep-sea-repair | Original two-person submarine repair crew beside sonar instruments and a round ocean window | Authentic 32-bit pixel art on an 8px grid, 32-color palette, hard clusters and deliberate dithering | Low-detail control panels left; crew and glowing window right | deep teal, navy, coral orange, seafoam, instrument amber |

- [ ] **Step 2: Generate the ten upgraded non-pixel original themes with separate built-in ImageGen calls**

Do not request multiple unrelated themes in one image. Preserve each theme's design brief from the approved spec.

- [ ] **Step 3: Generate Retro Orbit, Floppy Wizard, and Deep Sea Repair**

Require hard-edge pixel clusters and validate them independently.

- [ ] **Step 4: Generate Night Shift Penguin and Workshop Otter**

Use distinct media: black-gold editorial stage illustration, hand-cut magazine collage, and the approved benchmark cel-animation language. Do not reuse poses or layouts.

- [ ] **Step 5: Build a contact sheet and visually reject near-duplicate compositions**

Run:

```bash
magick montage artwork/masters/*.png -thumbnail '480x300^' -gravity center -extent 480x300 -tile 3x6 -geometry +12+12 /tmp/deep-skin-contact-sheet.jpg
```

At least two layout families and five visibly distinct media must be present.

- [ ] **Step 6: Run artwork validation**

Expected: all 18 files pass dimensions, filenames, and palette metadata checks.

- [ ] **Step 7: Commit**

```bash
git add artwork
git commit -m "feat: rebuild all deep skin artwork masters"
```

### Task 7: Publish the 18-theme admin catalog assets

**Files:**
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/pages/CodexSkins/skinCatalog.ts`
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/i18n/locales/zh/codexSkins.json`
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/i18n/locales/en/codexSkins.json`
- Modify: `/Users/wangqi/work/payment-platform/frontend/scripts/validate-codex-skin-assets.mjs`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/*.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/previews/*.webp`
- Test: `/Users/wangqi/work/payment-platform/frontend/src/pages/CodexSkins/skinCatalog.test.ts`

- [ ] **Step 1: Change catalog tests from 12 to 18 and add the six exact IDs**

```ts
assert.equal(CODEX_SKINS.length, 18);
for (const id of ['post-raccoon', 'night-shift-penguin', 'workshop-otter', 'moon-platform-cat', 'floppy-wizard', 'deep-sea-repair']) {
  assert.ok(CODEX_SKINS.some((skin) => skin.id === id));
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `node --test src/pages/CodexSkins/*.test.ts`

- [ ] **Step 3: Export exact 4K WebP originals and lightweight previews**

Use lossless masters, `cwebp -q 90` for originals, and 1280px previews. Pixel themes must use nearest-neighbor resizing only.

- [ ] **Step 4: Add catalog and localized copy**

Keep the page admin-only. New copy must describe the actual medium and theme behavior, not generic marketing adjectives.

- [ ] **Step 5: Expand validator to 18 exact assets**

Require 3840×2400 originals and prohibit missing or extra files.

- [ ] **Step 6: Run tests and production build**

```bash
node --test src/pages/CodexSkins/*.test.ts
pnpm run test:codex-skins
pnpm run build
```

Expected: 18-theme tests pass and Vite production build exits 0.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/pages/CodexSkins frontend/src/i18n frontend/public/codex-skins frontend/scripts/validate-codex-skin-assets.mjs
git commit -m "feat: publish eighteen deep Codex skins"
```

### Task 8: Build and hot-verify both benchmark themes on macOS

**Files:**
- Build output: `/Users/wangqi/Library/Caches/NexoCodexDreamSkin/Codex Dream Skin-deep-ui.app`
- Runtime state: `~/Library/Application Support/CodexDreamSkinStudio/theme/`

- [ ] **Step 1: Run helper regression tests and sync check**

```bash
node macos/tests/nexo-vivid-profile.test.mjs
node macos/tests/deep-skin-renderer-profile.test.mjs
node macos/tests/deep-skin-layout-css.test.mjs
node macos/tests/signature-skin-css.test.mjs
node macos/tests/native-immersive-css.test.mjs
node windows/tests/nexo-vivid-profile.test.mjs
node tools/sync-runtime-assets.mjs --check
```

- [ ] **Step 2: Build the universal helper**

```bash
DREAMSKIN_SDK="$(xcrun --sdk macosx --show-sdk-path)" macos/scripts/build-menubar-app.sh --skip-tests --output '/Users/wangqi/Library/Caches/NexoCodexDreamSkin/Codex Dream Skin-deep-ui.app'
```

Expected: Mach-O lists `x86_64` and `arm64`.

- [ ] **Step 3: Update only the helper and installed engine**

Quit/relaunch the menu-bar helper, synchronize its bundled engine, and verify the signature. Do not quit or restart Codex.

- [ ] **Step 4: Hot-apply Post Raccoon and verify the active task route**

Use `load-image-theme-macos.sh --no-apply`, then call only `hot_reapply_theme`. Run `verify-dream-skin-macos.sh --screenshot` and require `pass: true`, visible sidebar, composer, and current theme ID.

- [ ] **Step 5: Verify the home route without fake controls**

Open a new native task window manually or through the existing verified UI path, capture the home screenshot, and confirm every themed card corresponds to a native button. Do not use image overlays as evidence.

- [ ] **Step 6: Repeat with Moon Platform Cat and reduced motion**

Confirm hard pixel rendering, visible sidebar/composer styling, and no continuous animation under reduced-motion emulation.

- [ ] **Step 7: Commit any verification fixes and rerun the complete targeted suite**

Expected: all commands exit 0 and both visual screenshots meet the approved standard.

### Task 9: Release the admin-only preview

**Files:**
- Repository: `/Users/wangqi/work/payment-platform`
- Branch: `main`
- Production service: `frontend` only

- [ ] **Step 1: Verify the final local state**

```bash
git diff --check
node --test frontend/src/pages/CodexSkins/*.test.ts
cd frontend && pnpm run test:codex-skins && pnpm run build
```

- [ ] **Step 2: Push `main` without mixing user-owned untracked files**

Fetch and confirm `origin/main` is an ancestor, then push the committed main branch. Preserve `design-demos/codex-skins/` untouched.

- [ ] **Step 3: Perform production Git preflight**

On `/home/ubuntu/payment-platform`, require an empty `git status --porcelain`, branch `main`, and fast-forward ancestry to the pushed SHA.

- [ ] **Step 4: Pull and build only the frontend**

```bash
git pull --ff-only origin main
docker compose build frontend
docker compose up -d --no-deps frontend
```

- [ ] **Step 5: Verify release scope and health**

Require homepage HTTP 200, representative original and preview asset HTTP 200, frontend logs without startup errors, new frontend container ID, unchanged backend container ID, and restart count 0.

- [ ] **Step 6: Report the helper-repository publishing boundary**

If `18534516725/Codex-Dream-Skin` still returns 403, report that the platform preview and this Mac are updated but other machines cannot fetch the new helper until repository write access or an approved distribution repository exists. Do not claim universal rollout before that is resolved.
