# Turning a silenced question back on

## What this is about

Photonz almost never stops to ask you anything. Deleting a layer does not ask.
Cropping does not ask. Undo covers all of it, and you can see what happened.

There is exactly one command that does stop and ask: **Turn Into Picture**, in
the Layer menu and in a layer's own row menu. It takes a shape or a piece of
text and bakes it into pixels so a marquee can cut a piece out of it. It asks
first because what it takes away is invisible. The instant after, the picture
is identical: same shape, same colour, same place. What is gone is that the
shape or the words could be edited at all, and nothing on screen says so. You
find out a week later, reaching for words that are no longer there.

The question looks like this:

> **Turn "Card" into a picture?**
> It becomes pixels, so a marquee can cut a piece out of it. The shape stops
> being editable. Undo puts it back.
>
> `[ ] Don't ask again`      **Cancel**   **Turn Into Picture**

That checkbox is standard macOS, and people tick it without much thought. It is
often the right thing to tick: if you are cutting up half a mockup you do not
want to be asked forty times.

## The problem

Ticking it is permanent. There is nowhere in Photonz to bring the question
back. Not in a menu, not in a window, nowhere. Somebody who ticks it on their
first day, or ticks it by accident reaching for the button next to it, has
given up that warning for good.

The project's own UX rules already say this is wrong: "A person must be able to
get the question back, in one place that lists every question they have
silenced and turns any of them back on." They also record that nothing ships
that place yet.

So the question is not whether to build the way back. It is **where a person
goes to find it.**

## Why this is a real question and not a detail

Photonz has no Settings window. Not a small one, not an empty one. The menu bar
menu even has a note in it saying Preferences comes back the day there is a
settings window behind it. So building the obvious answer means the app grows a
front door it does not have today, and the first thing behind that door is a
list with one row in it.

That is the trade. A door everybody knows how to open, with almost nothing
behind it yet. Or no door, and a way back that only finds you if you happen to
be standing in the right place.

## What each option feels like

### A Settings window

You press **Command-,** the way you would in any Mac app, or pick **Settings**
from the Photonz menu in the menu bar. A small window opens on a page called
**Questions**.

If you have never silenced anything, the whole page is one sentence: something
close to "Photonz is asking you every question it knows how to ask." Nothing to
click. That matters, because a page full of unticked switches is an invitation
to go and turn warnings off, which is the opposite of the point.

If you did silence Turn Into Picture, the page has one row: the command's name,
a line saying what it stops to warn you about, and a button that starts it
asking again. Press it, run Turn Into Picture, and the question is back on the
very next use.

In a year, when the app has three or four of these, it is the same page with
three or four rows.

### Offer it back where it went quiet

Nothing new opens anywhere. Instead, the next time you run Turn Into Picture
after silencing it, the command does its thing and a small notice appears near
the canvas: "Turned "Card" into a picture", with a link that says **Ask me next
time**.

It is nicely timed: that is the exact moment you might think "hang on, it did
not ask me". But it is not a list, and it only reaches you if you run that
command again. If you ticked the box on your first day and did not touch Turn
Into Picture for a month, there is nothing to find and nothing to search for.
It also puts a small piece of chrome back on a command you deliberately made
quiet.

### A section in the Experiments window

The Experiments window already exists and already opens with no document. It
would gain a **Questions you have silenced** section at the bottom, with the
same one row and the same button.

This is the fastest to build and it costs no new surface. The trouble is who
Experiments is for. It is a workbench for turning unfinished features on and
off, and the switches in it change the app underneath you. A person looking for
a warning they turned off will not think to open it, and if they do open it
they land somewhere that was not built for them.

### Leave it as it is

Don't ask again stays a one way door, and the app keeps breaking its own rule.
Defensible only as a bet that nobody silences it by accident before there is a
Settings window for some other reason. Picking this retires the task rather
than sending it back round.

## The recommendation

**A Settings window.** It is the answer a person already knows without being
taught, it works with no document open, it is still findable months after you
have forgotten what you clicked, and it is the only one of the three that is
still the right shape when the app has ten of these questions instead of one.

The cost is honest and small: an almost empty Settings window for a while. An
empty page that says "nothing is silenced" reads as reassurance, not as an
unfinished screen.

## Where to look

- The question itself: open any document, draw a rectangle, then **Layer >
  Turn Into Picture...**
- The existing Experiments window, for a sense of option three:
  **Photonz menu bar icon > Experiments...**
