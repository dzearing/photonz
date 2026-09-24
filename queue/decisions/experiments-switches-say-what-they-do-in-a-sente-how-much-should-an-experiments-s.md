# How much should an Experiments switch say under its name?

## What this is about

The Experiments window (in the app menu) lists every feature switch for the
release you are running, grouped by the part of the app it changes. Each switch
has a name and a description under it.

Those descriptions have grown into essays. Of 95 switches, 92 run over 40
words; the typical one is 179 words and the longest, Turn Into Path, is 557. A
list of 95 essays is not something anybody reads, so the descriptions have
stopped doing their job of telling you what a switch does before you flip it.

## What changed already

A test now holds every description to the length it has today: none may grow,
and a new switch may not go over 40 words. The rewrite waits on this answer.

## The options

- **One sentence, about 25 words.** *"Adds the release name to editor window
  titles."* Fastest to scan; what Off means is only added when the name leaves
  it unclear.
- **Two short sentences, up to 40 words.** What it changes, then what Off
  means. *"The toast after a capture shows an Edit button and its key. Off means
  Edit only appears while the pointer is over the toast."* This is the length
  the task was first filed with.
- **Leave them as they are.** Keeps every detail in the window. This retires
  the rewrite; the test still stops them growing.

Either rewrite keeps the words someone would search for, because the window's
search box reads descriptions.
