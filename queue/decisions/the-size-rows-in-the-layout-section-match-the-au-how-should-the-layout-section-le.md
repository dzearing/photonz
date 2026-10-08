# Sizing a frame in the Layout section: two rows or the mock's one

## What this is about

When you pick a group, or a screen set to a row or a column, the **Layout** section on the right says how big it is. It can either be as big as what is inside it (**Hug**) or a size you give it.

The auto-layout mock draws this as **one row**:

- **Frame size**: Hug | Narrow | Wide

See it at http://127.0.0.1:8791/index.html#ui-autolayout (the Container section, last row). There, Narrow and Wide are two preset widths that show the contents reflowing.

The app shows **two rows** instead:

- **Width**: Hug | Fixed
- **Height**: Hug | Fixed

Fixed keeps the size the thing is at that moment. You change the number in the W and H boxes, or by dragging a handle.

## Option A: keep Width and Height

- You can hug one direction and fix the other: a phone screen 375 wide that grows taller as you add rows is Width Fixed, Height Hug.
- It is how Figma does it.
- Costs one extra row compared to the mock.

## Option B: one Frame size row as the mock draws it

- Exactly the mock.
- Hug applies to both directions at once, so a screen fixed in width but growing in height can't be made.
- Narrow and Wide are two widths the app picks for you. Any other width is still typed in W.

## Recommendation

A. The mock's Narrow and Wide look like demo presets for the prototype, and hugging only the height is the most common real case.
