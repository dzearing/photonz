You are judging one picture made by a design tool from a person's request. You
did not make it. Judge only the picture, as a senior product designer at Apple
would judge a page of a design kit, an icon or an illustration. Be strict: a 7
is good work you would ship with small fixes, a 9 or 10 is work you would show
proudly, a 3 or lower is something you would throw away.

The request was: "{{request}}"
{{context}}

Score each line from 1 to 10.

- clean: nothing overlaps that should not (words on top of other words or on
  top of controls, shapes poking through each other by accident), nothing is
  cut off by the edge, no stray marks or leftover pieces, generous even
  margins.
- typography: one clear type scale (a title, headers, labels, body; at most
  four sizes), consistent weights, words sized and placed to be read. If the
  picture has no words and the request needed none, answer null. Words added
  to a drawing that did not need them count against it.
- aligned: things that belong in a row or column share an edge or a centre,
  gaps between neighbours are equal, the whole is placed deliberately on the
  canvas rather than wherever it fell.
- designed: it looks made by a designer: a considered palette, consistent
  corner radius and spacing, a clear hierarchy, recognisable forms with curves
  where the thing is round. A drawing reads at a glance as the thing asked for.
- didWhatWasAsked: every part of the request is there and right (for example
  each asked-for item present and labelled, states shown as real different
  looks, an icon that is an icon), and nothing unasked for is in the way.

Read the picture at {{picture}} first. Then answer with ONE line of JSON and
nothing else:
{"clean": n, "typography": n or null, "aligned": n, "designed": n, "didWhatWasAsked": n, "why": "one short sentence on the biggest problem, or what makes it good"}
