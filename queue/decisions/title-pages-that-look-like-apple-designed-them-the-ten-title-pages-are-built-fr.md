# The ten title pages, built: do they look right?

## What this is

On 2026-10-18 you looked at the title page mock
([video-titles-apple](http://127.0.0.1:8791/index.html#video-titles-apple)) and
picked all ten designs, with the old busy set kept under **More Styles**. They
are now in the app (Photonz Next, no settings changed):

- **Library, Catalog:** the ten lead the Title Pages group in the mock's order
  (Keynote Section, Film Super, Session Title, Chapter Card, Editorial,
  Sessions Stage, Launch, Gradient Word, Big Number, End Card). The old pages
  sit under their own **More Styles** header below them.
- **Sequence > Insert Title Page** and a track's right-click **Add Title Page**
  list the ten, then a **More Styles** submenu with the old pages.

Each page is the mock transcribed: the same words, faces, sizes, letter
spacing, line spacing, colours and positions on a 1920 by 1080 frame, and the
same motion (a fade, a rise of a few points, a blur that clears, lines that
slide up out of their own baseline, a word whose spacing settles). The
backgrounds hold still; only Sessions Stage's violet glow drifts, very slowly.
Everything you insert is ordinary layers you can edit, like every title.

## What to look at

- **The reel:** `queue/audits/2026-10-18-apple-titles-reel.mp4` (40 seconds,
  all ten as the app draws and exports them), or the GIF beside it.
- **Mock beside app:** `queue/audits/2026-10-18-apple-titles-beside-mock.png`.
  Each row is one page; each pair is the mock then the app at the start, a
  quarter and half way through its entrance, when it has arrived, and while it
  holds.

## How close it is, measured

Mean difference between the mock's frame and the app's, per colour channel, on
a scale of 0 to 255 (0 is identical):

| Page | start | 25% | 50% | in | hold |
| --- | --- | --- | --- | --- | --- |
| Keynote Section | 0.0 | 1.1 | 0.7 | 0.6 | 0.6 |
| Film Super | 1.0 | 1.7 | 1.4 | 1.3 | 1.3 |
| Session Title | 0.0 | 1.5 | 0.9 | 0.8 | 0.8 |
| Chapter Card | 0.0 | 0.7 | 0.7 | 0.4 | 0.4 |
| Editorial | 0.0 | 1.7 | 5.5 | 5.6 | 5.6 |
| Sessions Stage | 1.1 | 2.8 | 2.1 | 2.1 | 2.2 |
| Launch | 0.4 | 2.0 | 1.4 | 1.3 | 1.3 |
| Gradient Word | 0.0 | 1.4 | 0.5 | 0.6 | 0.3 |
| Big Number | 0.0 | 1.5 | 0.7 | 0.6 | 0.6 |
| End Card | 0.0 | 0.2 | 0.5 | 0.3 | 0.3 |

The words land within 2 pixels of where the mock puts them on every page.

## The one real difference: Editorial's serif

New York comes in several cuts for different sizes. The Mac draws a 128 point
headline in its headline cut, which is a little bolder and narrower. The
browser the mock was drawn in used a smaller-size cut, which is wider and
lighter, so the mock's "to explain things" is about 60 pixels wider than the
app's. Everything else on the page matches.

- **a. Ship as built.** Editorial keeps the Mac's own headline cut.
- **b. Match the mock.** The app learns to pick a serif cut by hand and
  Editorial uses the mock's wider, lighter one. A follow-up build; the other
  nine ship now either way.
- **c. Something still looks amateur.** Say which pages and what bothers you,
  and those get reworked.
