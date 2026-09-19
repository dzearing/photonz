# Trim and send, once a recording opens in the ordinary window

## What this is about

Photonz can record your screen. When you open one of those recordings today, you
get a **separate little window**: the picture, one dark bar floating across the
bottom, and a strip of grey blocks under it showing the pieces you have cut it
into. You can trim it, cut it, throw a piece away, and save it. That flow
shipped on 2026-09-19 and it is genuinely quick.

The video design pass (`docs/design/video-surface.md`, and the page
[Video, in the window you already have](http://127.0.0.1:8791/index.html#video-shell))
says that window should go away, and that opening a recording should open **the
ordinary Photonz window** — your layers list, your tools, your panel, your
document name — with a timeline along the bottom. That part is settled and is
not what this card is asking. A recording is a document, a clip is a layer, and
a separate window for one kind of document is the thing that makes video feel
bolted on.

**What is not settled is what happens to the quick trim flow once it is in
there.** That is a question about how the app should feel, so it is yours.

## What you have now

Two pictures of the shipped window, taken on 2026-09-19:

- `queue/manager/shots/2026-09-19-video-three-pieces.png` — idle, three pieces,
  one of them picked.
- `queue/manager/shots/2026-09-19-video-trim-handles.png` — trim mode, with the
  handles in and **Reset · Cancel · Done** across the bar.

Notice what the second picture buys you: two big grips you drag, a clear range,
and a button that says Done. That is the thing this card is about keeping,
moving or replacing.

## The three answers

### a · Keep the fast lane

Opening a recording still lands you in the quick trim view. A **Show timeline**
control opens the full editor whenever you want it, and it is the same document
either way — nothing is converted and nothing is lost when you switch.

You would notice: nothing changes about trimming and sending. The video features
are behind a control you have to press once.

### b · One window, always

Opening a recording lands you in the ordinary window with a timeline along the
bottom. Trimming is **dragging the ends of the clip**, the same gesture as
trimming anything else in the app. There is no separate trim view and no Done
button, because there is nothing to come back from.

You would notice: one way to do everything, and every video feature visible from
the moment the window opens. And the quick job now happens in a busier window,
with the handles and Done gone.

### c · One window, with a trim mode in it (recommended)

Opening a recording lands you in the ordinary window, and **Trim is a tool you
pick**, exactly like Crop. Picking it puts the handles on the clip and shows
Reset, Cancel and Done — the controls from the second picture, unchanged —
inside the real window.

You would notice: one window, and the fast job keeps what makes it fast. Trim
behaves like Crop, which you already know. It costs one click more than today,
except that Trim is the tool your hand is already on when a recording opens.

## Why c is recommended

Crop already works this way and nobody finds it strange: a tool you pick, a
thing you drag, Apply or Cancel. Trim is the same shape of job. It keeps every
control the shipped flow earned without keeping the separate window that is the
actual problem, and it does not ask the quick job to be done with a fiddly
gesture on a small strip.

Picking **b** is not wrong — it is the purest answer — but it takes a flow that
shipped yesterday and replaces it with a drag, and a two-second trim is the
thing this app is used for most.

Picking **a** keeps everything that works and costs one thing: it leaves two
ways to look at one recording, which is the seam the whole design pass exists to
remove.

## What happens after you pick

Whichever you pick, the build task `a-document-can-have-time` carries it, and
the rest of the video chain follows. Nothing here changes the panel, the layers
list or the timeline itself, all of which are settled.
