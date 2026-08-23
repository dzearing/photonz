# Fixtures — pages built to be wrong

A gate nobody has watched fail is a gate nobody knows works. These are not part
of the study: they are the smallest pages that make (and fail to keep) a
promise, so `node shared/check-selection.mjs --self-test` can prove the real
gate still bites, in both directions.

| fixture | what it is | expected |
| --- | --- | --- |
| `claims-selection-draws-none.html` | a canvas page whose caption says the ring is on the canvas, and whose walkthrough lights a Layers row, drawing nothing | **caught** |
| `claims-selection-draws-it.html` | the same page, declaring the frame with `data-sel-frame` | passes |
| `talks-about-selection.html` | a language page that discusses the selection ring and has no canvas at all | passes |

Add a fixture whenever a gate gains a rule, and record what it should do in
that gate's `--self-test` expectations.
