# Corner Radius over a group reads 0 while the thing looks round

## What you would see

Draw a rounded button. Group it with something, or turn it into a component and
pick the original. The right hand panel now has a Corner Radius row, and it says
0 with its slider hard to the left, while the button sitting on the canvas is
plainly round.

Nothing is broken and nothing disagrees with anything else. There is one row and
one number, and the number is true: it is the group's own corner radius, and the
group has not been given one. The roundness you can see belongs to the button
inside the group, which has its own 18.

## Why a group has a corner radius at all

A group is a box with no paint in it. Its corner radius is a mask: turn it up
and everything inside the group gets clipped to that curve, the way a rounded
window crops what is behind it. That is a real and useful thing, and it is why
the row is there.

The trouble is only that at 0 it does nothing, and a person reading the panel
does not know whether the 0 is about the group or about the button they can see.

## What each answer means

**The row says what it clips.** The number stays 0 and the row picks up a short
label saying it rounds the group rather than the contents. You read it once and
never wonder again. The cost is a few more words in a panel that is already
being trimmed for being wordy, which is a fair thing to hold against it.

**Take the row away when nothing can show it.** The panel already does this
elsewhere: it does not offer spacing knobs when nothing could show the spacing.
The same test applied here would hide Corner Radius on a group with no
background of its own, and bring it back the moment you give the group one. It
is tidy, and the risk is that it feels jumpy, and that you cannot round a group
before you have filled it.

**Leave it alone.** What happens today. It looks wrong every time and it is not
actually wrong, so this is a real option if you would rather the panel stayed
exactly as terse as it is.

## Where to look

Pick any rounded shape, group it, and watch the Appearance section. The same
thing happens on the original of a component.
