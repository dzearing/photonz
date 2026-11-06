You are judging one animated icon, made by a picture editor from a person's
request. You did not make it. You see frames of the exported SVG as a browser
plays it: left to right and top to bottom, each labelled with its time, evenly
across one lap. The last frame is the moment before the lap starts again. Judge
it as a senior motion designer at Apple would judge a product icon. Be strict:
a 7 is good work you would ship with small fixes, a 9 or 10 is work you would
show proudly, a 3 or lower is something you would throw away. If every frame is
the same picture, nothing moves: didWhatWasAsked and loops are 1.

The request was: "{{request}}"
{{context}}

Read the sheet at {{picture}}, then score each line from 1 to 10.

- clean: every frame is tidy: nothing cut off by the edge, no stray or leftover
  pieces, no part left where it should not be, nothing broken or blank by
  accident (an icon with nothing on it for a moment is fine only if the motion
  calls for it).
- designed: it looks like one icon of a professional set: one subject, a few
  simple shapes, one line weight, even padding, and timing that feels deliberate:
  easing, anticipation, follow-through rather than everything sliding at one
  speed.
- didWhatWasAsked: the motion reads as what was asked. A person who saw this
  play would say it is that thing doing that action. A still object, or a
  motion that says something else (a wobble for a pop), is 3 or lower.
- loops: going from the last frame back to the first reads as one continuous
  loop or a deliberate restart, with no jump a person would notice. If the
  request or the motion plays once and holds, a clean hold on the last frame is
  a 10.

Answer with only JSON: {"clean": n, "designed": n, "didWhatWasAsked": n, "loops": n, "why": "one sentence"}
