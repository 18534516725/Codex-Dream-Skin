# Five-character skin titles design

## Goal

Every skin home page shows one short title of at most five Unicode characters. It never exposes the original marketplace-style headline or secondary tagline. The approved skin `material-df6388daee46-e3486a16` displays `深蓝礼服`.

## Root cause

The shared rule hides the native headline with `font-size: 0`, but the `max-width: 900px` media query later restores it to `18px`. Narrow windows therefore reveal the untouched long source text and overpower the generated title.

## Design

- Keep title compaction in the shared renderer so macOS and Windows behave identically.
- Remove marketing tokens such as `4K`, `动态`, `静态`, `壁纸`, and `背景`, then cap the result at five Unicode characters.
- Give the reported approved skin an explicit `深蓝礼服` alias so truncation cannot produce an awkward title.
- Keep the native source headline at `font-size: 0` in every breakpoint; size only the generated `::before` title responsively.
- Keep the prior particle exception scoped only to the reported skin.

## Verification

- Static renderer tests assert the exact alias and five-character cap.
- CSS tests assert the narrow breakpoint never restores native headline text.
- Shared runtime synchronization, macOS/Windows Node regressions, payload checks, CI and release asset verification remain required.
