/* Browser measurement sweep for the mock study.
   ux-audit-agent.md §0a requires real browser measurement, not class-grep: an
   HTTP 200 plus a passing grep has already shipped visibly broken pages here.

   HOW TO RUN: paste the body of sweep() into a chrome-devtools evaluate_script
   call on any page of the study (the dev server must be up on :8791). It loads
   every page into a hidden 1280x900 iframe, so one call covers all 64 pages
   without 64 navigations, and the scripts really execute.

   WHY offsetParent: walkthrough pages keep later steps display:none, so their
   canvases and docks legitimately measure 0x0. Measuring them anyway produced
   four false "zero canvas" reports. Only visible elements are judged.

   WHY the display assertion: a stray `*/` in photonz-ds.css silently deleted
   the rule that followed it. Every page still rendered plausibly, and the
   layout numbers still looked right, because a different rule happened to
   cover for it. Assert that a shared rule is ACTUALLY IN EFFECT, never just
   that the result looks reasonable. */
async function sweep(pages) {
  const bad = [];
  const stats = { pages: 0, segs: 0, dockManagers: 0 };
  for (const p of pages) {
    const f = document.createElement('iframe');
    f.style.cssText = 'position:fixed;left:-9999px;top:0;width:1280px;height:900px;border:0';
    document.body.appendChild(f);
    f.src = '/pages/' + p + '.html';
    await new Promise(r => { f.onload = r; setTimeout(r, 6000); });
    await new Promise(r => setTimeout(r, 300));
    const d = f.contentDocument, w = f.contentWindow;
    if (!d) { bad.push({ p, iss: ['no document'] }); f.remove(); continue; }
    stats.pages++;
    const vis = e => e.offsetParent !== null || w.getComputedStyle(e).position === 'fixed';
    const box = e => e.getBoundingClientRect();
    const iss = [];

    const ov = d.documentElement.scrollWidth - d.documentElement.clientWidth;
    if (ov > 0) iss.push('horizontal overflow ' + ov);

    stats.dockManagers += d.querySelectorAll('.dockmgr').length;
    [...d.querySelectorAll('.dockmgr')].filter(vis).forEach(m => {
      const b = box(m);
      if (b.width < 40 || b.height < 20) iss.push('dock manager collapsed');
    });

    /* Segs: judge only what the user can see. `.seg-plate` (the sliding
       selection plate) and `.seg-alt` (the collapse-to-menu trigger) are not
       chips; a collapsed seg keeps its chip buttons in the layout but hides
       them with `visibility`, so measuring those reported truncation nobody
       can see. And the dock default is now NATURAL-WIDTH columns (segmented
       .css, the scopeseg geometry), so unequal chip widths are by design —
       the failure worth flagging is a visible label that still clips. */
    [...d.querySelectorAll('.dgrp-b .seg,.pdock .seg')].filter(vis).forEach(s => {
      stats.segs++;
      if (w.getComputedStyle(s).display !== 'grid') iss.push('panel seg is not the shared grid');
      const chips = [...s.querySelectorAll(':scope > button')]
        .filter(b => w.getComputedStyle(b).visibility !== 'hidden');
      const t = chips.filter(b => b.scrollWidth > b.clientWidth + 1).map(b => b.textContent.trim());
      if (t.length) iss.push('truncated chip ' + t.join('|'));
    });

    [...d.querySelectorAll('.dgrp-h .cnt')].filter(vis).forEach(c => {
      const t = c.closest('.dgrp-h').querySelector('.ttl');
      if (t && box(c).left - box(t).right > 24) iss.push('count stranded at header right');
    });

    [...d.querySelectorAll('.canvas')].filter(vis).forEach(c => {
      const b = box(c);
      if (b.width < 2 || b.height < 2) iss.push('zero-size canvas');
    });

    [...d.querySelectorAll('.libtools')].filter(vis).forEach(l => {
      if (l.scrollWidth > l.clientWidth + 1) iss.push('clipped panel toolbar');
    });

    if (iss.length) bad.push({ p, iss: [...new Set(iss)] });
    f.remove();
  }
  return { stats, bad };
}
