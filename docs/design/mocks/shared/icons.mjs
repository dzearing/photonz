/* Photonz icon library — THE SOURCE OF TRUTH.
   ------------------------------------------------------------------
   Edit glyphs here, then run:   node shared/build-icons.mjs
   That regenerates three things and keeps them in lockstep:
     1. the .ic-* block in shared/photonz-ds.css
     2. the searchable grid in pages/iconography.html
     3. the icon-name list in shared/AGENTS.md
   Never hand-edit those three regions; they are marked GENERATED.

   ------------------------------------------------------------------
   THE GRID (documented for humans on pages/iconography.html)

     view box     24 x 24
     live area    20 x 20  (2 -> 22) — nothing may exceed it
     keylines     square  18 x 18 (3 -> 21)
                  circle  d 17.2   (r 8.6, cx/cy 12)
                  landscape 20 x 15 · portrait 15 x 20
     stroke       1.75, round caps, round joins
     fills        only where the glyph is solid by nature
                  (play, keyframe, star, cursor, sparkle, dots)

   Circles read larger than squares at the same measure, so the circle
   keyline is deliberately smaller than the square one. That single
   compensation is why the set sits still next to a row of text.

   Every glyph is drawn to a keyline, not to the view box. A glyph that
   fills 24 units next to one that fills 14 is the whole reason an icon
   set stops looking drawn by one hand.
*/

export const STROKE = 1.75;

/* ---- helpers ------------------------------------------------------ */

const P = (d, extra = '') => `<path d='${d}'${extra ? ' ' + extra : ''}/>`;
const SOLID = (d) => `<path d='${d}' fill='black' stroke='none'/>`;
const DOT = (cx, cy, r = 1.1) => `<circle cx='${cx}' cy='${cy}' r='${r}' fill='black' stroke='none'/>`;
const C = (cx, cy, r, extra = '') => `<circle cx='${cx}' cy='${cy}' r='${r}'${extra ? ' ' + extra : ''}/>`;
const R = (x, y, w, h, r, extra = '') =>
  `<rect x='${x}' y='${y}' width='${w}' height='${h}' rx='${r}'${extra ? ' ' + extra : ''}/>`;

/* A linear alpha ramp. Mask alpha honours gradients, so this gives a real
   fade instead of faking one with dots. Ids are scoped per data URI. */
const RAMP = (id, x1, y1, x2, y2, from = 1, to = 0) =>
  `<defs><linearGradient id='${id}' x1='${x1}' y1='${y1}' x2='${x2}' y2='${y2}'>` +
  `<stop offset='0' stop-color='black' stop-opacity='${from}'/>` +
  `<stop offset='1' stop-color='black' stop-opacity='${to}'/></linearGradient></defs>`;

/* A mechanical cog, generated so the teeth stay perfectly regular. */
function gear(teeth = 8, outer = 9.4, inner = 7.2, halfTooth = 12) {
  const pt = (r, a) => {
    const rad = (a * Math.PI) / 180;
    return `${(12 + r * Math.cos(rad)).toFixed(2)} ${(12 + r * Math.sin(rad)).toFixed(2)}`;
  };
  const step = 360 / teeth;
  const gap = step / 2 - halfTooth * 0.55;
  let d = '';
  for (let i = 0; i < teeth; i++) {
    const a = i * step - 90;
    d += (i ? 'L' : 'M') + pt(outer, a - halfTooth);
    d += 'L' + pt(outer, a + halfTooth);
    d += 'L' + pt(inner, a + halfTooth + gap);
    d += 'L' + pt(inner, a + step - halfTooth - gap);
  }
  return d + 'Z';
}

/* Radial ticks around a hub — suns, glows, apertures. */
function rays(count, r0, r1, offset = 0) {
  let d = '';
  for (let i = 0; i < count; i++) {
    const a = ((i * 360) / count + offset - 90) * (Math.PI / 180);
    const x0 = (12 + r0 * Math.cos(a)).toFixed(2), y0 = (12 + r0 * Math.sin(a)).toFixed(2);
    const x1 = (12 + r1 * Math.cos(a)).toFixed(2), y1 = (12 + r1 * Math.sin(a)).toFixed(2);
    d += `M${x0} ${y0}L${x1} ${y1}`;
  }
  return d;
}

/* Two overlapping shapes used by every boolean glyph, so the four ops
   are visibly the SAME two shapes with a different result. */
const B_SQ = 'M5.2 3.4h9.4a1.8 1.8 0 0 1 1.8 1.8v9.4a1.8 1.8 0 0 1-1.8 1.8H5.2a1.8 1.8 0 0 1-1.8-1.8V5.2a1.8 1.8 0 0 1 1.8-1.8Z';
const B_CI = 'M14.8 8.2a6.4 6.4 0 1 1 0 12.8 6.4 6.4 0 0 1 0-12.8Z';

/* ---- the library -------------------------------------------------- */
/* Each icon: [name, svg, blurb, keywords]. Blurb is the one-line meaning
   shown on the iconography page; keywords feed its search box. */

export const CATEGORIES = [
  {
    id: 'nav',
    name: 'Navigation & disclosure',
    note: 'Chevrons point at what opens. Arrows move you or move a thing. Never swap the two.',
    icons: [
      ['chevron-up', P('M5.5 15L12 8.5 18.5 15'), 'Collapse, previous in a stepper', 'up collapse less'],
      ['chevron-down', P('M5.5 9L12 15.5 18.5 9'), 'Expand a group, open a menu', 'down expand disclosure more menu'],
      ['chevron-left', P('M15 5.5L8.5 12 15 18.5'), 'Back, previous page', 'back previous prior'],
      ['chevron-right', P('M9 5.5L15.5 12 9 18.5'), 'Forward, drill into a row', 'forward next into'],
      ['chevron-updown', P('M7.5 10L12 5.5 16.5 10M7.5 14L12 18.5 16.5 14'), 'Stepper or sortable column', 'sort stepper pick select'],
      ['arrow-up', P('M12 19.5V5.4M6 11.4L12 5.4l6 6'), 'Move up an order', 'north raise'],
      ['arrow-down', P('M12 4.5v14.1M6 12.6l6 6 6-6'), 'Move down an order', 'south lower'],
      ['arrow-left', P('M19.5 12H5.4M11.4 6L5.4 12l6 6'), 'Go left, decrease', 'west back'],
      ['arrow-right', P('M4.5 12h14.1M12.6 6l6 6-6 6'), 'Go right, continue', 'east next continue'],
      ['more', DOT(5.9, 12, 1.55) + DOT(12, 12, 1.55) + DOT(18.1, 12, 1.55), 'Overflow menu, drag handle', 'ellipsis overflow options handle'],
      ['more-vertical', DOT(12, 5.9, 1.55) + DOT(12, 12, 1.55) + DOT(12, 18.1, 1.55), 'Row-level overflow menu', 'ellipsis kebab overflow'],
      ['external', P('M13.5 4.5h6v6M19.5 4.5l-8 8') + P('M17.5 14v4A3 3 0 0 1 14.5 21h-8A3 3 0 0 1 3.5 18v-8A3 3 0 0 1 6.5 7h4'), 'Open outside the app', 'link open new window browser'],
    ],
  },

  {
    id: 'action',
    name: 'Core actions',
    note: 'The verbs every surface shares. One concept, one glyph, app-wide.',
    icons: [
      ['plus', P('M12 4.6v14.8M4.6 12h14.8'), 'Add, create, insert', 'add new create insert'],
      ['minus', P('M4.6 12h14.8'), 'Remove one, collapse', 'remove subtract less'],
      ['x', P('M6.2 6.2l11.6 11.6M17.8 6.2L6.2 17.8'), 'Close, dismiss, clear', 'close dismiss cancel clear'],
      ['check', P('M4.8 12.4l4.9 4.9 9.5-10.6'), 'Done, on, confirmed', 'done ok confirm tick yes'],
      ['check-circle', C(12, 12, 8.6) + P('M8 12.2l2.9 2.9 5.3-6'), 'Succeeded, valid', 'success valid passed good'],
      ['x-circle', C(12, 12, 8.6) + P('M9.2 9.2l5.6 5.6M14.8 9.2l-5.6 5.6'), 'Failed, invalid', 'error fail invalid bad'],
      ['search', C(10.6, 10.6, 6.7) + P('M15.4 15.4l4.1 4.1'), 'Find, filter a list', 'find filter magnify lookup'],
      ['trash', P('M4.6 6.6h14.8M9.6 6.6V5A1.5 1.5 0 0 1 11.1 3.5h1.8A1.5 1.5 0 0 1 14.4 5v1.6M6.6 6.6l.9 11.6A2.3 2.3 0 0 0 9.8 20.5h4.4a2.3 2.3 0 0 0 2.3-2.3l.9-11.6') + P('M10.2 10.4v5.6M13.8 10.4v5.6'), 'Delete for good', 'delete remove bin destroy'],
      ['copy', R(9, 3.4, 11.6, 11.6, 2.6) + P('M15 20.6H6A2.6 2.6 0 0 1 3.4 18V9'), 'Copy to the clipboard', 'clipboard cmd-c'],
      ['duplicate', R(3.4, 7, 13.6, 13.6, 2.6) + P('M7 3.4h11a2.6 2.6 0 0 1 2.6 2.6v11'), 'Make a second one, in place', 'clone repeat cmd-d'],
      ['undo', P('M9.4 14.6L4.4 9.6l5-5') + P('M4.4 9.6h9.9a5.6 5.6 0 0 1 0 11.2h-3.6'), 'Step back through history', 'back revert cmd-z'],
      ['redo', P('M14.6 14.6l5-5-5-5') + P('M19.6 9.6H9.7a5.6 5.6 0 0 0 0 11.2h3.6'), 'Step forward again', 'forward cmd-shift-z'],
      ['save', P('M20.5 8.7V18a2.6 2.6 0 0 1-2.6 2.6H6.1A2.6 2.6 0 0 1 3.5 18V6a2.6 2.6 0 0 1 2.6-2.6h9.2z') + P('M8.4 3.4v4.9h6.3V3.4M7.4 20.6v-6.4h9.2v6.4'), 'Write the document to disk', 'disk write store cmd-s'],
      ['export', P('M12 15V4.2M8 8.2L12 4.2l4 4') + P('M4.4 15v3.4A2.2 2.2 0 0 0 6.6 20.6h10.8a2.2 2.2 0 0 0 2.2-2.2V15'), 'Send a rendition out of Photonz', 'render output publish png jpg'],
      ['import', P('M12 4.2V15M8 11l4 4 4-4') + P('M4.4 15v3.4A2.2 2.2 0 0 0 6.6 20.6h10.8a2.2 2.2 0 0 0 2.2-2.2V15'), 'Bring a file into the document', 'open place add file'],
      ['share', P('M12 15V3.8M8.4 7.4L12 3.8l3.6 3.6') + P('M4.6 13.4v5A2.2 2.2 0 0 0 6.8 20.6h10.4a2.2 2.2 0 0 0 2.2-2.2v-5'), 'Share sheet, copy a link', 'send airdrop link publish'],
      ['link', P('M10.2 13.4a4.4 4.4 0 0 0 6.6.5l2.6-2.6a4.4 4.4 0 0 0-6.2-6.2l-1.5 1.5') + P('M13.8 10.6a4.4 4.4 0 0 0-6.6-.5l-2.6 2.6a4.4 4.4 0 0 0 6.2 6.2l1.5-1.5'), 'Linked to its source', 'chain connected instance url'],
      ['unlink', P('M14.6 5.6l1.4-1.4a4.4 4.4 0 0 1 6.2 6.2l-1.4 1.4M9.4 18.4l-1.4 1.4a4.4 4.4 0 0 1-6.2-6.2l1.4-1.4') + P('M3.5 3.5l17 17'), 'Detach from its source', 'break detach unbind'],
      ['refresh', P('M20.4 12a8.4 8.4 0 1 1-2.5-6') + P('M20.4 4.4v5.5h-5.5'), 'Recompute, reload, re-run', 'reload sync retry regenerate'],
      ['settings', P(gear()) + C(12, 12, 3.1), 'Preferences and options', 'gear preferences options config'],
      ['info', C(12, 12, 8.6) + P('M12 11.2v5.2') + DOT(12, 7.9, 1.05), 'Explanatory detail', 'about help detail note'],
      ['help', C(12, 12, 8.6) + P('M9.5 9.6a2.6 2.6 0 0 1 5.1.7c0 1.7-2.5 2.2-2.5 3.9') + DOT(12, 16.9, 1.05), 'What does this do', 'question support learn'],
      ['filter', P('M3.6 5.4h16.8l-6.5 7.7v6.1l-3.8 2.1v-8.2z'), 'Narrow a list down', 'funnel narrow refine'],
    ],
  },

  {
    id: 'file',
    name: 'Documents & library',
    note: 'Everything that holds work: files, folders, collections, the asset library.',
    icons: [
      ['document', P('M14 3.4H6.8A2.4 2.4 0 0 0 4.4 5.8v12.4a2.4 2.4 0 0 0 2.4 2.4h10.4a2.4 2.4 0 0 0 2.4-2.4V8.8z') + P('M14 3.4v5.4h5.6'), 'A Photonz document', 'file page doc'],
      ['document-new', P('M14 3.4H6.8A2.4 2.4 0 0 0 4.4 5.8v12.4a2.4 2.4 0 0 0 2.4 2.4h4.6') + P('M14 3.4v5.4h5.6') + P('M17.4 14v6M14.4 17h6'), 'Start a new document', 'new blank create'],
      ['folder', P('M20.6 18.2a2.4 2.4 0 0 1-2.4 2.4H5.8a2.4 2.4 0 0 1-2.4-2.4V5.8a2.4 2.4 0 0 1 2.4-2.4h4.1l2.1 3.2h6.2a2.4 2.4 0 0 1 2.4 2.4z'), 'A folder of documents', 'directory group'],
      ['folder-open', P('M3.4 18.2V5.8a2.4 2.4 0 0 1 2.4-2.4h4.1l2.1 3.2h6.2a2.4 2.4 0 0 1 2.4 2.4v1.4') + P('M3.4 18.2l2.4-7.4h15.6l-2.5 7.7a2.4 2.4 0 0 1-2.3 1.7H5.8a2.4 2.4 0 0 1-2.4-2z'), 'The folder you are inside', 'open directory browse'],
      ['library', R(3.4, 3.4, 7.4, 7.4, 1.6) + C(16.9, 7.1, 3.7) + R(3.4, 13.2, 7.4, 7.4, 1.6) + P('M16.9 12.9l4.1 7.7h-8.2z'), 'Reusable assets you can place', 'assets collection kit deck components'],
      ['grid', R(3.4, 3.4, 7.6, 7.6, 1.8) + R(13, 3.4, 7.6, 7.6, 1.8) + R(3.4, 13, 7.6, 7.6, 1.8) + R(13, 13, 7.6, 7.6, 1.8), 'Thumbnail view', 'tiles gallery thumbnails view'],
      ['list', P('M8.6 6.6h11.4M8.6 12h11.4M8.6 17.4h11.4') + DOT(4.6, 6.6, 1.2) + DOT(4.6, 12, 1.2) + DOT(4.6, 17.4, 1.2), 'List view', 'rows table view'],
      ['tag', P('M20.4 13.6l-6.8 6.8a2.2 2.2 0 0 1-3.1 0l-6.7-6.7a2.2 2.2 0 0 1-.6-1.5V5.7a2.2 2.2 0 0 1 2.2-2.2h6.5a2.2 2.2 0 0 1 1.5.6l7 7a2.2 2.2 0 0 1 0 3.1z') + DOT(8.3, 8.3, 1.35), 'Label an asset', 'label keyword category'],
      ['image', R(3.4, 3.4, 17.2, 17.2, 2.8) + C(9, 8.8, 1.9) + P('M20.6 15.2l-4.7-4.7L5 20.6'), 'A raster image asset', 'photo bitmap picture raster'],
      ['star', SOLID('M12 3.4l2.72 5.66 6.18.9-4.47 4.36 1.05 6.15L12 17.47l-5.48 2.9 1.05-6.15L3.1 9.96l6.18-.9z'), 'Favourite, pinned to the top', 'favorite bookmark rating'],
      ['history', P('M3.6 12a8.4 8.4 0 1 0 2.8-6.3L3.4 8.2') + P('M3.4 3.4v4.8h4.8') + P('M12 7.6V12l3.2 1.9'), 'Version history, past states', 'versions time undo-stack revisions'],
      ['pin', P('M9.4 3.4h5.2l-.8 5.2 3 2.7v1.6H7.2v-1.6l3-2.7z') + P('M12 13v7.6'), 'Keep this pinned open', 'keep stick anchor'],
      ['archive', R(3.4, 4.4, 17.2, 4.4, 1.6) + P('M5.2 8.8v9.4a2.4 2.4 0 0 0 2.4 2.4h8.8a2.4 2.4 0 0 0 2.4-2.4V8.8') + P('M10.2 12.6h3.6'), 'Stow it without deleting it', 'box store stash'],
    ],
  },

  {
    id: 'view',
    name: 'View & canvas',
    note: 'Moving the eye, not the artwork. Nothing here mutates the document.',
    icons: [
      ['zoom-in', C(10.6, 10.6, 6.7) + P('M15.4 15.4l4.1 4.1M8 10.6h5.2M10.6 8v5.2'), 'Zoom the canvas in', 'magnify closer scale-view'],
      ['zoom-out', C(10.6, 10.6, 6.7) + P('M15.4 15.4l4.1 4.1M8 10.6h5.2'), 'Zoom the canvas out', 'magnify further'],
      ['zoom-fit', P('M3.6 9V5.4A1.8 1.8 0 0 1 5.4 3.6H9M15 3.6h3.6A1.8 1.8 0 0 1 20.4 5.4V9M20.4 15v3.6a1.8 1.8 0 0 1-1.8 1.8H15M9 20.4H5.4a1.8 1.8 0 0 1-1.8-1.8V15'), 'Fit the document in the window', 'fit frame contain shift-1'],
      ['zoom-actual', P('M3.6 9V5.4A1.8 1.8 0 0 1 5.4 3.6H9M15 3.6h3.6A1.8 1.8 0 0 1 20.4 5.4V9M20.4 15v3.6a1.8 1.8 0 0 1-1.8 1.8H15M9 20.4H5.4a1.8 1.8 0 0 1-1.8-1.8V15') + R(10.2, 10.2, 3.6, 3.6, 0.9, "fill='black' stroke='none'"), 'One image pixel per screen pixel', '100% actual-size one-to-one'],
      ['hand', P('M7.4 11.4V6.2a1.6 1.6 0 0 1 3.2 0M10.6 10.6V4.9a1.6 1.6 0 0 1 3.2 0v5.7M13.8 10.6V5.9a1.6 1.6 0 0 1 3.2 0V13M17 12.4V9a1.6 1.6 0 0 1 3.2 0v6.6a5 5 0 0 1-5 5h-2a6 6 0 0 1-5.1-2.9l-2-3.4a1.6 1.6 0 0 1 2.7-1.7l1.6 2.2'), 'Pan the canvas', 'pan grab drag space'],
      ['maximize', P('M4.4 9V6A1.6 1.6 0 0 1 6 4.4h3M15 4.4h3A1.6 1.6 0 0 1 19.6 6v3M19.6 15v3a1.6 1.6 0 0 1-1.6 1.6h-3M9 19.6H6A1.6 1.6 0 0 1 4.4 18v-3'), 'Fill the screen', 'fullscreen expand enlarge'],
      ['minimize', P('M9 4.4v3A1.6 1.6 0 0 1 7.4 9h-3M15 4.4v3A1.6 1.6 0 0 0 16.6 9h3M19.6 15h-3a1.6 1.6 0 0 0-1.6 1.6v3M4.4 15h3A1.6 1.6 0 0 1 9 16.6v3'), 'Leave full screen', 'restore shrink collapse'],
      ['sidebar-left', R(3.4, 4.6, 17.2, 14.8, 2.6) + P('M9.6 4.6v14.8'), 'Show or hide the left dock', 'panel navigator rail'],
      ['sidebar-right', R(3.4, 4.6, 17.2, 14.8, 2.6) + P('M14.4 4.6v14.8'), 'Show or hide the right dock', 'panel inspector properties'],
      ['panel-bottom', R(3.4, 4.6, 17.2, 14.8, 2.6) + P('M3.4 14.4h17.2'), 'Show or hide the timeline dock', 'drawer tray timeline'],
      ['canvas-grid', R(3.4, 3.4, 17.2, 17.2, 2.6) + P('M9.13 3.4v17.2M14.87 3.4v17.2M3.4 9.13h17.2M3.4 14.87h17.2'), 'Show the layout grid', 'guides layout columns'],
      ['rulers', P('M3.6 20.4V3.6h16.8') + P('M8.4 3.6v3M13 3.6v4.6M17.6 3.6v3M3.6 8.4h3M3.6 13h4.6M3.6 17.6h3'), 'Show rulers and units', 'measure units gutters'],
      ['snap', P('M6.6 3.8v7.6a5.4 5.4 0 0 0 10.8 0V3.8h-4v7.6a1.4 1.4 0 0 1-2.8 0V3.8z') + P('M6.6 7.8h4M13.4 7.8h4'), 'Snap to edges and guides', 'magnet align stick'],
    ],
  },

  {
    id: 'tool',
    name: 'Tools',
    note: 'Everything that can be the active tool. These carry the tool bar, so they must read at 16px against a glass background.',
    icons: [
      ['cursor', SOLID('M5.6 3.6l6.1 15.9 2.35-6.6 6.6-2.35z'), 'Select and transform', 'pointer arrow select v'],
      ['move', P('M12 3.4v17.2M3.4 12h17.2M8.6 6.8L12 3.4l3.4 3.4M8.6 17.2L12 20.6l3.4-3.4M6.8 8.6L3.4 12l3.4 3.4M17.2 8.6L20.6 12l-3.4 3.4'), 'Move the selection', 'reposition nudge drag'],
      ['marquee-rect', R(3.6, 3.6, 16.8, 16.8, 2.2, "stroke-dasharray='3.4 2.9'"), 'Rectangular selection', 'select box crop-region m'],
      ['marquee-ellipse', C(12, 12, 8.4, "stroke-dasharray='3.4 2.9'"), 'Elliptical selection', 'select oval circle round'],
      ['lasso', P('M12 4.2c4.6 0 8.2 2.6 8.2 5.9 0 3.2-3.6 5.8-8.2 5.8-1.5 0-2.9-.3-4.1-.8-1.4.9-2.5 1.7-3.2 2.6.4-1.3.5-2.4.4-3.3-.9-.9-1.3-2-1.3-3.2 0-3.3 3.6-5.9 8.2-5.9z') + P('M7.4 15.2v3a1.9 1.9 0 1 0 1.9 1.9'), 'Free-hand selection', 'freehand select outline l'],
      ['wand', P('M3.8 20.2L13 11') + SOLID('M16.8 2.9l1.32 3.09 3.09 1.32-3.09 1.32-1.32 3.09-1.32-3.09L12.39 7.31l3.09-1.32z') + SOLID('M7.4 3.2l.68 1.6 1.6.68-1.6.68L7.4 7.76l-.68-1.6-1.6-.68 1.6-.68z') + SOLID('M20.2 14.4l.62 1.46 1.46.62-1.46.62-.62 1.46-.62-1.46-1.46-.62 1.46-.62z'), 'Select by similarity', 'magic auto select w'],
      ['subject', P('M6.4 20.2a5.6 5.6 0 0 1 11.2 0') + C(12, 8.2, 3.9) + P('M3.4 7V4.6a1.2 1.2 0 0 1 1.2-1.2H7M17 3.4h2.4a1.2 1.2 0 0 1 1.2 1.2V7M20.6 17v2.4a1.2 1.2 0 0 1-1.2 1.2H17M7 20.6H4.6a1.2 1.2 0 0 1-1.2-1.2V17', "stroke-dasharray='0'"), 'Select the subject for me', 'auto person cutout ai'],
      ['crop', P('M6.6 2.6v12.8a2.4 2.4 0 0 0 2.4 2.4h12.4M2.6 6.6h12.8a2.4 2.4 0 0 1 2.4 2.4v12.4'), 'Crop and re-frame', 'trim reframe c'],
      ['straighten', P('M3.4 16.6L20.6 7.4') + P('M3.4 20.6h17.2M3.4 20.6v-2.4M20.6 20.6v-2.4'), 'Level the horizon', 'rotate level horizon angle'],
      ['ruler', P('M15.6 2.9l5.5 5.5a1.4 1.4 0 0 1 0 2L10.4 21.1a1.4 1.4 0 0 1-2 0L2.9 15.6a1.4 1.4 0 0 1 0-2L13.6 2.9a1.4 1.4 0 0 1 2 0z') + P('M7.1 11.3l1.9 1.9M10.3 8.1l1.9 1.9M13.5 4.9l1.9 1.9'), 'Measure and redline', 'measure distance dimension redline'],
      ['eyedropper', P('M3.4 20.6l1-1h3l8.8-8.8') + P('M4.4 19.6v-3l8.8-8.8') + P('M15.4 6.2l3.2-3.2a2.1 2.1 0 1 1 3 3l-3.2 3.2.4.4a2.1 2.1 0 1 1-3 3l-3.8-3.8a2.1 2.1 0 1 1 3-3z'), 'Pick a colour from the canvas', 'picker sample color i'],
      ['pen', P('M8.4 4.4h7.2v8.7L12 20.6l-3.6-7.5z') + P('M8.4 13.1h7.2M12 14.8v5.8') + C(12, 8.6, 1.5), 'Draw a vector path', 'nib bezier path vector p'],
      ['pencil', P('M12 20.6h8.6') + P('M16.4 3.9a2.4 2.4 0 0 1 3.4 3.4L8.2 18.9l-4.5 1.1 1.1-4.5z'), 'Edit, rename, freehand line', 'edit write draw'],
      ['brush', P('M9.6 12.2l8.2-8.2a2.1 2.1 0 0 1 3 3l-8.2 8.2') + P('M7.2 14.2a3.1 3.1 0 0 0-3.1 3.1c0 1.4-2 1.6-2 2.1 1 1 2.6 2.1 4.1 2.1a4.1 4.1 0 0 0 4.1-4.1 3.1 3.1 0 0 0-3.1-3.2z'), 'Paint with the brush engine', 'paint stroke bristle b'],
      ['eraser', P('M8.6 20.5h11.9') + P('M4.7 16.3l3.1 3.1a2.2 2.2 0 0 0 3.1 0l8.6-8.6a2.2 2.2 0 0 0 0-3.1l-3.1-3.1a2.2 2.2 0 0 0-3.1 0L4.7 13.2a2.2 2.2 0 0 0 0 3.1z') + P('M9.7 8.2l6.1 6.1'), 'Erase back to transparent', 'rub delete pixels e'],
      ['fill', P('M18.4 11.2L11.2 4a1.9 1.9 0 0 0-2.7 0l-5.4 5.4a1.9 1.9 0 0 0 0 2.7l5.4 5.4a1.9 1.9 0 0 0 2.7 0z') + P('M6.4 3.4l2.1 2.1M3.5 12.9h14.9') + SOLID('M20.6 20.4a1.7 1.7 0 0 1-3.4 0c0-1.4 1.4-2.1 1.7-3.4.3 1.3 1.7 2 1.7 3.4z'), 'Flood fill a region', 'bucket paint-can g'],
      ['gradient', R(3.4, 3.4, 17.2, 17.2, 2.8) + R(6.4, 6.4, 11.2, 11.2, 1.4, "fill='url(#gr)' stroke='none'") + RAMP('gr', 0, 0, 1, 1), 'Fill with a gradient ramp', 'ramp blend linear radial'],
      ['clone', P('M8.6 3.4h6.8l-1 5h-4.8z') + R(4.4, 8.4, 15.2, 4, 1.5) + P('M6.9 12.4v4.4a3.4 3.4 0 0 0 3.4 3.4h3.4a3.4 3.4 0 0 0 3.4-3.4v-4.4'), 'Clone stamp from a source point', 'stamp source copy-pixels s'],
      ['heal', P('M4.9 14.6l9.7-9.7a3.4 3.4 0 0 1 4.8 0 3.4 3.4 0 0 1 0 4.8l-9.7 9.7a3.4 3.4 0 0 1-4.8 0 3.4 3.4 0 0 1 0-4.8z') + DOT(10.4, 13.6, 1.05) + DOT(13.6, 10.4, 1.05), 'Heal a blemish from its surroundings', 'spot repair retouch blemish j'],
      ['patch', P('M2.9 7.7a4.8 4.8 0 0 1 4.8-4.8h3.4a4.8 4.8 0 1 1 0 9.6H7.7a4.8 4.8 0 0 1-4.8-4.8z', "stroke-dasharray='3 2.8'") + P('M8.3 16.3a4.8 4.8 0 0 1 4.8-4.8h3.4a4.8 4.8 0 1 1 0 9.6h-3.4a4.8 4.8 0 0 1-4.8-4.8z'), 'Patch an area from a clean source', 'replace region source-fill'],
      ['dodge-burn', C(8.9, 12, 5.5) + `<circle cx='15.1' cy='12' r='5.5' fill='black' stroke='none'/>`, 'Lighten or darken by hand', 'dodge burn exposure-brush o'],
      ['blur-tool', P('M12 3.2c0 0 6.4 6.5 6.4 10.6a6.4 6.4 0 1 1-12.8 0C5.6 9.7 12 3.2 12 3.2z') + P('M9.4 14.6a2.6 2.6 0 0 0 2.6 2.6'), 'Soften an area by hand', 'soften smudge droplet r'],
      ['text', P('M5.4 6.6V4.4h13.2v2.2M12 4.4v15.2M9 19.6h6'), 'Add or edit a text layer', 'type font letter t'],
    ],
  },

  {
    id: 'shape',
    name: 'Shapes & vector',
    note: 'The vector primitives and the operations that combine them. The four booleans are deliberately the same two shapes with a different result.',
    icons: [
      ['square', R(3.4, 3.4, 17.2, 17.2, 3.2), 'Rectangle shape', 'rect box rounded r'],
      ['circle', C(12, 12, 8.6), 'Ellipse shape', 'ellipse oval round o'],
      ['line', P('M4.6 19.4L19.4 4.6'), 'Straight line shape', 'segment stroke rule'],
      ['triangle', P('M10.3 4.7L2.9 17.5a2 2 0 0 0 1.7 3h14.8a2 2 0 0 0 1.7-3L13.7 4.7a2 2 0 0 0-3.4 0z'), 'Triangle shape', 'polygon three'],
      ['polygon', P('M12 3.1l7.5 4.35v8.7L12 20.5l-7.5-4.35v-8.7z'), 'Regular polygon shape', 'hexagon ngon sides'],
      ['frame', P('M4 8.6h16M4 15.4h16M8.6 4v16M15.4 4v16'), 'A frame that clips its children', 'artboard board container group'],
      ['bezier', P('M4.2 18.2C4.2 9.4 19.8 14.6 19.8 5.8') + R(2.2, 16.2, 4, 4, 1.2) + R(17.8, 3.8, 4, 4, 1.2), 'A curve between two points', 'curve spline handle path'],
      ['node', C(12, 12, 2.4) + P('M5 19l4.4-4.4M19 5l-4.4 4.4') + R(2.6, 16.6, 3.6, 3.6, 1) + R(17.8, 3.8, 3.6, 3.6, 1), 'Edit a point and its handles', 'anchor point vertex handle'],
      ['corner-radius', P('M4.4 19.6V10.4A6 6 0 0 1 10.4 4.4h9.2') + P('M4.4 10.4V4.4h6', "stroke-dasharray='2.6 2.6'") + DOT(4.4, 4.4, 1.15), 'Round the corners', 'radius rounding fillet'],
      ['boolean-union', `<path d='${B_SQ}${B_CI}' fill='black' stroke='none' opacity='.42'/><path d='${B_SQ}'/><path d='${B_CI}'/>`, 'Keep both shapes as one', 'combine merge weld add'],
      ['boolean-subtract', `<defs><mask id='bs'><path d='${B_SQ}' fill='white'/><path d='${B_CI}' fill='black'/></mask></defs><path d='${B_SQ}' mask='url(#bs)' fill='black' stroke='none' opacity='.42'/><path d='${B_SQ}'/><path d='${B_CI}'/>`, 'Remove the top shape', 'minus front knockout'],
      ['boolean-intersect', `<defs><clipPath id='bi'><path d='${B_SQ}'/></clipPath></defs><path d='${B_CI}' clip-path='url(#bi)' fill='black' stroke='none' opacity='.55'/><path d='${B_SQ}'/><path d='${B_CI}'/>`, 'Keep only the overlap', 'intersection common'],
      ['boolean-exclude', `<path fill-rule='evenodd' d='${B_SQ}${B_CI}' fill='black' stroke='none' opacity='.42'/><path d='${B_SQ}'/><path d='${B_CI}'/>`, 'Keep everything but the overlap', 'xor difference'],
      ['flatten', P('M12 2.9L4.3 6.6 12 10.3l7.7-3.7z') + P('M12 12.6v4.6M9.4 14.8l2.6 2.6 2.6-2.6') + P('M4.3 20.6h15.4', "stroke-width='2.4'"), 'Flatten to a single layer', 'bake rasterize collapse outline-stroke'],
    ],
  },

  {
    id: 'layer',
    name: 'Layers & structure',
    note: 'Layers are everything in Photonz, so this group has to be the most legible one in the set.',
    icons: [
      ['layers', P('M12 3.2L3.1 7.6 12 12l8.9-4.4z') + P('M3.1 16.4L12 20.8l8.9-4.4M3.1 12L12 16.4 20.9 12'), 'The layer stack', 'stack z-order composite'],
      ['layer-add', P('M12 3.2L3.1 7.6 12 12l8.9-4.4z') + P('M3.1 12l4.4 2.2M12 16.4l3.4-1.7') + P('M17.6 14.4v6M14.6 17.4h6'), 'Add a layer', 'new-layer insert'],
      ['group', P('M3.6 8.4V5.4A1.8 1.8 0 0 1 5.4 3.6h3M15.6 3.6h3a1.8 1.8 0 0 1 1.8 1.8v3M20.4 15.6v3a1.8 1.8 0 0 1-1.8 1.8h-3M8.4 20.4h-3a1.8 1.8 0 0 1-1.8-1.8v-3') + R(8.8, 8.8, 6.4, 6.4, 1.6), 'Group the selection', 'nest folder cmd-g'],
      ['ungroup', P('M3.6 8.4V5.4A1.8 1.8 0 0 1 5.4 3.6h3M15.6 3.6h3a1.8 1.8 0 0 1 1.8 1.8v3M20.4 15.6v3a1.8 1.8 0 0 1-1.8 1.8h-3M8.4 20.4h-3a1.8 1.8 0 0 1-1.8-1.8v-3') + P('M9.2 12h5.6'), 'Break the group apart', 'unnest release flatten-group'],
      ['component', P('M12 2.9l4.2 4.2-4.2 4.2-4.2-4.2z') + P('M12 12.7l4.2 4.2-4.2 4.2-4.2-4.2z') + P('M17 7.8l4.2 4.2-4.2 4.2M7 7.8L2.8 12 7 16.2'), 'A reusable component', 'symbol master reusable'],
      ['instance', P('M12 3.4l8.6 8.6-8.6 8.6L3.4 12z'), 'An instance of a component', 'copy linked child'],
      ['mask', R(3.4, 3.4, 17.2, 17.2, 3.2) + SOLID('M12 6.6a5.4 5.4 0 1 1 0 10.8 5.4 5.4 0 0 1 0-10.8z'), 'Mask a layer to a shape', 'alpha clip cutout stencil'],
      ['clip', P('M8.2 4.6v9.6a2.6 2.6 0 0 0 2.6 2.6h8.4') + P('M15.8 13.6l3.8 3.2-3.8 3.2'), 'Clip to the layer below', 'clipping nest inside'],
      ['eye', P('M2.9 12s3.6-6.6 9.1-6.6S21.1 12 21.1 12s-3.6 6.6-9.1 6.6S2.9 12 2.9 12z') + C(12, 12, 3), 'Layer is visible', 'show visible unhide preview'],
      ['eye-off', P('M17.6 17.6A9.9 9.9 0 0 1 12 19.2C6.4 19.2 2.9 12 2.9 12a18 18 0 0 1 4.7-5.6M9.9 4.9A10 10 0 0 1 12 4.7c5.6 0 9.1 7.3 9.1 7.3a18.4 18.4 0 0 1-2.4 3.5') + P('M3.4 3.4l17.2 17.2'), 'Layer is hidden', 'hide invisible off'],
      ['lock', R(4.2, 10.6, 15.6, 9.8, 2.4) + P('M8 10.6V7.6a4 4 0 0 1 8 0v3'), 'Locked from editing', 'locked protected frozen'],
      ['unlock', R(4.2, 10.6, 15.6, 9.8, 2.4) + P('M8 10.6V7.6a4 4 0 0 1 7.6-1.8'), 'Unlocked and editable', 'open unprotected'],
      ['opacity', `<defs><clipPath id='op'><circle cx='12' cy='12' r='8.6'/></clipPath></defs><g clip-path='url(#op)' fill='black' stroke='none' opacity='.45'><rect x='3' y='3' width='9' height='9'/><rect x='12' y='12' width='9' height='9'/></g>` + C(12, 12, 8.6), 'Layer opacity', 'alpha transparency fade checker'],
      ['blend', C(8.8, 12, 5.6) + C(15.2, 12, 5.6) + `<defs><clipPath id='bl'><circle cx='8.8' cy='12' r='5.6'/></clipPath></defs><circle cx='15.2' cy='12' r='5.6' clip-path='url(#bl)' fill='black' stroke='none' opacity='.5'/>`, 'Blend mode', 'multiply screen overlay mix'],
      ['merge', P('M6.4 3.6v6.2a3.2 3.2 0 0 0 3.2 3.2h4.8a3.2 3.2 0 0 0 3.2-3.2V3.6') + P('M12 13v7.4M8.6 17l3.4 3.4L15.4 17'), 'Merge the selected layers', 'flatten combine collapse'],
    ],
  },

  {
    id: 'arrange',
    name: 'Transform & arrange',
    note: 'Alignment glyphs always show the edge you are aligning to as a solid rule, plus two objects landing on it.',
    icons: [
      ['flip-horizontal', P('M12 3.4v17.2', "stroke-dasharray='2.6 2.4'") + P('M9.4 6.6L4 12l5.4 5.4z') + P('M14.6 6.6L20 12l-5.4 5.4z'), 'Mirror left to right', 'mirror reflect horizontal'],
      ['flip-vertical', P('M3.4 12h17.2', "stroke-dasharray='2.6 2.4'") + P('M6.6 9.4L12 4l5.4 5.4z') + P('M6.6 14.6L12 20l5.4-5.4z'), 'Mirror top to bottom', 'mirror reflect vertical'],
      ['rotate-left', P('M3.6 12a8.4 8.4 0 1 0 2.8-6.3L3.4 8.2') + P('M3.4 3.4v4.8h4.8'), 'Rotate 90 counter-clockwise', 'ccw turn anticlockwise'],
      ['rotate-right', P('M20.4 12a8.4 8.4 0 1 1-2.8-6.3L20.6 8.2') + P('M20.6 3.4v4.8h-4.8'), 'Rotate 90 clockwise', 'cw turn clockwise'],
      ['align-left', P('M3.9 3.6v16.8') + R(7.2, 6, 12.8, 4.6, 1.4) + R(7.2, 13.4, 8.4, 4.6, 1.4), 'Align to the left edge', 'left edge justify-objects'],
      ['align-center-h', P('M12 3.6v16.8') + R(5.6, 6, 12.8, 4.6, 1.4) + R(7.8, 13.4, 8.4, 4.6, 1.4), 'Align on the vertical centre', 'center middle horizontal'],
      ['align-right', P('M20.1 3.6v16.8') + R(4, 6, 12.8, 4.6, 1.4) + R(8.4, 13.4, 8.4, 4.6, 1.4), 'Align to the right edge', 'right edge'],
      ['align-top', P('M3.6 3.9h16.8') + R(6, 7.2, 4.6, 12.8, 1.4) + R(13.4, 7.2, 4.6, 8.4, 1.4), 'Align to the top edge', 'top edge'],
      ['align-middle', P('M3.6 12h16.8') + R(6, 5.6, 4.6, 12.8, 1.4) + R(13.4, 7.8, 4.6, 8.4, 1.4), 'Align on the horizontal centre', 'middle center vertical'],
      ['align-bottom', P('M3.6 20.1h16.8') + R(6, 4, 4.6, 12.8, 1.4) + R(13.4, 8.4, 4.6, 8.4, 1.4), 'Align to the bottom edge', 'bottom edge'],
      ['distribute-h', P('M3.9 3.6v16.8M20.1 3.6v16.8') + R(9.4, 7.4, 5.2, 9.2, 1.4), 'Equal gaps left to right', 'spacing spread even horizontal'],
      ['distribute-v', P('M3.6 3.9h16.8M3.6 20.1h16.8') + R(7.4, 9.4, 9.2, 5.2, 1.4), 'Equal gaps top to bottom', 'spacing spread even vertical'],
      ['bring-forward', R(3.6, 3.6, 12, 12, 2.2) + P('M8.4 20.4h9.6a2.4 2.4 0 0 0 2.4-2.4V8.4'), 'Bring one step forward', 'raise up z-order front'],
      ['send-backward', R(8.4, 8.4, 12, 12, 2.2) + P('M15.6 3.6H6a2.4 2.4 0 0 0-2.4 2.4v9.6'), 'Send one step back', 'lower down z-order back'],
      ['swap', P('M4.4 8.6h13.4M14 4.8l3.8 3.8-3.8 3.8') + P('M19.6 15.4H6.2M10 11.6l-3.8 3.8 3.8 3.8'), 'Swap two things', 'exchange replace switch'],
      ['scale', R(3.4, 3.4, 12.4, 12.4, 2.2) + P('M12.6 12.6l8 8M20.6 14.8v5.8h-5.8'), 'Scale the selection', 'resize transform size'],
      ['flow-horizontal', R(2.8, 8.4, 6.4, 7.2, 1.8) + R(14.8, 8.4, 6.4, 7.2, 1.8) + P('M9.2 12h5.6M12.6 9.8l2.2 2.2-2.2 2.2'), 'Lay children out in a row', 'auto-layout row direction stack'],
      ['flow-vertical', R(8.4, 2.8, 7.2, 6.4, 1.8) + R(8.4, 14.8, 7.2, 6.4, 1.8) + P('M12 9.2v5.6M9.8 12.6l2.2 2.2 2.2-2.2'), 'Lay children out in a column', 'auto-layout column direction stack'],
    ],
  },

  {
    id: 'adjust',
    name: 'Adjust & effects',
    note: 'Non-destructive edits. Each glyph names its parameter so an effect row is readable without its label.',
    icons: [
      ['sliders', P('M5.2 20.4v-6.2M5.2 9.8V3.6M12 20.4v-8.6M12 7.4V3.6M18.8 20.4v-4.6M18.8 11.4V3.6M2.6 14.2h5.2M9.4 7.4h5.2M16.2 15.8h5.2'), 'Adjustment controls', 'controls settings tune knobs'],
      ['swatch', P('M12 3.4a8.6 8.6 0 0 0 0 17.2c1.25 0 1.9-.85 1.9-1.8 0-.5-.2-.95-.55-1.3a1.75 1.75 0 0 1 1.25-3h2.1a4.05 4.05 0 0 0 4-4.05c0-4.05-3.9-7.05-8.7-7.05z') + DOT(8.4, 8.6, 1.15) + DOT(12.4, 7.2, 1.15) + DOT(7.2, 13, 1.15), 'Pick a colour', 'color palette fill chip'],
      ['exposure', C(12, 12, 4.4) + P(rays(8, 7.4, 9.9)), 'Exposure and brightness', 'brightness light sun ev'],
      ['contrast', C(12, 12, 8.6) + SOLID('M12 3.4a8.6 8.6 0 0 1 0 17.2z'), 'Contrast', 'tone punch levels'],
      ['saturation', P('M12 3.2c0 0 6.4 6.5 6.4 10.6a6.4 6.4 0 1 1-12.8 0C5.6 9.7 12 3.2 12 3.2z') + SOLID('M12 3.2c0 0 6.4 6.5 6.4 10.6a6.4 6.4 0 0 1-6.4 6.4z'), 'Saturation and vibrance', 'vibrance color chroma'],
      ['temperature', P('M14.2 14.4V6a2.2 2.2 0 0 0-4.4 0v8.4a4.8 4.8 0 1 0 4.4 0z') + P('M12 9.6v6.6'), 'White balance', 'white-balance kelvin warm cool'],
      ['curves', R(3.4, 3.4, 17.2, 17.2, 2.6) + P('M4.4 19.6c5.4 0 3.2-5.4 7.6-7.6s2.2-7.6 7.6-7.6') + DOT(8.1, 16.4, 1.3) + DOT(15.9, 7.6, 1.3), 'Tone curve', 'tone rgb histogram-curve'],
      ['levels', P('M3.6 20.4h16.8') + P('M6.2 20.4v-4.6M9.4 20.4v-9.2M12.6 20.4v-13M15.8 20.4v-8M19 20.4v-4'), 'Levels and histogram', 'histogram black-point white-point'],
      ['sharpen', P('M12 3.8l8.4 15.4H3.6z') + P('M12 3.8v15.4') + SOLID('M12 5.6l6.6 12.1H12z'), 'Sharpen detail', 'clarity detail unsharp'],
      ['blur', "<circle cx='12' cy='12' r='9' fill='url(#bu)' stroke='none'/><defs><radialGradient id='bu'><stop offset='.15' stop-color='black'/><stop offset='.55' stop-color='black' stop-opacity='.55'/><stop offset='1' stop-color='black' stop-opacity='0'/></radialGradient></defs>", 'Blur', 'gaussian soften defocus'],
      ['noise', DOT(5.4, 5.6, 1.25) + DOT(10.6, 4.4, .85) + DOT(15.8, 6.2, 1.25) + DOT(19.6, 4.6, .85) + DOT(8, 9.4, .85) + DOT(13.4, 9.8, 1.25) + DOT(18.8, 10.6, .85) + DOT(4.6, 12.6, 1.25) + DOT(10, 14.4, .85) + DOT(16.2, 14.8, 1.25) + DOT(6.4, 18.2, .85) + DOT(12.4, 19.2, 1.25) + DOT(19.2, 18.6, .85), 'Grain and noise', 'grain film dither texture'],
      ['vignette', R(3.4, 3.4, 17.2, 17.2, 2.8) + `<rect x='3.4' y='3.4' width='17.2' height='17.2' rx='2.8' fill='url(#vg)' stroke='none'/><defs><radialGradient id='vg'><stop offset='.45' stop-color='black' stop-opacity='0'/><stop offset='1' stop-color='black' stop-opacity='.85'/></radialGradient></defs>`, 'Vignette', 'edge-darkening falloff'],
      ['shadow', R(3.4, 3.4, 13.2, 13.2, 2.8) + `<rect x='7.4' y='7.4' width='13.2' height='13.2' rx='2.8' fill='black' stroke='none' opacity='.4'/>`, 'Drop shadow', 'drop-shadow elevation depth'],
      ['glow', C(12, 12, 4.2) + `<circle cx='12' cy='12' r='9' fill='url(#gl)' stroke='none'/><defs><radialGradient id='gl'><stop offset='.35' stop-color='black' stop-opacity='.55'/><stop offset='1' stop-color='black' stop-opacity='0'/></radialGradient></defs>`, 'Outer glow', 'bloom halo light'],
      ['border', R(2.8, 2.8, 18.4, 18.4, 3.4) + R(7, 7, 10, 10, 1.8), 'Border and stroke width', 'stroke outline edge weight'],
      ['effects', P('M4.4 7.4h9.2M4.4 12h6.6M4.4 16.6h9.2') + SOLID('M17.6 4.2l1.3 3.5 3.5 1.3-3.5 1.3-1.3 3.5-1.3-3.5-3.5-1.3 3.5-1.3z'), 'The effect stack on a layer', 'fx stack filters adjustments'],
    ],
  },

  {
    id: 'type',
    name: 'Type',
    note: 'Text-alignment glyphs are the ragged-line family. Object alignment lives in Transform & arrange and never uses these.',
    icons: [
      ['bold', P('M7 4.6h6.2a3.9 3.9 0 0 1 0 7.8H7z', "stroke-width='2.6'") + P('M7 12.4h7.2a3.9 3.9 0 0 1 0 7.8H7z', "stroke-width='2.6'"), 'Bold', 'weight strong cmd-b'],
      ['italic', P('M10.4 4.4h8.2M5.4 19.6h8.2M14.8 4.4L9.2 19.6'), 'Italic', 'oblique slant cmd-i'],
      ['underline', P('M6.6 4v6.6a5.4 5.4 0 0 0 10.8 0V4') + P('M5.6 20.2h12.8'), 'Underline', 'cmd-u'],
      ['strikethrough', P('M4.4 12h15.2') + P('M7 7.4A3.6 3.6 0 0 1 10.6 4.4h3.6a3.6 3.6 0 0 1 3.4 2.4M17 16.6a3.6 3.6 0 0 1-3.6 3h-3a3.6 3.6 0 0 1-3.4-2.4'), 'Strikethrough', 'strike cross-out'],
      ['text-align-left', P('M3.8 5.6h16.4M3.8 10.4h10.4M3.8 15.2h13.6M3.8 20h8.4'), 'Ragged right', 'left flush-left'],
      ['text-align-center', P('M3.8 5.6h16.4M6.8 10.4h10.4M5.2 15.2h13.6M7.8 20h8.4'), 'Centred', 'center centre'],
      ['text-align-right', P('M3.8 5.6h16.4M9.8 10.4h10.4M6.6 15.2h13.6M11.8 20h8.4'), 'Ragged left', 'right flush-right'],
      ['text-align-justify', P('M3.8 5.6h16.4M3.8 10.4h16.4M3.8 15.2h16.4M3.8 20h16.4'), 'Justified', 'justify block'],
      ['line-height', P('M8.4 5.4h11.8M8.4 12h11.8M8.4 18.6h11.8') + P('M4.2 4.4v15.2M2.4 6.2l1.8-1.8 1.8 1.8M2.4 17.8l1.8 1.8 1.8-1.8'), 'Line height', 'leading spacing rows'],
      ['letter-spacing', P('M9 14.4L12 6l3 8.4M9.9 12.2h4.2') + P('M4 4.6v14.8M20 4.6v14.8'), 'Letter spacing', 'tracking kerning'],
      ['font-size', P('M3.4 8V5.6h8.8V8M7.8 5.6v13.6M5.8 19.2h4') + P('M13.6 12.6v-1.4h7v1.4M17.1 11.2v8M15.5 19.2h3.2'), 'Font size', 'size points scale-type'],
      ['list-bullet', P('M9 6.4h11M9 12h11M9 17.6h11') + DOT(4.8, 6.4, 1.35) + DOT(4.8, 12, 1.35) + DOT(4.8, 17.6, 1.35), 'Bulleted list', 'bullets unordered'],
      ['list-number', P('M9.4 6.4h10.6M9.4 12h10.6M9.4 17.6h10.6') + P('M3.6 4.6h1.4v3.8M3.4 12.4a1.3 1.3 0 0 1 2.3.8c0 .9-2.3 1.6-2.3 2.6h2.4M3.4 16.6h2.4l-1.3 1.6a1.2 1.2 0 1 1-1 1.8'), 'Numbered list', 'ordered numbers'],
    ],
  },

  {
    id: 'time',
    name: 'Media & timeline',
    note: 'Transport glyphs are solid so they hold up in a 22px scrubber; everything structural stays a line glyph.',
    icons: [
      ['play', SOLID('M7.4 4.9l12 7.1-12 7.1z'), 'Play', 'transport start space'],
      ['pause', SOLID('M7.4 4.4h3.2v15.2H7.4zM13.4 4.4h3.2v15.2h-3.2z'), 'Pause', 'transport stop-temporarily'],
      ['stop', SOLID('M6.6 6.6h10.8v10.8H6.6z'), 'Stop', 'transport end halt'],
      ['skip-back', SOLID('M19 5.2v13.6L8.2 12z') + P('M5 5.2v13.6'), 'Jump to the start', 'previous rewind first'],
      ['skip-forward', SOLID('M5 5.2v13.6L15.8 12z') + P('M19 5.2v13.6'), 'Jump to the end', 'next fast-forward last'],
      ['step-back', SOLID('M18.4 7v10L9.8 12z') + P('M6.4 9.6v4.8', "stroke-width='2.4'"), 'One frame back', 'frame previous nudge'],
      ['step-forward', SOLID('M5.6 7v10l8.6-5z') + P('M17.6 9.6v4.8', "stroke-width='2.4'"), 'One frame forward', 'frame next nudge'],
      ['loop', P('M6.6 6.4h10.8a3.4 3.4 0 0 1 3.4 3.4v.6') + P('M17.4 17.6H6.6a3.4 3.4 0 0 1-3.4-3.4v-.6') + P('M17.8 3.4l2.8 3-2.8 3M6.2 20.6l-2.8-3 2.8-3'), 'Loop playback', 'repeat cycle again'],
      ['keyframe', SOLID('M12 3.6l8.4 8.4-8.4 8.4L3.6 12z'), 'A keyframe on the timeline', 'animate diamond value-at-time'],
      ['transition', SOLID('M4.4 4.4L11 12l-6.6 7.6z') + SOLID('M19.6 4.4L13 12l6.6 7.6z'), 'A transition between clips', 'crossfade dissolve wipe'],
      ['blade', R(2.8, 7, 8, 10, 2) + R(13.2, 7, 8, 10, 2) + P('M12 3.4v17.2', "stroke-dasharray='2.6 2.4'"), 'Split the clip at the playhead', 'razor cut split scissors'],
      ['trim', R(3.4, 6.4, 17.2, 11.2, 2.4) + R(5.4, 8.6, 2.6, 6.8, 1, "fill='black' stroke='none'") + R(16, 8.6, 2.6, 6.8, 1, "fill='black' stroke='none'"), 'Trim the in and out points', 'in out handles range'],
      ['speed', C(12, 13.2, 7.6) + P('M12 13.2l4.2-4.2') + P('M3.4 6.4l2.4 1.8M20.6 6.4l-2.4 1.8M12 3.6v2'), 'Clip speed and time remap', 'rate slow-motion ramp tempo'],
      ['timeline', R(3.4, 5.6, 9.2, 5, 1.4) + R(9.6, 13.4, 11, 5, 1.4) + P('M7.2 3.4v17.2') + DOT(7.2, 3.9, 1.5), 'The timeline dock', 'tracks sequence playhead edit'],
      ['audio', P('M9.4 17.6V5.2l11.2-1.8v12.4') + C(6.4, 17.6, 3.1) + C(17.6, 15.8, 3.1), 'An audio clip', 'music sound track note'],
      ['waveform', P('M3.4 12v0M6.2 8.4v7.2M9 5.4v13.2M11.8 9.6v4.8M14.6 6.4v11.2M17.4 9v6M20.6 10.8v2.4'), 'Audio waveform', 'levels amplitude sound'],
      ['volume', P('M4.4 9.4h3.2L12.6 5.2v13.6L7.6 14.6H4.4z') + P('M15.8 9.4a3.6 3.6 0 0 1 0 5.2M18.4 6.6a7.4 7.4 0 0 1 0 10.8'), 'Volume', 'sound level loud'],
      ['volume-off', P('M4.4 9.4h3.2L12.6 5.2v13.6L7.6 14.6H4.4z') + P('M16.2 9.8l4.4 4.4M20.6 9.8l-4.4 4.4'), 'Muted', 'mute silent off'],
      ['mic', R(9, 3.4, 6, 11.2, 3) + P('M5.6 11.6v1.4a6.4 6.4 0 0 0 12.8 0v-1.4M12 19.4v1.2'), 'Record from the microphone', 'record voice-over narrate'],
      ['captions', R(3.4, 5.2, 17.2, 13.6, 2.8) + P('M9.4 10.4a2.4 2.4 0 1 0 0 3.2M16.6 10.4a2.4 2.4 0 1 0 0 3.2'), 'Captions and subtitles', 'subtitles cc text-track'],
      ['video', P('M3.4 7.6a2.4 2.4 0 0 1 2.4-2.4h6.8a2.4 2.4 0 0 1 2.4 2.4v8.8a2.4 2.4 0 0 1-2.4 2.4H5.8a2.4 2.4 0 0 1-2.4-2.4z') + P('M15 10.4l5.6-3.2v9.6L15 13.6z'), 'A video clip', 'movie clip footage'],
      ['film', R(3.4, 4.6, 17.2, 14.8, 2.4) + P('M8.2 4.6v14.8M15.8 4.6v14.8M3.4 12h17.2'), 'Film strip, frames', 'strip frames reel'],
      ['camera', P('M3.4 9a2.4 2.4 0 0 1 2.4-2.4h1.8l1.4-2.2h5.8l1.4 2.2h1.8A2.4 2.4 0 0 1 20.6 9v8a2.4 2.4 0 0 1-2.4 2.4H5.8A2.4 2.4 0 0 1 3.4 17z') + C(12, 12.8, 3.6), 'Take a still', 'photo shoot snapshot'],
      ['aperture', C(12, 12, 8.6) + P('M13.98 8.4l4.94 8.55M9.9 8.4h9.88M8.06 11.6l4.94-8.55M9.9 15.6L4.96 7.05M13.98 15.6H4.1M15.82 12.4l-4.94 8.55'), 'Lens and camera detail', 'lens iris f-stop exif'],
    ],
  },

  {
    id: 'agent',
    name: 'Agent, capture & system',
    note: 'The glyphs that speak for Photonz itself. Sparkle is the agent, always, everywhere.',
    icons: [
      ['sparkle', SOLID('M12 2.8l2.05 5.9 5.9 2.05-5.9 2.05L12 18.7l-2.05-5.9L4.05 10.75l5.9-2.05z') + SOLID('M18.8 15.2l.85 2.35 2.35.85-2.35.85-.85 2.35-.85-2.35-2.35-.85 2.35-.85z'), 'The agent did this, or can', 'ai magic assistant generate'],
      ['chat', P('M20.6 14.4a2.6 2.6 0 0 1-2.6 2.6H8.6L4 20.6l.9-3.6H6a2.6 2.6 0 0 1-2.6-2.6V6.6A2.6 2.6 0 0 1 6 4h12a2.6 2.6 0 0 1 2.6 2.6z'), 'Talk to the agent', 'message conversation prompt ask'],
      ['capture', P('M3.6 8.6V5.8a2.2 2.2 0 0 1 2.2-2.2h2.8M15.4 3.6h2.8a2.2 2.2 0 0 1 2.2 2.2v2.8M20.4 15.4v2.8a2.2 2.2 0 0 1-2.2 2.2h-2.8M8.6 20.4H5.8a2.2 2.2 0 0 1-2.2-2.2v-2.8') + C(12, 12, 3.4), 'Capture part of the screen', 'screenshot grab snip region'],
      ['record', C(12, 12, 8.6) + `<circle cx='12' cy='12' r='4.4' fill='black' stroke='none'/>`, 'Record the screen', 'capture screen-recording'],
      ['window', R(3.4, 4.6, 17.2, 14.8, 2.6) + P('M3.4 9.2h17.2') + DOT(6.6, 6.9, 0.95) + DOT(9.4, 6.9, 0.95), 'Capture one window', 'app screen chrome'],
      ['display', R(3.4, 4.4, 17.2, 12.2, 2.4) + P('M8.6 20.4h6.8M12 16.6v3.8'), 'The whole screen', 'monitor screen desktop'],
      ['cloud', P('M7.4 19a4.8 4.8 0 0 1-.5-9.6 6 6 0 0 1 11.3 1.5A4.2 4.2 0 0 1 17.4 19z'), 'Synced to the cloud', 'sync online backup'],
      ['download', P('M12 3.6v11.8M7.6 11l4.4 4.4 4.4-4.4') + P('M4.4 20.4h15.2'), 'Download', 'save-to-disk fetch get'],
      ['upload', P('M12 20.4V8.6M7.6 13L12 8.6l4.4 4.4') + P('M4.4 3.6h15.2'), 'Upload', 'send push put'],
      ['branch', C(6.6, 6, 2.6) + C(6.6, 18, 2.6) + C(17.4, 6, 2.6) + P('M6.6 8.6v6.8M17.4 8.6v1.8a4 4 0 0 1-4 4H6.6'), 'A variant branched off this document', 'variant version fork alternative'],
      ['compare', R(3.4, 4.6, 17.2, 14.8, 2.6) + P('M12 3.4v17.2') + `<rect x='3.4' y='4.6' width='8.6' height='14.8' rx='2.6' fill='black' stroke='none' opacity='.35'/>`, 'Before and after', 'before-after split ab review'],
      ['restore', P('M3.6 12a8.4 8.4 0 1 0 2.8-6.3L3.4 8.2') + P('M3.4 3.4v4.8h4.8') + P('M12 8.4V12l2.8 1.7'), 'Go back to a saved state', 'revert version rollback'],
      ['keyboard', R(2.8, 6.2, 18.4, 11.6, 2.4) + P('M6.4 9.8h.01M9.6 9.8h.01M12.8 9.8h.01M16 9.8h.01M6.4 12.8h.01M9.6 12.8h.01M12.8 12.8h.01M16 12.8h.01M8.4 15.6h7.2'), 'Keyboard shortcut', 'shortcut keys hotkey'],
      ['command', P('M17.4 3.6a2.8 2.8 0 0 0-2.8 2.8v11.2a2.8 2.8 0 1 0 2.8-2.8H6.6a2.8 2.8 0 1 0 2.8 2.8V6.4a2.8 2.8 0 1 0-2.8 2.8h10.8a2.8 2.8 0 0 0 0-5.6z'), 'The command surface', 'cmd palette command-k'],
      ['warning', P('M10.3 4.7L2.9 17.5a2 2 0 0 0 1.7 3h14.8a2 2 0 0 0 1.7-3L13.7 4.7a2 2 0 0 0-3.4 0z') + P('M12 9.6v4.2') + DOT(12, 17.1, 1.05), 'Needs attention', 'caution alert attention'],
    ],
  },
];

/* Older names kept alive so no page breaks when a glyph is renamed.
   An alias is a second class name pointing at the same mask. Prefer the
   canonical name in new work; the iconography page lists these separately. */
export const ALIASES = {
  zoom: 'zoom-in',
  sidebar: 'sidebar-right',
  edit: 'pencil',
  fullscreen: 'maximize',
  'align-center': 'align-center-h',
  color: 'swatch',
  agent: 'sparkle',
  add: 'plus',
  close: 'x',
  delete: 'trash',
  split: 'blade',
  measure: 'ruler',
  visible: 'eye',
  hidden: 'eye-off',
};

/* Flat lookup, used by the generator and by anything that wants the names. */
export const ICONS = CATEGORIES.flatMap((c) =>
  c.icons.map(([name, svg, blurb, keywords]) => ({ name, svg, blurb, keywords: keywords || '', category: c.id }))
);

export const NAMES = ICONS.map((i) => i.name);
