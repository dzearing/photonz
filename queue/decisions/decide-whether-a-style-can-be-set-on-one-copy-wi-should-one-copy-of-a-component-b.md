# Should one copy of a component be able to wear its own text style?

## What this is about

A **component** is a thing you draw once and reuse: a Button, a Card, a Nav
bar. Every place you use it is a **copy**, and a copy follows its original. Fix
the original and every copy changes with it. That is the whole point.

A **text style** is a saved look for words: a name like Heading holding a font,
a size, a weight and a colour. It lives on the Library shelf on the right, and
you can pick its tile up and let it go on any words on the picture, which sets
them in that style there and then.

Put the two together and you get today's dead end. You drag Heading over the
label of a button that happens to be a copy, and nothing will take it.

## What happens today

Until this week the app said:

> Save button is not text, so it cannot wear Heading.

The pointer was sitting on the word "Save". Anybody can read it. The app was
telling them something they could see was false, and offering nothing to do
about it.

It now says:

> Label comes from Button. Set Heading on the original, or detach this copy.

That is honest, and it names both moves that work:

- **Set it on the original.** Open the Button you drew once, drop the style on
  its label, and every copy of it changes. This is usually right for a design
  system: buttons are supposed to match.
- **Detach this copy.** The copy stops following the original and becomes
  ordinary layers. Now the style lands like it would anywhere else. But the
  copy has left the family for good, and it will not pick up the next change
  you make to Button.

What is missing is the small thing in between: **this one button, different,
still a Button.**

## Why it is a real question and not an oversight

A copy is already allowed to own quite a lot. On the copy's own panel you can
give it:

- its own colour
- its own size
- its own room inside
- its own opacity
- its own wording, when the original offers a wording knob for that piece

Each of those shows up on the panel as "its own", with a one press way back to
what the original says. So "a copy can own one more thing" is a well worn path.

The reason it is not obvious is **where a text style comes from**. Every one of
those five is a setting the copy already has, turned to a different number.
A text style arrives from OUTSIDE the component, off the Library shelf, and it
is a link rather than a value: text set in Heading follows Heading, so editing
Heading later reaches through the copy too. That is a second thread of
inheritance running across the first one, and it is worth being deliberate
about before adding it.

## What you would see, under each option

**A: a copy can wear its own style.** You drag Heading onto the copy's label
and it lands, on that copy only. The copy's panel then shows a line saying part
of its look is its own, with a way back. The other copies are untouched.

**B: leave it as it is.** Exactly what happens now: the sentence explains and
points at the original or at detaching. You take one of those two roads.

**C: ask on the spot.** The drop stops and asks: this copy, or every copy? You
pick, and it lands. Nothing changes until you answer.

## Where to look

- The drag and its sentence: Photonz Dev, Next release, Library panel, Styles
  shelf. Place the starter Button twice (once as the original, once as a copy),
  save any text style, and carry its tile over each of them.
- The picture of the refusal as it reads today:
  `queue/audits/2026-09-09-style-on-a-copy-refused.png`
- What a copy already owns, and how it says so: the Component section of the
  properties panel with a copy selected.

## Recommendation

**A.** It is what somebody aiming at one button meant, it matches the five
things a copy can already own, and nothing about it is one way: the copy says
what is its own and puts it back in one press. C is the careful version, but a
question in the middle of a drag turns the fast way into the slow way, and the
"every copy" road already exists a few inches away on the original.
