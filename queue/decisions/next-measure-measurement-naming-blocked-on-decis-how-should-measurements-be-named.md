# What is the measurement naming question?

## The feature in one paragraph

As you measure a screenshot, each measurement lands as a row in a Measurements panel: a list you can review, filter, and export as a spec. Every row needs a name. The mock shows friendly, meaningful names like "Save Changes / width" and "Field to button gap". But a screenshot is just pixels: the app does not know that rectangle is a Save Changes button, so friendly names have to come from somewhere.

## Where to see it

- The [Measure & redline mock](http://127.0.0.1:8791/index.html#redline) shows the Measurements panel with the friendly names.
- The measure spec: `docs/design/next-measure.md`, section 6 (panel), section 7 (export), where the names also become the exported spec list text.

## What each option feels like

- **Simple automatic names you can rename.** Rows name themselves from what they are: "Width 128 px", "Gap 16 px". Double-click to rename the ones that matter. Always works, never wrong, but a long list looks uniform until you invest in renaming.
- **Read names from the screenshot text.** The app runs text recognition near the measured element, so measuring a button labeled Save Changes yields "Save Changes / width" automatically, like the mock. When it works it feels like magic; when it misreads, a wrongly named row is worse than a plain one, and recognition takes a moment.
- **No names, just values.** Rows show only kind and number. Nothing to build or explain, but a twenty-row spec export reads as a wall of numbers.

## Why the recommendation is simple names plus rename

It is dependable and cheap, and it does not close the door: text recognition can be layered on later as a "suggest names" pass once the panel exists and real spec exports show how much names actually matter. Starting with recognition risks the panel's first impression being a wrong name.
