# One file per component

`photonz-ds.css` grew to 2,379 lines and `photonz-ds.js` to 2,161. At that size
you cannot find a component, and you certainly cannot change one without reading
around it — which is how the shell ended up with 57 hand-authored copies in the
first place.

Both files are now **empty on purpose**. The whole design system lives here:
**35 CSS components** and **16 JS components**, largest first —
`icons` (77 KB of generated glyphs), `colorpicker`, `inspector`, `dock`,
`walkthrough`. Nothing is over ~900 lines and most are under 150.

So a component lives here, in its own pair of files:

```
shared/components/tooltip.css     ← its look
shared/components/tooltip.js      ← its behaviour (optional)
shared/components/order.json      ← concatenation order
```

**Pages do not change.** They still link `/shared/photonz-ds.css` and
`/shared/photonz-ds.js`. `dev-server.mjs` assembles those two URLs on each
request from the base file plus every component in `order.json`. That keeps the
runtime contract identical — one classic script, one stylesheet, same execution
order — so a page's own inline `<script>` still runs after the DS, which 51 pages
rely on. For static hosting, `node shared/build-ds.mjs` writes the same bundles
to disk.

## Rules

- **Order is explicit.** `order.json` lists components in cascade order. Never
  rely on alphabetical or filesystem order.
- **A component owns its whole surface**: tokens it needs, base rules, variants,
  states, responsive behaviour, and the JS that wires it. If you have to edit two
  files to change one component's look, it is not split correctly.
- **Behaviour is an idempotent upgrade pass.** Each JS component is its own
  guarded IIFE, safe to run twice, and a no-op on a page that does not use it.
- **`core.js` runs first** and publishes the only four shared helpers on
  `window.PZ`: `all`, `winOf`, `isNarrow`, `NARROW`. That is the entire shared
  surface. A component must not reach into another component's internals; if it
  needs to, the two are one component or the shared part belongs in core.
- **`shared/photonz-ds.{css,js}` are empty and must stay empty.** They exist only
  so the URL every page links stays valid. Adding a rule there puts it outside
  the component that owns it, which is exactly how this got out of hand.

## Splitting one out

1. `shared/components/<name>.css` (+ `.js`), with a header comment saying what
   the component is and what it replaces.
2. Delete those rules from `shared/photonz-ds.css`.
3. Add `<name>` to `order.json` at the position the cascade needs.
4. Reload. The dev server reassembles; livereload picks it up.
