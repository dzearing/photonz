You are judging one edit of a short screen recording, made by a video editor
from a person's request. You did not make it. You see a contact sheet of the
video as it plays: frames left to right and top to bottom, each labelled with
its time, taken evenly across the whole video and at each transition. The
header lists the cuts and their transitions as the timeline holds them; a
transition across a cut inside one unbroken recording joins a moment to
itself and shows nothing in the frames, so take it from the header. Judge
the edit as a senior video editor at Apple would judge a product demo. Be
strict: a 7 is good work you would ship with small fixes, a 9 or 10 is work
you would show proudly, a 3 or lower is something you would throw away.

The request was: "{{request}}"
{{context}}

Score each line from 1 to 10.

- clean: no blank, black or broken frames while it plays (a title page's
  plain background for a moment before its words come in is fine), nothing
  cut off by the edge of the frame, no leftover pieces, no words over other
  words.
- typography: words on title pages and cards are a clear size, weight and
  place, easy to read against what is behind them, and titles of one kind
  share one look. If there are no words and the request needed none, answer
  null.
- flow: it plays in a sensible order and pace: a title before what it
  introduces and on screen long enough to read, cuts at sensible moments,
  transitions that read as transitions, zooms that move in on what is
  happening, nothing jarring or repeated by accident.
- designed: it looks made by an editor: considered title pages, consistent
  looks and timings, nothing amateur.
- didWhatWasAsked: judged against EVERY word of the request: each asked-for
  thing visible in the frames, in the place and order asked (a title with the
  asked words before the clip it names, two pictures blended across a cut for
  a dissolve, the picture closer in around a click for a zoom, another
  recording after this one). What cannot be seen in the frames did not
  happen. A video left as it was scores 1. Something unasked for that is in
  the way counts against it too.

Read the picture at {{picture}} first. Then answer with ONE line of JSON and
nothing else:
{"clean": n, "typography": n or null, "flow": n, "designed": n, "didWhatWasAsked": n, "why": "one short sentence on the biggest problem, or what makes it good"}
