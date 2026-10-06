# Should music dip under someone talking by itself?

## What this is about

When you add a music bed to a screen recording where someone is talking, the
music plays at its full level the whole way through, right over the voice.
Editors fix that by "ducking": the music goes quieter while someone speaks and
comes back up in the pauses.

In Photonz today you can duck by hand. The music's bar on the timeline has a
level line, and you drag points onto it: one before each sentence, one at the
bottom of the dip, one after it. That is about four drags for every sentence.

The audio mock ([video-audio](http://127.0.0.1:8791/pages/video-audio.html))
draws a Duck switch and a "Duck music under voiceover" command. Both were left
out in September because the app could not tell which sound was a voice. That
has changed. The captions now write themselves, word by word, so the app knows
exactly when someone is talking.

## The options

**A. One command, Duck Under Speech (recommended).** Right-click the music (or
use the menu bar) and choose Duck Under Speech. The music dips under every
stretch of talking, and the dips appear as ordinary level points on its bar
that you can drag. If you cut the talk later, run it again to refresh the dips.

**B. Music always dips under speech.** Music under a talking recording dips by
itself and keeps following the speech as you cut. A Duck switch on the music's
Sound section turns it off.

**C. Do not build this.** Keep ducking by hand.

## Why A is recommended

It does the tedious part in one step and leaves you with the same points you
already know how to move. Nothing changes the sound until you ask. Premiere's
auto ducking works the same way: you press a button and it writes keyframes.
