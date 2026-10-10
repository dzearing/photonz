# Polished animated titles: research and build plan

Asked for on 2026-10-10. The user's words: "the comps in the library for titles
are so very bland. They look like powerpoint titles. I am wondering if we can
have more professionally polished animated title screens with interesting,
tweakable effects. Moving backgrounds, text that comes in, looks polished and
designed, maybe motion blur, not like a template. do research on what good
looking intros look like and derive how to make it easy to build these."

This extends `video-titles.md` (a preset is just layers you own). The build is
queued as six tasks, listed at the end.

## Summary

- **Why today's presets read as PowerPoint.** Each one is animated as a whole
  group with one choice (fade, slide, pop, scale), and all eight leave with the
  same fade (`Sources/PhotonzCore/TitlePresets.swift:104-115, 421-428`). The
  background, the words and the accent arrive as one slab, and nothing moves
  while the title holds. Polished titles do the opposite: each part enters on
  its own beat, text arrives by line or word, and the background keeps
  drifting slowly.
- **A short list of techniques does most of the work**: mask (slide up)
  reveals, blur to sharp, per word or per character stagger of 20 to 100 ms,
  expo or quint ease out over 400 to 800 ms, tight tracking on the headline, a
  slow animated gradient with grain, an accent line that draws on, and a touch
  of motion blur on anything that moves fast.
- **"Template-y" is defaults nobody chose**: the stock elastic bounce,
  mid-tone backgrounds, too many effects at once, a font that does not suit the
  content ([withmedia](https://withmedia.in/blog/motion-graphics-not-templates),
  [ecommercefastlane](https://ecommercefastlane.com/animation-video-maker-tips/)).
  Restraint and deliberate timing read as designed.
- **The model**: a title is parts (background, text lines, accents). Each part
  has an in, a hold and an out, each a named behaviour with three to five
  knobs. A few global knobs sit on top: theme, font pair, energy, intensity.
  This is how Jitter
  ([help](https://help.jitter.video/en/articles/6500074-animate-text)) and
  Motion's published Final Cut parameters
  ([Apple](https://support.apple.com/guide/motion/create-a-title-template-motn141bb14b/mac))
  work.
- **Renderer gaps**: Photonz already keys blur, opacity, scale and position,
  and has masks and gradients. Missing: per word and per glyph layout and
  animation, animated backgrounds (mesh, noise), grain, motion blur, draw-on
  strokes, and tile previews that actually play (today they show a still).

## What polished intros do

**Typography**

- Set the static type first. Headline tracking about -0.02em, line height 1.1
  to 1.2 ([iart.ai](https://www.iart.ai/blog/how-to-animate-text)).
- Large size contrast: a big bold headline over a small light or medium
  subtitle, often a muted tint of the same colour.
- Apple pairs SF Pro Display Bold titles with Regular body. Pure white on black
  or the reverse; no gradient text, no drop shadows, no mid-tones
  ([yansmedia](https://www.yansmedia.com/blog/what-font-apple-use),
  [DEmotion](https://trydemotion.com/blog/after-effects-advanced-techniques)).
  Near-white `#F5F5F7` is Apple's light background.
- Variable fonts can animate weight smoothly, thin to bold, through their
  variation axes ([iart.ai](https://www.iart.ai/blog/how-to-animate-text)).
- Avoid decorative and script faces in motion: they stop being legible
  ([vertex.art](https://vertex.art/blogs/typography-animation-kinetic-typography)).

**Text reveals** ([iart.ai](https://www.iart.ai/blog/how-to-animate-text)
unless noted)

- **Mask reveal (slide up)**: each line sits in a box that hides its overflow
  and rises from below its own baseline. The standard premium headline
  entrance. Stagger lines 60 to 100 ms.
- **Blur in**: opacity 0 to 1 while blur goes from about 12 px to 0. Keep the
  blur modest and the move short, or it looks sluggish.
- **Character stagger**: each glyph fades and rises with a 20 to 40 ms offset.
  Short strings only.
- **Word stagger**: 40 to 70 ms between words. Apple style is about a 2 frame
  offset at 60 fps, each word rising a little as it fades in
  ([DEmotion](https://trydemotion.com/blog/after-effects-advanced-techniques)).
- **Clip wipe**: a directional reveal where the glyphs do not move. Pairs with
  an underline or colour bar that travels across.
- **Others**: tracking in (letters start wide and close up), scale down from
  about 110 to 120% to 100%, slide with a 10 to 20% spring overshoot
  ([motion tokens](https://skills.smoothui.dev/docs/motion)).
- **Readability**: each unit is legible before the next arrives. Hold about
  0.3 s per word after the reveal, and at least 1 s
  ([iart.ai](https://www.iart.ai/blog/how-to-animate-text)).

**Motion and timing**

- The professional ease is expo out, `cubic-bezier(0.16, 1, 0.3, 1)`: a fast
  start and a soft landing. A full reveal stays under about 800 ms, each
  fragment 400 to 600 ms ([iart.ai](https://www.iart.ai/blog/how-to-animate-text)).
- Exits are 30 to 50% shorter than entrances and ease in. A spring exit drops
  its bounce ([motion tokens](https://skills.smoothui.dev/docs/motion),
  [Material](https://m3.material.io/styles/motion/easing-and-duration)).
- Lower thirds: 15 to 25 frames in, the same out, hold 3 to 5 s, inside title
  safe, 10% from the edges, so 192 px left and 108 px bottom at 1080p
  ([infinitecreation](https://infinitecreation.io/tutorial-lower-thirds)).
- Final Cut and Motion titles mark a fixed build in and build out so the
  middle stretches without changing the animation's speed
  ([Larry Jordan](https://larryjordan.com/articles/create-a-flexible-title-template-in-motion-for-fcp/)).
  Photonz needs the same: the in and out keep their length while the hold
  stretches.

**Backgrounds**

- Animated mesh or soft linear gradients are the default product video
  backdrop. Two or three colours at most (two brand colours and a neutral),
  slow movement, about one gentle sweep per 10 s clip
  ([kinoviz](https://kinoviz.com/blog/animated-gradient-backgrounds)).
- A nice touch: hold the background still under the opening title and ramp its
  speed up as the title leaves
  ([kinoviz](https://kinoviz.com/blog/animated-gradient-backgrounds)).
- Grain gives the tactile Linear, Arc or Vercel look and also stops the encoder
  banding smooth gradients. Enough to notice at 100%, forgotten at arm's length
  ([css-tricks](https://css-tricks.com/grainy-gradients/),
  [kinoviz](https://kinoviz.com/blog/animated-gradient-backgrounds)).
- Apple style glass is a 15 to 20 px blur behind a frosted panel
  ([DEmotion](https://trydemotion.com/blog/after-effects-advanced-techniques)).
  The Photonz version is the recording itself, blurred and dimmed, behind the
  title. That ties the intro to the content, the best cure for the template
  look.

**Motion blur**

- The shutter angle sets how much. 180 degrees is the film standard and the
  natural default; 270 to 360 is the heavy smear of stylised titles and sports
  graphics ([ProVideo Coalition](https://www.provideocoalition.com/motion_blur/),
  [styleframe](https://www.styleframe.ai/blog/motion-blur-in-after-effects)).
- In practice it shows only during the fast part of an expo ease out, which is
  exactly where it sells the move.

**Accents**

- Thin rules or underlines that draw on; a small colour block the text wipes
  out from behind (broadcast lower thirds); a soft glow on one keyword.
- A lower third's backing shape resizes with its text, like Premiere's
  responsive design "pin to"
  ([nofilmschool](https://nofilmschool.com/2017/10/adobe-premiere-pro-responsive-design)).
  Photonz cards already lay themselves out (`TitlePresets.swift:131-137`).

**Designed against template-y**

- Designed: one idea per title, two type sizes at most, deliberate empty space,
  colours taken from the content, every part entering on its own beat, and
  something subtle still moving during the hold (background drift, or a slow 1
  to 2% scale push).
- Template-y: the whole graphic moving as one block, linear or default ease,
  elastic bounce on everything, mid-tone gradients, drop shadows on text, a
  stock font whatever the content, several effects stacked at once
  ([withmedia](https://withmedia.in/blog/motion-graphics-not-templates)).
- Sound matters too: soft whooshes and ticks synced to the builds are credited
  with "50% of perceived quality"
  ([DEmotion](https://trydemotion.com/blog/after-effects-advanced-techniques)).
  Photonz already has `SoundEffects.swift`.

## Twelve style directions

Timings at Normal energy. "Knobs" is what the person can tweak.

1. **Keynote Clean.** Background pure black or `#F5F5F7`, optionally a very
   slow radial vignette. SF Pro Display Bold headline at -0.02em; Regular
   subtitle at about 35% of the headline size, 60% opacity. Words fade and rise
   12 px with an 80 ms stagger, expo out, 500 ms each. Out: everything fades
   together in 250 ms, ease in. No accents. Knobs: light or dark, word stagger,
   rise distance, weight.
2. **Soft Gradient Glass.** Three-colour mesh gradient drifting on a 10 s loop,
   with grain. A frosted panel (20 px background blur, 12% white, rounded)
   holds the title. The panel scales from 96% with a fade over 600 ms quint
   out, then the text blurs in (12 px to 0) 150 ms later, staggered by line.
   Knobs: palette, drift speed, grain, panel blur, corner radius.
3. **Kinetic Bold.** A solid saturated colour that swaps on each word beat.
   Heavy condensed caps, very large (60 to 80% of the frame width). Each word
   mask-slides up with a 10% spring overshoot and a 60 ms stagger, motion blur at
   270 degrees. During the hold the block keeps a slow 2% scale push. Knobs:
   energy, overshoot, colour sequence, blur.
4. **Editorial Serif.** Warm paper (`#F4F1EA`) with fine grain. A large
   high-contrast serif title (New York or Georgia) with a small tracked
   uppercase sans kicker above it at +0.15em. The kicker fades first, the serif
   line clip-wipes left to right over 700 ms, and a hairline rule draws on
   underneath. Knobs: paper tint, serif, rule on or off, wipe direction.
5. **Tech Terminal.** Near-black with a faint grid or scanlines and a slow
   green or amber glow. SF Mono, typed in at 30 ms a character with a blinking
   block cursor, and an optional 2 to 3 frame scramble before each character
   locks. A thin progress bar accent. Knobs: characters per second, scramble,
   accent colour, cursor style.
6. **Recording Behind Glass** (the Photonz signature). The first seconds of the
   recording itself, blurred 30 to 40 px, dimmed 40%, with a slow 105% to 100%
   zoom. A white headline blurs in with a line stagger. Out: the title fades
   while the recording's blur goes to 0, landing in the real footage. Knobs:
   blur, dim, zoom, which moment to sample.
7. **Light Leak Cinematic.** Dark, with one or two large soft warm blobs
   crossing slowly in screen or add blend. Thin, wide uppercase tracks in from
   +0.4em to +0.15em over 1.5 s with a fade, with a gentle glow. Knobs: leak
   colour, intensity, tracking start, duration.
8. **Split Wipe lower third** (broadcast). A colour bar wipes in from the left,
   300 ms expo out. The name reveals from behind the bar's leading edge as a
   mask, the role 120 ms later. Out in reverse, 200 ms. Knobs: bar colour,
   thickness, side, corner radius.
9. **Minimal Underline lower third.** No backing. The name fades and rises
   8 px; a 2 px underline draws on from the left over 400 ms starting 100 ms
   later; the role fades in after the line. Needs a text shadow or a soft dark
   gradient at the bottom of the frame to stay legible over footage. Knobs:
   line colour, line length (text width or fixed), alignment.
10. **Pill Card lower third.** A rounded pill, glass or solid, scales in from
    90% with a 12% spring overshoot. A small round avatar or logo at the left;
    the name and role blur in inside the pill. Knobs: fill, overshoot, avatar,
    shadow.
11. **Gradient Text Glow** (product launch). Black. A very large headline with
    a moving linear gradient clipped to the text and a soft outer glow. Scales
    from 115% to 100% while blur goes 20 px to 0 and it fades in over 900 ms
    expo out; the gradient keeps sliding during the hold. Knobs: gradient
    colours and speed, glow, starting scale.
12. **Stacked Stagger** (tech channel intro). Two or three lines of different
    weights and sizes, each mask-revealing from alternating directions 100 ms
    apart, then a small logo mark pops in. Dark with a slow mesh. Out: lines
    leave upward in reverse order. Knobs: direction pattern, stagger, logo,
    energy.

## Making it easy to build

**The model** (pure, in PhotonzCore)

- A `TitleDesign` holds its `parts`, a `theme` (three to five colour roles:
  background, primary text, secondary text, accent), a `fontPair` (display and
  text), `energy` (a speed multiplier that also scales stagger and overshoot)
  and `intensity` (scales blur, distance and grain together).
- A `TitlePart` is a background (solid, gradient, mesh, blurred recording), a
  text line, or an accent (rule, bar, pill, glow, logo). Each has a role
  (headline, subtitle, kicker) so a theme and a font pair can restyle any
  preset, plus an in, a hold and an out behaviour and a start offset within the
  title.
- A behaviour is a named recipe with a few parameters.
  - Recipes: fade, rise, mask reveal, blur in, track in, scale from, wipe,
    typewriter, draw on, spring pop; and for the hold: drift, push, gradient
    flow.
  - Parameters: duration; unit (whole, line, word, glyph); stagger; order
    (forward, reverse, centre out, random); direction; curve (the shared
    `EasingCurve` list, adding Ease out expo and quint); distance; blur;
    overshoot.
- **It compiles into keys on ordinary layers**, never a new runtime object.
  That keeps the rule in `video-titles.md` that a preset is just layers you
  own. Per unit stagger needs one new thing: a text animator that stores unit,
  stagger and order once and is evaluated per glyph at render time, instead of
  splitting into one layer per word.
- **Locked builds, stretchy hold**: trimming the bar on the timeline stretches
  the hold and keeps the in and out the same length, as Motion's build markers
  do.

**What the person sees**

1. **Browse.** Library tiles play on hover and loop while picked, small
   (about 320 px wide), with the person's own first frame behind them where the
   style uses the recording. Today's tile is a still at rest
   (`Sources/Photonz/LibraryTitleTile.swift`), which hides exactly what makes a
   title good.
2. **Pick and drop**, as today: double click, insert or drag.
3. **Type on the canvas.** Lines re-lay out, backing shapes follow the text,
   and the animation replays from its in point after a short pause.
4. **A few knobs first**, in a Title section, in this order: Theme (swatches,
   plus From Recording, which samples two or three colours from the clip); Font
   pair (four or five curated pairs); Energy (Calm, Normal, Punchy: durations
   x1.3, x1, x0.7, with more overshoot and motion blur and a tighter stagger as
   it rises); Intensity (one slider for blur, distance, grain and glow);
   Background (on or off, and its kind).
5. **Then per part.** Pick a part on the canvas or in the panel for its in,
   hold and out pickers, their few knobs, and Replay. Keys and the curve editor
   stay there for anyone who wants to hand-edit.
6. **Save as my title** exists (`SaveTitlePresetDialog.swift`). It saves the
   design (behaviours, theme, roles), not just the baked layers, so theme and
   energy stay tweakable afterwards.

## Renderer needs and costs (1080p, 60 fps, Core Image on Metal)

Estimates, not measured on Photonz.

| Need | How | Cost |
|---|---|---|
| Per glyph or per word layout | CoreText run positions computed once per text edit; each unit drawn into a small atlas and composited with its own transform and opacity | Cheap if units are cached; re-rasterising text every frame is not. `TextRasterizer.swift` lays out lines (`:144-170`) with no unit split |
| Masks and clip wipes | A crop or rect mask per line (`CIBlendWithMask`), or the existing `LayerMatte` | Cheap |
| Animated gaussian blur | Already keyable (`LayerMotion.swift:36`); Core Image's blur stays near constant cost at large radii ([Apple](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/)) | Moderate full frame. Blur only a text unit's small bounds, never the whole frame |
| The recording blurred behind | One full frame blur a frame, at half resolution then upscaled | Moderate; fine on M-series |
| Motion blur | Best: 4 to 8 sub-frame samples across the shutter, averaged, only for parts moving faster than a threshold. Cheaper: `CIMotionBlur` along each unit's velocity, radius = speed x shutter / 360 per frame | Sub-frame sampling is N times the part's cost, but only on small text during short builds. Directional blur per unit is cheap |
| Animated mesh gradient | A small Metal or `CIColorKernel` moving a few colour points with smooth falloff, or blended `CILinearGradient` and `CIRadialGradient` | Cheap as a kernel; render at half size and upscale |
| Grain | `CIRandomGenerator`, cropped, offset each frame, a low opacity overlay or soft light | Cheap |
| Draw-on strokes | Animate the stroke's end (trim path) | Cheap; needs a trim property on paths |
| Glow and light leaks | The existing glow plus large blurred ovals in screen or add blend | Cheap to moderate |
| Variable font weight | Rebuild the font with an axis value each frame | Moderate, since it re-rasterises text every frame; keep it optional |

Under 16 ms is realistic if unit rasters are cached, full frame blurs and
gradients run at half resolution, and motion blur runs only during builds.
Composite path changes need a perf note (repo rules).

## What Photonz has today

- **Presets**: `BuiltInTitle` has 4 title pages (midnight, sunrise, paper,
  spotlight) and 4 name cards (bar, clean, accent, minimal)
  (`Sources/PhotonzCore/TitlePresets.swift:77-138`). Each is a group of ordinary
  layers drawn by `TitlePen` (`:283`) with flat, linear or radial gradients,
  boxes, ovals and text.
- **One animation for the whole group**: `TitleAnimation` is fade, slide, pop
  or scale (`Sources/PhotonzCore/ClipKeys.swift:206-230`) at a fixed 500 ms
  (`:220`), written onto the group as a whole (`TitlePresets.swift:421-428`,
  `ClipKeys.swift:246-307`). Every preset's out is a fade (`TitlePresets.swift:115`),
  and the ease is the generic ease in or linear (`ClipKeys.swift:257-258`), not
  an expo style curve.
- **Easing**: `EasingCurve` has linear, in, out, in out, in out sine, out back,
  out elastic, steps and a custom bezier (`Sources/PhotonzCore/LayerMotion.swift:428-447`).
  No named expo or quint, though the custom bezier can express them.
- **Keyable properties**: position, scale, rotation, opacity, colour, blur,
  shadow (`LayerMotion.swift:18-55`). A per layer blur in is possible today;
  the presets just do not use it.
- **Effects**: blur, shadow, border and glow (`Sources/PhotonzCore/LayerEffects.swift:22-43`);
  layer mattes, Photoshop style clipping (`Sources/PhotonzCore/LayerCompositing.swift:227`).
- **The shelf**: tiles show a still at rest (`Sources/Photonz/LibraryTitleTile.swift:6-12`).
  Saving your own exists (`Sources/Photonz/SaveTitlePresetDialog.swift`,
  `Sources/PhotonzCore/TitlePresetShelf.swift:15-17`).

**Missing**: per part timing (background, text and accent cannot enter on
separate beats); per line, word or glyph animation and stagger (the rasteriser
draws whole lines); mask reveal, track in, typewriter and draw on, and a trim
property for accents; animated backgrounds, grain and the blurred recording
backdrop; motion blur anywhere in PhotonzRender (no `CIMotionBlur`, `shutter`
or `motionBlur` in the code); theme, font pair, energy and intensity; hold
motion; in and out lengths that scale with energy; named expo and quint curves;
tile previews that play.

## Build order (one queue task each, filed 2026-10-10)

1. **Titles move in parts, not as one block.**
2. **Title text comes in by line, word or letter.**
3. **Title backgrounds move: gradients, grain, the recording behind glass.**
4. **Motion blur on titles that move fast.**
5. **Title tiles play, and a few knobs restyle a title.**
6. **A set of titles that look designed.**

Screen Studio cannot make text slides at all
([tight.studio](https://tight.studio/blog/how-to-add-text-slides-in-screen-studio/)),
so this is a place Photonz can stand out.

## Sources

[iart.ai](https://www.iart.ai/blog/how-to-animate-text),
[svgator](https://www.svgator.com/blog/kinetic-typography-a-guide-to-text-in-motion/),
[vertex.art](https://vertex.art/blogs/typography-animation-kinetic-typography),
[DEmotion, Apple style](https://trydemotion.com/blog/after-effects-advanced-techniques),
[yansmedia](https://www.yansmedia.com/blog/what-font-apple-use),
[kinoviz, gradients](https://kinoviz.com/blog/animated-gradient-backgrounds),
[css-tricks, grainy gradients](https://css-tricks.com/grainy-gradients/),
[ProVideo Coalition, motion blur](https://www.provideocoalition.com/motion_blur/),
[styleframe](https://www.styleframe.ai/blog/motion-blur-in-after-effects),
[infinitecreation, lower thirds](https://infinitecreation.io/tutorial-lower-thirds),
[motion tokens](https://skills.smoothui.dev/docs/motion),
[Material easing](https://m3.material.io/styles/motion/easing-and-duration),
[Jitter, text](https://help.jitter.video/en/articles/6500074-animate-text),
[Apple Motion title templates](https://support.apple.com/guide/motion/create-a-title-template-motn141bb14b/mac),
[Larry Jordan](https://larryjordan.com/articles/create-a-flexible-title-template-in-motion-for-fcp/),
[nofilmschool, responsive design](https://nofilmschool.com/2017/10/adobe-premiere-pro-responsive-design),
[withmedia](https://withmedia.in/blog/motion-graphics-not-templates),
[ecommercefastlane](https://ecommercefastlane.com/animation-video-maker-tips/),
[Apple Core Image filter reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/),
[tight.studio, Screen Studio](https://tight.studio/blog/how-to-add-text-slides-in-screen-studio/).
