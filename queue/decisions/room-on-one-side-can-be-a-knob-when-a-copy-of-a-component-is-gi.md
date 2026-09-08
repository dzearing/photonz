# Room on a copy: what keeps following the original?

## What this is about

A component in Photonz is a control you build once and place many times: a
button, a chip, a card. The thing you built is the original; everything you drop
on the canvas afterwards is a copy of it, and copies keep following the original
so that fixing the button fixes every button.

Some things about a copy are allowed to be its own. The author of the component
decides which, by adding a **knob**: a row on the copy's panel with a number or
a word in it. One of those knobs is **room**, the space a control keeps clear
inside its own edges. A button typically keeps 10 above and below and 16 at each
side.

Room is four numbers, not one, so the knob is the same control the canvas
already uses for it: one field reading `10/16/10/16`, a chevron beside it, and
Top, Right, Bottom and Left underneath when you open it. Typing one number over
the closed field levels all four. Typing into one of the four sides changes only
that side.

That all works today. You can see it in the audit
`2026-09-06-uneven-room-knob` on the Audits section of this dashboard: the
picture `2026-09-06-uneven-room-knob-3-sides.png` is the four sides open on a
copy's panel.

## The bit that is not settled

What happens **afterwards**, when the component itself changes.

Today, the moment a copy answers any one side, it takes the whole room over. The
three sides you did not touch are frozen at whatever the original happened to be
holding at that moment, and they stop following. So:

1. You build a button that keeps 10 above and below, 16 at the sides.
2. You place ten copies of it.
3. On one copy you type 40 into Left, because it holds a longer word.
4. A week later you decide every button should breathe more, and you change the
   original's top from 10 to 32.
5. Nine copies get 32. The one you widened stays at 10, and nothing on screen
   ever told you it had stopped listening.

That last part is the whole question. The way out exists (the revert arrow puts
the knob back to following), but you have to notice you need it.

I confirmed step 5 is really what happens rather than reading it off the code: a
copy typed to `left 40` reads `top 10, right 16, bottom 10, left 40`, and after
the original's top is changed to 32 it still reads `top 10, right 16, bottom 10,
left 40`.

## What you would see under each answer

### A. Untouched sides keep following (recommended)

Only what you typed is yours. On the copy's panel, Left reads 40 in ordinary ink
with a small way-back arrow beside it; Top, Right and Bottom read 10, 16 and 10
quietly, the way any knob a copy has not answered reads. Change the original's
top to 32 and this copy's top becomes 32 too, while its left stays at 40.

This is how the rest of a copy already behaves: a copy that has not answered a
knob follows it. The only reason room does not work this way is that its four
numbers are stored as one answer.

The cost is that one row can now hold two kinds of number at once. It is worth
being sure you want that before it is built, which is why this is a card rather
than a decision I made.

### B. Leave it as it is

Answering one side means the copy owns its room from then on, full stop. One
rule, nothing new on the panel, and a copy you shaped by hand never changes
shape again by itself.

Choosing this ends the task: everything else it asked for already shipped on
2026-09-06.

### C. Whole room still, but any side can be handed back

The freeze still happens, but each side gains its own way back, so a copy that
only meant to change the left can put the other three back to following. It is
the smallest change of the three. It also leaves the surprise in place and only
helps the people who go looking for the fix.

## Where to look

- Audit `2026-09-06-uneven-room-knob` on this dashboard, especially evaluate
  question 3, which asked this same question in passing and was never answered.
- In the app: draw a rectangle and some text, stack them, set Padding to 10 above
  and below and 24 at the sides, press Make Component, add a Padding knob, and
  drop a copy from the Library shelf.
