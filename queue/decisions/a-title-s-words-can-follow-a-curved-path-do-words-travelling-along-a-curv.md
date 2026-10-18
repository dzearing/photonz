# How words travelling along a curve arrive

## What it is

A title's words can now be set along a curve you draw with the Pen. Pick the title and the curve together and choose **Put Text on a Path** (on the right-click of the words, and in the Layer menu). Each letter stands on the curve, turned to it. Drag the curve's points and the words reflow. **Start**, in the Text section, slides the words along the curve, and with two keys on it the words travel along the curve over time.

The design is the motion mock's "Text on a path" card: http://127.0.0.1:8791/pages/video-motion.html (Techniques, "Follow the curve").

## What to look at

- The reel, frames of the exported MP4 between 0:01 and 0:02, where Start runs from -60% to 0%: `queue/audits/2026-10-18-text-on-a-path-reel.gif` (also `.mp4`), and the frames side by side in `2026-10-18-text-on-a-path-reel-contact.png`.
- The app beside the mock in one picture: `2026-10-18-text-on-a-path-beside-the-mock.png`.

## The question

While Start is below nought, the words that have not reached the curve yet are not drawn. Each letter appears the moment it reaches the curve's first point, and a letter that runs past the last point is gone.

- **Keep it (recommended):** letters pop on at the start of the curve, which is what SVG, Photoshop and Illustrator all do with type on a path.
- **Soft ends:** each letter fades in over the first tenth of the curve and out over the last, only while Start is keyed, so the words seem to grow out of the curve.

Either way the words keep their font, colour, shadow and outline the whole way along.
