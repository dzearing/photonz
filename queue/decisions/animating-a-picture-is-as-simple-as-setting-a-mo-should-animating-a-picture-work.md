# How should animating a picture work?

## What this is about

You said the motion pane was totally unintuitive: you press the plus, you have to
choose a property, and you did not want to think about that. You wanted to position
something, save a keyframe, click one, adjust things, and have it tween. You also
said pictures should reuse the video editor.

This is a prototype of that. It runs in the browser, and the whole key flow works:

**[Try the prototype](http://127.0.0.1:8791/index.html#picture-keys)**. Press
**Show me** to watch it, or use the bell yourself. The six boxes above the window
tick themselves off as you go.

## What you would do

1. Pick a layer. The panel shows an **Add Key** button.
2. Press it, or K. The timeline rises under the picture, two seconds long and
   repeating. A hollow diamond marks the moment.
3. Change the layer: drag it, fade it, turn it, resize it. The diamond fills in, and
   a row appears only for what you changed.
4. Click the ruler further along and change it again. A second key appears, and the
   picture tweens between the two.
5. Press Space. It plays and loops.

Click a key to go back and change it. Press Delete to remove it. Delete the last key
and the timeline goes away: it is a still picture again.

## How a change never keys by surprise

Only a layer you pressed Add Key on keys itself. Try dragging the Badge in the
prototype: it has no keys, so it moves for the whole picture, as it always has.

On a layer with keys, a hollow diamond stands at the playhead showing where the next
change lands. The change fills it in with a small pop. There is no record mode to
leave switched on.

## What each answer means

**Option a, build it as shown.** Four things you can see change:

- **The plus and the From and To form go from pictures.** Motion already saved keeps
  playing. Animate a property survives under the small arrow beside Add Key.
- **K adds a key.** K is the Lens today, and neither Photoshop nor Premiere settles
  it, which is why you are being asked. The Lens would keep its menu row and have no
  letter: the letters left are held for erasers and stamps. On a video with the
  timeline focused, K stays Premiere's Stop.
- **A video's panel gets the same button**, in the place your video mock
  ([video.html](http://127.0.0.1:8791/index.html#video)) draws Animate a property.
- **The pivot shows only when the Rotation row is picked.** Your bell mock
  ([Make a bell swing](http://127.0.0.1:8791/index.html#icon-animate-wt)) draws it from
  the moment Rotation exists. On the real app that means a drag from the middle of a
  rotating layer moves the pivot and not the layer, which would trip the first thing
  anybody does here. This also replaces the bell mock's Motion list as the way in.

**Option b** is the same with no letter for Add Key. The Lens keeps K.

**Option c** builds nothing. Say what is wrong in your note, and the prototype changes
and comes back to you.

**Option d** drops it. Pictures stay as they are.

## What a picture does not get

The timeline here is the video one with the cutting taken out: no track tools, no
volume, no scrubber (the ruler is right there). The prototype lists every part that
is the same as video and every part that is not, with the reason, under **One key
model, two documents**.

## What the prototype does not show

Path and Draw a Curve are named but not drawn: they come from the video editor
unchanged. Only four values can be keyed in it (position, scale, rotation, opacity);
the real thing keys everything the video editor can. The selection is simplified.

One thing to look for when you try it: after the first key, nothing tells you to move
the playhead. If you stop there and press play, nothing moves. It did not earn a line
of text in the window under the copy rules, so it is left to the tutorial for now.
Say if you stall there.
