# Should a title or picture's right-click menu lead with Animate and Add Key?

## What this is about

Right-clicking something on the video timeline opens a menu of what you can do
to it. On 2026-10-17 you said the clip menu was enormous and made little sense,
so each kind of thing now has its own short menu of about ten rows. The rest
sits one level down under **More**. The whole layout is one table:
`docs/design/timeline-right-click.md`.

A title page or a picture today opens with:

- Split at 0:02.00 · Start at 0:02.00 · End at 0:02.00
- Animate In ▸ · Animate Out ▸ (and Add Transition ▸ where one fits)
- Cut · Copy · Delete · Ripple Delete
- More ▸ (Fade In, Fade Out, **Animate ▸**, **Add Key at 0:02.00**, Replay Title, Save as Preset…, Select Forward, Duplicate, Rename…)

## What the mock draws

The animation mock (`http://127.0.0.1:8791/index.html#video-animate`, the
right-click on a clip's key line) leads with **Animate ▸, Add Key, Remove Key**,
then Split at Playhead, Speed and Delete.

## The two choices

**Keep them under More.** Short and the same shape as every other clip. Keying
a title by right-click costs one more step; the header's diamond and
Clip ▸ Key at Playhead still do it in one.

**Put Animate and Add Key on top for titles and pictures.** Matches the mock,
and makes "move this title from A to B" a right-click away. To stay short,
Animate In, Animate Out, Cut and Copy move under More for these two kinds.
