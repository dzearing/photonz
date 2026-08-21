/* Photonz mock · the scalable dock: panel groups, pane manager, splitters, rail, collapse.
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
  /* ---- 1 · collapsible + scroll-constrained panel groups ----
     .dgrp > .dgrp-h (title, chevron, optional buttons) + .dgrp-b (own
     scroller). Clicking the header collapses the group to its header
     only; siblings are untouched because each body is bounded. */
  all('.dgrp > .dgrp-h').forEach(function (h) {
    var g = h.parentNode;
    if (!h.querySelector('.chev')) {
      var c = document.createElement('i');
      c.className = 'chev ic xs ic-chevron-down';
      h.insertBefore(c, h.firstChild);
    }
    if (!h.hasAttribute('tabindex')) h.setAttribute('tabindex', '0');
    h.setAttribute('role', 'button');
    var sync = function () {
      h.setAttribute('aria-expanded', g.classList.contains('collapsed') ? 'false' : 'true');
    };
    var toggle = function () { g.classList.toggle('collapsed'); sync(); };
    h.addEventListener('click', function (e) {
      if (e.target.closest('button, input, [data-target], [data-menu]')) return;
      toggle();
    });
    h.addEventListener('keydown', function (e) {
      if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggle(); }
    });
    sync();
  });

  /* ---- 1b · dock pane manager (VISUAL RULE 4) ----
     A chevron answers "is this group open"; it never answered "which groups
     do I even have". Each .pdock gets one sticky footer listing its own
     groups with a check, generated from the groups so a page cannot drift
     out of sync with its own dock. A hidden group is display:none; a
     collapsed one still shows its header. */
  all('.pdock').forEach(function (dock) {
    var groups = all('.dgrp', dock).filter(function (g) { return g.parentNode === dock; });
    if (groups.length < 2 || dock.querySelector('.dockmgr')) return;

    var bar = document.createElement('div');
    bar.className = 'dockmgr';
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'dockmgr-b';
    btn.setAttribute('aria-haspopup', 'menu');
    btn.setAttribute('aria-expanded', 'false');
    btn.innerHTML = '<i class="ic xs ic-sidebar"></i><span>Panels</span>' +
                    '<i class="ic xs ic-chevron-down sp"></i>';
    var menu = document.createElement('div');
    menu.className = 'popover menu dockmenu pop';
    menu.setAttribute('role', 'menu');

    groups.forEach(function (g) {
      var ttl = g.querySelector('.dgrp-h .ttl');
      var it = document.createElement('div');
      it.className = 'menuitem on';
      it.setAttribute('role', 'menuitemcheckbox');
      it.setAttribute('aria-checked', 'true');
      var lb = document.createElement('span');
      lb.textContent = ttl ? ttl.textContent.trim() : 'Panel';
      var ck = document.createElement('i');
      ck.className = 'ic xs ic-check ck';
      it.appendChild(lb); it.appendChild(ck);
      it.addEventListener('click', function (e) {
        e.stopPropagation();
        var show = g.classList.contains('hidden');
        g.classList.toggle('hidden', !show);
        it.classList.toggle('on', show);
        it.setAttribute('aria-checked', show ? 'true' : 'false');
      });
      menu.appendChild(it);
    });

    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var on = !menu.classList.contains('on');
      all('.popover.pop.on').forEach(function (p) { if (p !== menu) p.classList.remove('on'); });
      menu.classList.toggle('on', on);
      btn.setAttribute('aria-expanded', on ? 'true' : 'false');
    });
    // clicks inside the list must NOT dismiss it: you are checking several
    // panels at once, not picking one command.
    menu.addEventListener('click', function (e) { e.stopPropagation(); });

    bar.appendChild(menu); bar.appendChild(btn);
    dock.appendChild(bar);
  });

  /* ---- 1c · panel scope controls size to their own labels (VISUAL RULE 6) ----
     The CSS lays a scope control out as an auto-fit grid; only JS can know how
     wide its widest label actually is. Measured once, from text, so a splitter
     drag never needs to re-measure - the dock width decides how many of these
     columns fit, the labels decide how wide a column has to be. */
  all('.pdock .seg, .dgrp-b .seg').forEach(function (seg) {
    var btns = all('button', seg);
    if (!btns.length) return;
    var w = 0;
    btns.forEach(function (b) {
      // Measure with width:max-content, NOT scrollWidth. scrollWidth returns
      // max(content, clientWidth), so it reports the chip's CURRENT box once
      // that box is wider than its text - which fed the measurement back into
      // itself: chips got wider, --segmin grew to match, and a 4-chip scope
      // that fitted one row wrapped to two. max-content is the intrinsic text
      // width and cannot drift with layout.
      var prev = b.style.width;
      b.style.width = 'max-content';
      w = Math.max(w, Math.ceil(b.getBoundingClientRect().width));
      b.style.width = prev;
    });
    if (!w) return;
    // +2 for sub-pixel rounding; the clamp stops one long label from forcing a
    // single column, and short ones from collapsing to nothing.
    seg.style.setProperty('--segmin', Math.min(132, Math.max(52, w + 2)) + 'px');
  });

  /* ---- 2 · resizable panes ----
     .splitter.v resizes the dock to its right (drag left to grow).
     .splitter.h resizes the .dgrp-b above it. `data-resize="prev|next"`
     overrides which sibling is the target; data-min / data-max bound it.
     The size lives as an inline style, so it persists for the session. */
  all('.splitter').forEach(function (sp) {
    var vertical = sp.classList.contains('v');
    var dir = sp.getAttribute('data-resize') || (vertical ? 'next' : 'prev');
    var target = dir === 'next' ? sp.nextElementSibling : sp.previousElementSibling;
    if (!target) return;
    var sizeEl = vertical ? target : (target.querySelector('.dgrp-b') || target);
    var min = parseInt(sp.getAttribute('data-min'), 10) || (vertical ? 180 : 80);
    var max = parseInt(sp.getAttribute('data-max'), 10) || (vertical ? 460 : 520);
    if (!sp.hasAttribute('tabindex')) sp.setAttribute('tabindex', '0');
    sp.setAttribute('role', 'separator');
    sp.setAttribute('aria-orientation', vertical ? 'vertical' : 'horizontal');
    sp.setAttribute('aria-label', vertical ? 'Resize panel dock' : 'Resize panel group');

    function measure() {
      var r = sizeEl.getBoundingClientRect();
      return vertical ? r.width : r.height;
    }
    function apply(px) {
      px = Math.max(min, Math.min(max, Math.round(px)));
      if (vertical) sizeEl.style.width = px + 'px';
      else { sizeEl.style.maxHeight = px + 'px'; sizeEl.style.height = px + 'px'; }
    }
    var start = 0, base = 0;
    sp.addEventListener('pointerdown', function (e) {
      e.preventDefault();
      start = vertical ? e.clientX : e.clientY;
      base = measure();
      sp.classList.add('dragging');
      if (sp.setPointerCapture) sp.setPointerCapture(e.pointerId);
    });
    sp.addEventListener('pointermove', function (e) {
      if (!sp.classList.contains('dragging')) return;
      var d = (vertical ? e.clientX : e.clientY) - start;
      // a dock sitting to the RIGHT grows as the pointer moves LEFT
      apply(base + (vertical && dir === 'next' ? -d : d));
    });
    ['pointerup', 'pointercancel'].forEach(function (t) {
      sp.addEventListener(t, function (e) {
        sp.classList.remove('dragging');
        if (sp.releasePointerCapture && sp.hasPointerCapture && sp.hasPointerCapture(e.pointerId)) {
          sp.releasePointerCapture(e.pointerId);
        }
      });
    });
    sp.addEventListener('keydown', function (e) {
      var step = e.shiftKey ? 32 : 8, cur = measure();
      if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') { e.preventDefault(); apply(cur + (vertical ? step : -step)); }
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') { e.preventDefault(); apply(cur + (vertical ? -step : step)); }
    });
  });

  /* ---- 3 · dock collapse / rail / narrow overlay ----
     One state attribute on .edit.lean drives all three:
       data-dock="open"    dock inline (wide) · hidden (narrow)
       data-dock="closed"  rail only
       data-dock="overlay" dock floats over the canvas (narrow)
     Any [data-dock-toggle] button flips it; the value may be a selector
     for the shell, otherwise the nearest .edit.lean in the same window. */
  function shellFor(btn) {
    var sel = btn.getAttribute('data-dock-toggle');
    if (sel) { var el = document.querySelector(sel); if (el) return el; }
    return winOf(btn).querySelector('.edit.lean');
  }
  function setDock(shell, state) {
    shell.setAttribute('data-dock', state);
    var narrow = isNarrow(shell);
    var showing = narrow ? state === 'overlay' : state !== 'closed';
    all('[data-dock-toggle]').forEach(function (b) {
      if (shellFor(b) !== shell) return;
      // reuse the shared toggle-on state: .tool.on when the dock is showing.
      b.classList.toggle('on', showing);
      b.setAttribute('aria-pressed', showing ? 'true' : 'false');
    });
  }
  /* Panel-dock affordance. Two patterns coexist during the migration:
     - Pages WITH a command strip (.toolbar above the shell): a square toggle in
       the strip's corner (.dock-corner).
     - Pages WITHOUT one (the strip was removed): the expanded panel carries an
       "×" to collapse it (.dock-close); collapsed, the rail's tabs expand it.
     Both are [data-dock-toggle], wired by the listener below. Runs first so the
     new control is picked up there. */
  all('.edit.lean').forEach(function (shell) {
    var bar = shell.previousElementSibling;
    var hasBar = bar && bar.classList && bar.classList.contains('toolbar');
    var sel = shell.id ? '#' + shell.id : '';
    if (hasBar) {
      if (bar.querySelector('.dock-corner')) return; // idempotent
      var corner = document.createElement('button');
      corner.type = 'button';
      corner.className = 'tool dock-corner';
      corner.setAttribute('data-dock-toggle', sel);
      corner.setAttribute('title', 'Show or hide the panel dock (⌥⌘L)');
      corner.setAttribute('aria-label', 'Show or hide the panel dock');
      // "on" = panel actually showing (narrow: only 'overlay'); mirror setDock.
      var st = shell.getAttribute('data-dock') || 'open';
      var open = isNarrow(shell) ? st === 'overlay' : st !== 'closed';
      corner.classList.toggle('on', open);
      corner.setAttribute('aria-pressed', open ? 'true' : 'false');
      corner.innerHTML = '<i class="ic sm ic-sidebar"></i>';
      bar.appendChild(corner);
    } else {
      var pdock = shell.querySelector('.pdock');
      if (!pdock || pdock.querySelector('.dock-head')) return; // idempotent
      var head = document.createElement('div');
      head.className = 'dock-head';
      var x = document.createElement('button');
      x.type = 'button';
      x.className = 'dock-close';
      x.setAttribute('data-dock-toggle', sel);
      x.setAttribute('title', 'Collapse the panel dock (⌥⌘L)');
      x.setAttribute('aria-label', 'Collapse the panel dock');
      x.innerHTML = '<i class="ic sm ic-x"></i>';
      head.appendChild(x);
      // wrap the panes in a scrolling body between the header and any footer
      // (.dockmgr), so the scroll area starts below the header, stops above the
      // footer, and reserves its gutter on the body (not the whole dock).
      var foot = pdock.querySelector(':scope > .dockmgr');
      var body = document.createElement('div');
      body.className = 'dock-body';
      [].slice.call(pdock.children).forEach(function (k) { if (k !== foot) body.appendChild(k); });
      pdock.insertBefore(body, foot);   // body before the footer (or last if none)
      pdock.insertBefore(head, body);   // header on its own row, first
    }
    // relocate: drop any canvas dock toggle this replaces
    var old = shell.querySelector('.cnv-act [data-dock-toggle]');
    if (old) {
      var cluster = old.closest('.cnv-act');
      old.parentNode.removeChild(old);
      if (cluster && !cluster.querySelector('button')) cluster.parentNode.removeChild(cluster);
    }
  });
  /* Bottom-dock affordance, mirroring the panel dock above. Any .timeline that
     has a local bar gets an "×" to collapse it and a one-row rail to bring it
     back — injected rather than authored, so all fourteen timeline pages get the
     same control without editing fourteen files. */
  /* `.win > .timeline` is the DOCK timeline specifically. Plain `.timeline` also
     matches the static previews pages draw inside on-ramps and panels (the blank
     project illustration on video.html), and putting a collapse control on an
     illustration is worse than having none. A bottom dock is always a direct
     child of the window. */
  all('.win > .timeline').forEach(function (tl) {
    if (tl.querySelector(':scope > .tlrail')) return;           // idempotent
    if (!tl.getAttribute('data-tl')) tl.setAttribute('data-tl', 'open');

    var x = document.createElement('button');
    x.type = 'button';
    x.className = 'tl-close';
    x.setAttribute('data-tl-toggle', '');
    x.setAttribute('title', 'Collapse the timeline');
    x.setAttribute('aria-label', 'Collapse the timeline');
    x.innerHTML = '<i class="ic sm ic-x"></i>';
    /* Most timeline docks have a local bar and the × belongs at the end of it.
       The ones that don't (app-shell, the walkthrough pages) still need the
       affordance, so it floats at the dock's top-right instead of being skipped
       — otherwise "the bottom dock collapses" would be true on five pages out of
       fourteen, which is the same inconsistency this set out to fix. */
    var bar = tl.querySelector(':scope > .tlbar');
    if (bar) { bar.appendChild(x); }
    else { x.classList.add('afloat'); tl.appendChild(x); }

    var rail = document.createElement('button');
    rail.type = 'button';
    rail.className = 'tlrail';
    rail.setAttribute('data-tl-toggle', '');
    rail.setAttribute('title', 'Show the timeline');
    rail.innerHTML = '<i class="ic sm ic-chevron-up"></i>' +
      '<span class="nm">Timeline</span>' +
      '<span class="sum"></span>' +
      '<span class="sp">click to expand</span>';
    tl.appendChild(rail);
    syncRail(tl);
  });
  /* The summary is whatever the page last wrote to data-tl-summary; observing
     it keeps the collapsed row honest without the page having to know a rail
     exists. Falls back to the document, so the row is never blank. */
  function syncRail(tl) {
    var rail = tl.querySelector(':scope > .tlrail');
    if (!rail) return;
    rail.querySelector('.sum').textContent = tl.getAttribute('data-tl-summary') || '';
  }
  all('.timeline[data-tl]').forEach(function (tl) {
    if (!window.MutationObserver) return;
    new MutationObserver(function () { syncRail(tl); })
      .observe(tl, { attributes: true, attributeFilter: ['data-tl-summary'] });
  });
  /* Several pages pin their dock with an INLINE height (`style="min-height:170px"`),
     and an inline declaration outranks any stylesheet rule — so a collapsed dock
     stayed 170px tall while its contents were correctly hidden: a collapse that
     reclaimed nothing. Rather than escalate to !important, stash the inline
     values on the way down and put them back on the way up, so the page keeps
     ownership of its own expanded size. */
  var TL_PINNED = ['minHeight', 'height', 'maxHeight'];
  all('[data-tl-toggle]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var tl = btn.closest('.timeline');
      if (!tl) return;
      var closing = tl.getAttribute('data-tl') !== 'closed';
      if (closing) {
        var saved = {};
        TL_PINNED.forEach(function (k) { saved[k] = tl.style[k] || ''; tl.style[k] = ''; });
        tl.__tlPinned = saved;
      } else if (tl.__tlPinned) {
        TL_PINNED.forEach(function (k) { tl.style[k] = tl.__tlPinned[k]; });
        tl.__tlPinned = null;
      }
      tl.setAttribute('data-tl', closing ? 'closed' : 'open');
    });
  });

  all('[data-dock-toggle]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var shell = shellFor(btn);
      if (!shell) return;
      var cur = shell.getAttribute('data-dock') || 'open';
      if (isNarrow(shell)) setDock(shell, cur === 'overlay' ? 'open' : 'overlay');
      else setDock(shell, cur === 'closed' ? 'open' : 'closed');
    });
  });
  // A rail tab restores the dock AND reveals the group it names.
  all('.drailtab[data-group]').forEach(function (tab) {
    tab.addEventListener('click', function () {
      var shell = tab.closest('.edit.lean');
      var grp = document.querySelector(tab.getAttribute('data-group'));
      if (shell) setDock(shell, isNarrow(tab) ? 'overlay' : 'open');
      if (grp) {
        // a rail tab names a panel, so it must bring it back whether the
        // panel was collapsed OR hidden from the Panels menu
        grp.classList.remove('collapsed');
        grp.classList.remove('hidden');
        var h = grp.querySelector('.dgrp-h');
        if (h) h.setAttribute('aria-expanded', 'true');
        // Reveal the group by scrolling ONLY the dock, never the page. Native
        // scrollIntoView bubbles to every scroll ancestor (incl. the page), so
        // expanding from a rail tab made the whole page jiggle. Scope it to the
        // dock and defer a frame so it doesn't fight the expand transition.
        var dock = grp.closest('.pdock');
        if (dock) requestAnimationFrame(function () {
          var g = grp.getBoundingClientRect(), d = dock.getBoundingClientRect();
          if (g.top < d.top) dock.scrollTop += g.top - d.top - 8;
          else if (g.bottom > d.bottom) dock.scrollTop += g.bottom - d.bottom + 8;
        });
      }
    });
  });
})();
