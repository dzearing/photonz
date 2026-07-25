/* Photonz mock · shared page behaviors (loaded by every page in the iframe shell).
   Pages are static; this only wires: cross-page nav, walkthrough steppers, subtabs,
   and theme sync from the shell. Guards everything so a page without those elements
   is a no-op. */
(function () {
  // Theme: the shell stamps data-theme; also honor prefers-color-scheme by default.
  window.addEventListener('message', function (e) {
    var d = e.data || {};
    if (d.photonzTheme) document.documentElement.setAttribute('data-theme', d.photonzTheme);
  });

  // Cross-page nav: any [data-target] asks the shell to load that page.
  document.querySelectorAll('[data-target]').forEach(function (el) {
    el.style.cursor = 'pointer';
    el.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      var id = el.getAttribute('data-target');
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ photonzNav: id }, '*');
      }
    });
  });

  // Inspector groups: any .section that has a .sec-h header becomes a collapsible
  // disclosure (chevron + click-to-collapse) so panels read as grouped, not a wall.
  document.querySelectorAll('.section > .sec-h').forEach(function (h) {
    var sec = h.parentNode;
    sec.classList.add('grp');
    if (!h.querySelector('.chev')) {
      var c = document.createElement('span');
      c.className = 'chev ic ic-chevron-down';
      h.insertBefore(c, h.firstChild);
    }
    h.addEventListener('click', function (e) {
      if (e.target.closest('[data-target]')) return; // let cross-links do their thing
      sec.classList.toggle('closed');
    });
  });

  // Subtabs (e.g. agent A/B/C): .subtab[data-alt] toggles matching .alt.
  var subtabs = [].slice.call(document.querySelectorAll('.subtab'));
  subtabs.forEach(function (t) {
    t.addEventListener('click', function () {
      subtabs.forEach(function (x) { x.classList.toggle('on', x === t); });
      document.querySelectorAll('.alt').forEach(function (a) {
        a.classList.toggle('on', a.id === t.getAttribute('data-alt'));
      });
    });
  });

  // Walkthrough stepper: .wstep sequence with .wprev/.wnext/.wdots i/.wlabel.
  // Step titles are read from each step's `.wcap .tx b` (or a data-title override).
  var wsteps = [].slice.call(document.querySelectorAll('.wstep'));
  if (wsteps.length) {
    var wdots = [].slice.call(document.querySelectorAll('.wdots i'));
    var wprev = document.querySelector('.wprev');
    var wnext = document.querySelector('.wnext');
    var wlabel = document.querySelector('.wlabel');
    var titles = wsteps.map(function (s) {
      if (s.getAttribute('data-title')) return s.getAttribute('data-title');
      var b = s.querySelector('.wcap .tx b');
      return b ? b.textContent.replace(/\.$/, '') : '';
    });
    var i = 0;
    var show = function (n) {
      i = Math.max(0, Math.min(wsteps.length - 1, n));
      wsteps.forEach(function (s, k) { s.classList.toggle('on', k === i); });
      wdots.forEach(function (d, k) { d.classList.toggle('on', k === i); });
      if (wlabel) wlabel.innerHTML = 'Step <b>' + (i + 1) + '</b> / ' + wsteps.length + ' · ' + titles[i];
      if (wprev) wprev.disabled = i === 0;
      if (wnext) wnext.disabled = i === wsteps.length - 1;
    };
    if (wprev) wprev.addEventListener('click', function () { show(i - 1); });
    if (wnext) wnext.addEventListener('click', function () { show(i + 1); });
    wdots.forEach(function (d, k) { d.addEventListener('click', function () { show(k); }); });
    show(0);
  }

  /* ============================================================
     THE SCALABLE DOCK SYSTEM (PRODUCT-MODEL.md §4b)
     Progressive enhancement for the shell vocabulary defined in
     photonz-ds.css: collapse, resize, scroll, overflow, overlay.
     Everything below is guarded, so a page that uses none of it is a
     no-op. Nothing here owns state a page cannot also set in markup.
     ============================================================ */

  // Keep in sync with the @container breakpoints in photonz-ds.css.
  var NARROW = 880;

  function winOf(el) { return el.closest('.win') || document.body; }
  function isNarrow(el) { return winOf(el).clientWidth <= NARROW; }
  function all(sel, root) { return [].slice.call((root || document).querySelectorAll(sel)); }

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

  /* ---- 4 · slide-down overlays (the history front door) ----
     [data-sheet="#id"] toggles that .sheet; [data-sheet-close] and Escape
     close it. Overlays slide over the canvas, so they never cost width. */
  function setSheet(sheet, on) {
    sheet.classList.toggle('on', on);
    sheet.setAttribute('aria-hidden', on ? 'false' : 'true');
    all('[data-sheet]').forEach(function (b) {
      if (document.querySelector(b.getAttribute('data-sheet')) !== sheet) return;
      b.classList.toggle('on', on);
      b.setAttribute('aria-expanded', on ? 'true' : 'false');
    });
  }
  all('[data-sheet]').forEach(function (btn) {
    var sheet = document.querySelector(btn.getAttribute('data-sheet'));
    if (!sheet) return;
    setSheet(sheet, sheet.classList.contains('on'));
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      setSheet(sheet, !sheet.classList.contains('on'));
    });
  });
  all('[data-sheet-close]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var sheet = btn.closest('.sheet');
      if (sheet) setSheet(sheet, false);
    });
  });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    all('.sheet.on').forEach(function (s) { setSheet(s, false); });
    all('.popover.pop.on').forEach(function (p) { p.classList.remove('on'); });
  });
  // The history pane is chromeless: it has no close button, so an outside
  // click dismisses it the way a menu-bar popover does. Its trigger stops
  // propagation, so toggling from the menu-bar icon still works.
  document.addEventListener('click', function (e) {
    all('.sheet.down.hist.on').forEach(function (s) {
      if (!s.contains(e.target)) setSheet(s, false);
    });
  });

  /* ---- 5 · toggled popovers (tool-bar overflow, group menus) ----
     [data-menu="#id"] toggles a .popover.pop; outside-click dismisses. */
  all('[data-menu]').forEach(function (btn) {
    var m = document.querySelector(btn.getAttribute('data-menu'));
    if (!m) return;
    m.classList.add('pop');
    btn.setAttribute('aria-haspopup', 'menu');
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var on = !m.classList.contains('on');
      all('.popover.pop.on').forEach(function (p) { if (p !== m) p.classList.remove('on'); });
      m.classList.toggle('on', on);
      btn.setAttribute('aria-expanded', on ? 'true' : 'false');
    });
    // A MENU closes when you pick an item. A popover you OPERATE - the color
    // picker - must not vanish on the first click inside it, or dragging the
    // hue track would dismiss the thing you are dragging. `.cpick` and any
    // [data-sticky] popover stay open until you click outside or hit its
    // close button.
    var sticky = m.classList.contains('cpick') || m.hasAttribute('data-sticky');
    m.addEventListener('click', function (e) {
      e.stopPropagation();
      if (!sticky || e.target.closest('[data-cp-close]')) m.classList.remove('on');
    });
  });
  document.addEventListener('click', function () {
    all('.popover.pop.on').forEach(function (p) { p.classList.remove('on'); });
  });

  /* ---- 6 · exclusive selection inside a container ----
     [data-radio=".filmcard"] makes those children mutually exclusive.
     data-radio-class picks the state class (default "on"). Used by the
     tool strip, the filmstrip, and rail tabs. */
  all('[data-radio]').forEach(function (box) {
    var sel = box.getAttribute('data-radio') || '.tool';
    var cls = box.getAttribute('data-radio-class') || 'on';
    var items = all(sel, box);
    items.forEach(function (it) {
      it.addEventListener('click', function () {
        items.forEach(function (x) { x.classList.toggle(cls, x === it); });
      });
    });
  });

  /* ---- 7 · zoom slider + scrubber readouts ----
     VISUAL RULE 5: zoom drives the canvas grid density, not just a readout.
     The slider owns the canvases in ITS shell only (a page can host several
     windows / walkthrough steps), so scope up to the nearest canvas column
     before collecting them. `.canvas.mini` specimens never zoom. */
  all('.zslider').forEach(function (s) {
    var out = (s.closest('.zoomctl') || document).querySelector('.zval');
    var scope = s.closest('.cnv, .edit, .wt-step, .win, .shell');
    var canvases = scope ? all('.canvas:not(.mini)', scope)
      : (all('.canvas:not(.mini)').length === 1 ? all('.canvas:not(.mini)') : []);
    var sync = function () {
      var z = (parseFloat(s.value) || 100) / 100;
      if (out) out.textContent = Math.round(z * 100) + '%';
      canvases.forEach(function (c) { c.style.setProperty('--zoom', z); });
    };
    s.addEventListener('input', sync);
    sync();
  });
  function tcode(sec) {
    sec = Math.max(0, sec);
    var m = Math.floor(sec / 60), s = Math.floor(sec % 60);
    return m + ':' + (s < 10 ? '0' : '') + s;
  }
  all('.scrub').forEach(function (sc) {
    var fill = sc.querySelector('.fill');
    var knob = sc.querySelector('.knob');
    var cur = (sc.parentNode || document).querySelector('.tc.cur');
    var dur = parseFloat(sc.getAttribute('data-duration') || '0');
    function seek(e) {
      var r = sc.getBoundingClientRect();
      var p = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
      if (fill) fill.style.width = (p * 100) + '%';
      if (knob) knob.style.left = (p * 100) + '%';
      if (cur && dur) cur.textContent = tcode(p * dur);
    }
    sc.addEventListener('pointerdown', function (e) {
      e.preventDefault();
      if (sc.setPointerCapture) sc.setPointerCapture(e.pointerId);
      sc.dataset.seeking = '1';
      seek(e);
    });
    sc.addEventListener('pointermove', function (e) { if (sc.dataset.seeking) seek(e); });
    ['pointerup', 'pointercancel'].forEach(function (t) {
      sc.addEventListener(t, function () { delete sc.dataset.seeking; });
    });
  });

  /* ============================================================
     8 · OPERATED WALKTHROUGHS (PRODUCT-MODEL.md §4d)

     ONE app screen, rendered once, that is DRIVEN. Nothing here
     re-renders the shell: a step declares STATE with data attributes,
     ds.js resets the stage to its authored baseline and replays steps
     0..n, then anchors a click cue over the REAL target element.

       <div class="wt">
         <div class="wt-stage"> …one .win.tall.cq shell… </div>
         <ol class="wt-steps">
           <li class="wt-step" data-title="…" data-cue="#tBlade"
               data-cue-label="Click the Blade tool" data-cue-place="top"
               data-tool="#tBlade" data-open="#gLibrary" data-scope="media"
               data-select="#lrClipA" data-show="#cvFrame" …>
             <div class="wt-cap vid">
               <span class="wt-n">3</span>
               <p class="wt-do">the <b>Blade</b> tool</p>
               <p class="wt-where">the floating tool bar</p>
               <p class="wt-res">Blade is the active tool.</p>
             </div>
           </li>
         </ol>
         <div class="wbar"> .wprev · .wdots · .wlabel · .wt-reset · .wnext </div>
       </div>

     Step directives (all optional, all resolved INSIDE the stage):
       data-tool="#id"           exclusive .on inside that tool's .tstrip
       data-open="#a,#b"         un-collapse those .dgrp groups
       data-collapse="#a,#b"     collapse those .dgrp groups
       data-dock="open|closed|overlay"   the .edit.lean dock state
       data-scope="media"        Library scope: .on the [data-scope] button,
                                 reveal [data-scope-body="media"], set
                                 [data-scope-label] text
       data-activate="#id"       exclusive .on among that element's
                                 like-classed siblings (workspace switcher)
       data-select="#id"         exclusive selection across .lrow/.libtile/
                                 .filmcard/.clip. Class comes from the step's
                                 data-select-class, else the target's
                                 data-sel-class, else "sel"
       data-show / data-hide     drop or add .wt-off (reveal canvas content,
                                 selection rings, empty states, badges)
       data-sheet-open/-shut     the .sheet.down overlay (history)
       data-pop="#id"            open a .popover.pop (so a cue can sit on a
                                 real menu item)
       data-time="on|off"        the document has time: transport + timeline
       data-set="#id=text|#id2=text"     set a readout's text
       data-css="#id=width:26%"  inline geometry (a trimmed clip, a bar)
       data-class="#id=blk|#id2=-caret"  add a variant class ("-x" removes it)
       data-cue / data-cue-label / data-cue-place    the click cue

     Rule of thumb for authors: anchor the cue on a control that still
     EXISTS after this step's state applies. A step that cannot be
     expressed as a real click on a real surface is not a usage step.
     ============================================================ */
  all('.wt').forEach(function (wt) {
    var stage = wt.querySelector('.wt-stage') || wt.querySelector('.win');
    var steps = all('.wt-step', wt);
    if (!stage || !steps.length) return;

    function list(v) {
      if (!v) return [];
      var s = v.split(',').map(function (x) { return x.trim(); }).filter(Boolean).join(',');
      return s ? all(s, stage) : [];
    }
    function pairs(v, fn) {
      (v || '').split('|').forEach(function (p) {
        var k = p.indexOf('=');
        if (k < 0) return;
        var el = stage.querySelector(p.slice(0, k).trim());
        if (el) fn(el, p.slice(k + 1));
      });
    }

    /* ---- baseline snapshot, so every step replay is deterministic ----
       class + the dock attribute cover every state directive; text is
       snapshotted only for the elements some step actually rewrites. */
    var snapClass = all('*', stage).map(function (el) {
      return [el, el.getAttribute('class')];
    });
    var snapDock = all('.edit.lean', stage).map(function (el) {
      return [el, el.getAttribute('data-dock') || 'open'];
    });
    var snapText = [], snapStyle = [];
    function remember(store, el, val) {
      for (var k = 0; k < store.length; k++) if (store[k][0] === el) return;
      store.push([el, val]);
    }
    steps.forEach(function (s) {
      pairs(s.getAttribute('data-set'), function (el) { remember(snapText, el, el.textContent); });
      pairs(s.getAttribute('data-css'), function (el) { remember(snapStyle, el, el.getAttribute('style')); });
    });
    function resetStage() {
      snapClass.forEach(function (r) {
        if (r[1] === null) r[0].removeAttribute('class'); else r[0].setAttribute('class', r[1]);
      });
      snapDock.forEach(function (r) { r[0].setAttribute('data-dock', r[1]); });
      snapText.forEach(function (r) { r[0].textContent = r[1]; });
      snapStyle.forEach(function (r) {
        if (r[1] === null) r[0].removeAttribute('style'); else r[0].setAttribute('style', r[1]);
      });
    }

    function applyStep(s) {
      var v;

      v = s.getAttribute('data-tool');
      if (v) {
        var t = stage.querySelector(v);
        if (t) {
          all('.tool', t.closest('.tstrip') || t.parentNode || stage).forEach(function (x) {
            x.classList.toggle('on', x === t);
          });
        }
      }

      list(s.getAttribute('data-open')).forEach(function (g) {
        g.classList.remove('collapsed');
        var h = g.querySelector('.dgrp-h');
        if (h) h.setAttribute('aria-expanded', 'true');
      });
      list(s.getAttribute('data-collapse')).forEach(function (g) {
        g.classList.add('collapsed');
        var h = g.querySelector('.dgrp-h');
        if (h) h.setAttribute('aria-expanded', 'false');
      });

      v = s.getAttribute('data-dock');
      if (v) all('.edit.lean', stage).forEach(function (sh) { sh.setAttribute('data-dock', v); });

      v = s.getAttribute('data-scope');
      if (v) {
        var name = v;
        all('[data-scope]', stage).forEach(function (b) {
          var on = b.getAttribute('data-scope') === v;
          b.classList.toggle('on', on);
          if (on) name = b.getAttribute('data-scope-name') || b.textContent.trim();
        });
        all('[data-scope-body]', stage).forEach(function (p) {
          p.classList.toggle('wt-off', p.getAttribute('data-scope-body') !== v);
        });
        all('[data-scope-label]', stage).forEach(function (l) { l.textContent = name; });
      }

      // exclusive .on among an element's like-classed siblings (workspace
      // switcher segments, seg buttons, anything that is one-of-N)
      list(s.getAttribute('data-activate')).forEach(function (t) {
        if (!t.parentNode) return;
        // siblings are "like-classed" by the target's first REAL class, never
        // by `on` itself (the currently-selected segment carries it, which
        // would have matched only itself). A bare <button> in a .seg has no
        // class at all, so fall back to the tag: that is what one-of-N means.
        var cls = (t.getAttribute('class') || '').split(/\s+/).filter(function (c) {
          return c && c !== 'on';
        })[0];
        [].slice.call(t.parentNode.children).forEach(function (x) {
          var like = cls ? x.classList.contains(cls) : x.tagName === t.tagName;
          if (like) x.classList.toggle('on', x === t);
        });
      });

      v = s.getAttribute('data-select');
      if (v) {
        all('.lrow,.libtile,.filmcard,.clip', stage).forEach(function (r) {
          r.classList.remove('sel', 'selc');
        });
        var pick = stage.querySelector(v);
        if (pick) {
          pick.classList.add(s.getAttribute('data-select-class') ||
            pick.getAttribute('data-sel-class') || 'sel');
        }
      }

      list(s.getAttribute('data-show')).forEach(function (e) { e.classList.remove('wt-off'); });
      list(s.getAttribute('data-hide')).forEach(function (e) { e.classList.add('wt-off'); });

      // a variant class the step turns on (a dip-to-black marker, a frozen
      // clip). The baseline class snapshot takes it off again on replay, so
      // this stays declarative like everything else.
      pairs(s.getAttribute('data-class'), function (el, cls) {
        cls.split(/\s+/).forEach(function (c) {
          if (!c) return;
          if (c.charAt(0) === '-') el.classList.remove(c.slice(1));  // "-caret" takes it off again
          else el.classList.add(c);
        });
      });

      list(s.getAttribute('data-sheet-open')).forEach(function (sh) {
        sh.classList.add('on'); sh.setAttribute('aria-hidden', 'false');
      });
      list(s.getAttribute('data-sheet-shut')).forEach(function (sh) {
        sh.classList.remove('on'); sh.setAttribute('aria-hidden', 'true');
      });

      /* A menu is transient, so it closes itself. Steps replay cumulatively
         (0..n), which used to leave a popover opened in step 2 still hanging
         open in step 8. Every step shuts every .popover.pop in the stage and
         then opens only the one it declares; a menu that should stay open
         across two steps declares data-pop on both. */
      all('.popover.pop', stage).forEach(function (p) { p.classList.remove('on'); });
      list(s.getAttribute('data-pop')).forEach(function (p) { p.classList.add('on'); });

      v = s.getAttribute('data-time');
      if (v) {
        all('.transport,.timeline', stage).forEach(function (e) {
          e.classList.toggle('wt-off', v !== 'on');
        });
      }

      pairs(s.getAttribute('data-set'), function (el, text) { el.textContent = text; });
      pairs(s.getAttribute('data-css'), function (el, css) { el.style.cssText += ';' + css; });
    }

    /* ---- the click cue ---- */
    var cue = document.createElement('div');
    cue.className = 'wt-cue';
    cue.innerHTML = '<span class="pulse"></span><span class="ring"></span><span class="lb"></span>';
    wt.appendChild(cue);
    var cueRing = cue.querySelector('.ring');
    var cuePulse = cue.querySelector('.pulse');
    var cueLb = cue.querySelector('.lb');

    // bring the target inside view of whatever group scroller holds it,
    // without ever scrolling the page itself
    function reveal(el) {
      var p = el.parentNode;
      while (p && p !== stage && p.getBoundingClientRect) {
        if (p.scrollHeight > p.clientHeight + 2 || p.scrollWidth > p.clientWidth + 2) {
          var pr = p.getBoundingClientRect(), er = el.getBoundingClientRect();
          if (er.top < pr.top) p.scrollTop -= (pr.top - er.top) + 8;
          else if (er.bottom > pr.bottom) p.scrollTop += (er.bottom - pr.bottom) + 8;
          if (er.left < pr.left) p.scrollLeft -= (pr.left - er.left) + 8;
          else if (er.right > pr.right) p.scrollLeft += (er.right - pr.right) + 8;
        }
        p = p.parentNode;
      }
    }

    // Narrow windows rail the dock, so a cue that points INTO the dock would
    // have nothing to point at. Summon the dock as an overlay for exactly
    // those steps, and put it away again for canvas steps. A step that sets
    // data-dock itself always wins.
    function autoDock(s, el) {
      if (!s || s.getAttribute('data-dock')) return;
      all('.edit.lean', stage).forEach(function (sh) {
        if (!isNarrow(sh)) return;
        var dock = sh.querySelector('.pdock');
        var wants = !!(el && dock && el.closest('.pdock') === dock);
        sh.setAttribute('data-dock', wants ? 'overlay' : 'open');
      });
    }

    function placeCue(s) {
      var sel = s && s.getAttribute('data-cue');
      var el = sel ? stage.querySelector(sel) : null;
      autoDock(s, el);
      if (!el || !el.getClientRects().length) { cue.classList.remove('on'); return; }
      reveal(el);
      var r = el.getBoundingClientRect(), w = wt.getBoundingClientRect();
      if (!r.width || !r.height) { cue.classList.remove('on'); return; }
      var pad = 4;
      cue.style.left = (r.left - w.left - pad) + 'px';
      cue.style.top = (r.top - w.top - pad) + 'px';
      cue.style.width = (r.width + pad * 2) + 'px';
      cue.style.height = (r.height + pad * 2) + 'px';
      var br = getComputedStyle(el).borderTopLeftRadius || '0px';
      var rad = (br === '0px' || br.indexOf(' ') > -1) ? '10px' : 'calc(' + br + ' + ' + pad + 'px)';
      cueRing.style.borderRadius = rad;
      cuePulse.style.borderRadius = rad;

      var label = s.getAttribute('data-cue-label') || '';
      cueLb.textContent = label;
      cueLb.style.display = label ? '' : 'none';
      var place = s.getAttribute('data-cue-place');
      if (!place) place = (r.top - w.top) > 96 ? 'top' : 'bottom';
      cue.className = 'wt-cue on p-' + place;

      // keep the label chip inside the walkthrough bounds
      cue.style.setProperty('--lbx', '0px');
      if (label && (place === 'top' || place === 'bottom')) {
        var lr = cueLb.getBoundingClientRect(), dx = 0;
        if (lr.left < w.left + 8) dx = (w.left + 8) - lr.left;
        else if (lr.right > w.right - 8) dx = (w.right - 8) - lr.right;
        if (dx) cue.style.setProperty('--lbx', Math.round(dx) + 'px');
      }
    }

    /* ---- nav ---- */
    var bar = wt.querySelector('.wbar');
    var prev = bar && bar.querySelector('.wprev');
    var next = bar && bar.querySelector('.wnext');
    var label = bar && bar.querySelector('.wlabel');
    var resetBtn = bar && bar.querySelector('.wt-reset');
    var dotbox = bar && bar.querySelector('.wdots');
    var dots = [];
    if (dotbox) {
      if (!dotbox.children.length) {
        steps.forEach(function () { dotbox.appendChild(document.createElement('i')); });
      }
      dots = all('i', dotbox);
      dots.forEach(function (d, k) {
        d.setAttribute('tabindex', '0');
        d.setAttribute('role', 'button');
        d.setAttribute('aria-label', 'Step ' + (k + 1));
        d.addEventListener('click', function (e) { e.stopPropagation(); show(k); });
        d.addEventListener('keydown', function (e) {
          if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); show(k); }
        });
      });
    }

    /* ---- VISUAL RULE 10: the controls belong IN the box, and Back sits
       beside Next ----
       The .wbar was authored as a SIBLING of .wt-steps, so it read as a
       detached strip floating under the caption card. Wrap the two into one
       .wt-panel here rather than editing twelve pages by hand, and reorder
       the bar's children in the DOM - not with CSS `order`, which would move
       the buttons visually while leaving tab order telling a different
       story. Left: step dots + label. Right, together: Reset · Back · Next.

       The bar goes FIRST in the panel, above the caption. You drive a
       walkthrough from the controls, so they must sit at a fixed spot the eye
       can return to; below the caption they moved down the page every time a
       step's text changed length. Bar-first also means the controls are the
       panel's first tab stops. */
    if (bar) {
      var stepsBox = wt.querySelector('.wt-steps');
      if (stepsBox && stepsBox.parentNode === bar.parentNode && !wt.querySelector('.wt-panel')) {
        var panel = document.createElement('div');
        panel.className = 'wt-panel';
        stepsBox.parentNode.insertBefore(panel, stepsBox);
        panel.appendChild(bar);
        panel.appendChild(stepsBox);
      }
      [dotbox, label, resetBtn, prev, next].forEach(function (el) {
        if (el) bar.appendChild(el);
      });
    }

    var i = 0, raf = null;
    function title(k) {
      var s = steps[k];
      if (s.getAttribute('data-title')) return s.getAttribute('data-title');
      var d = s.querySelector('.wt-do');
      return d ? d.textContent.trim() : '';
    }
    function repos() {
      if (raf) cancelAnimationFrame(raf);
      raf = requestAnimationFrame(function () { placeCue(steps[i]); });
    }
    function show(n) {
      i = Math.max(0, Math.min(steps.length - 1, n));
      resetStage();
      for (var k = 0; k <= i; k++) applyStep(steps[k]);
      steps.forEach(function (s, k) { s.classList.toggle('on', k === i); });
      dots.forEach(function (d, k) { d.classList.toggle('on', k === i); });
      if (label) label.innerHTML = 'Step <b>' + (i + 1) + '</b> / ' + steps.length + ' · ' + title(i);
      if (prev) prev.disabled = i === 0;
      if (next) next.disabled = i === steps.length - 1;
      placeCue(steps[i]);
      // re-measure after the shell's own transitions settle (sheets, dock)
      [90, 320, 560].forEach(function (t) { setTimeout(repos, t); });
    }
    // stopPropagation so the nav never counts as an "outside click" that would
    // dismiss an overlay the step just opened
    if (prev) prev.addEventListener('click', function (e) { e.stopPropagation(); show(i - 1); });
    if (next) next.addEventListener('click', function (e) { e.stopPropagation(); show(i + 1); });
    if (resetBtn) resetBtn.addEventListener('click', function (e) { e.stopPropagation(); show(0); });

    /* VISUAL RULE 10: stepping is arrow-key navigable. Bound per .wt and
       guarded to that walkthrough, so a page holding two of them steps the
       one you are actually in. A page with exactly one .wt responds without
       needing focus first; anything else requires focus, because guessing
       would steal arrows from the wrong widget. Never intercept arrows aimed
       at a control the user is editing. */
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;
      var t = e.target;
      if (t && t.closest && t.closest('input,textarea,select,[contenteditable="true"]')) return;
      var owner = t && t.closest ? t.closest('.wt') : null;
      if (!owner) {
        var only = all('.wt');
        if (only.length !== 1) return;
        owner = only[0];
      }
      if (owner !== wt) return;
      e.preventDefault();
      show(e.key === 'ArrowRight' ? i + 1 : i - 1);
    });

    window.addEventListener('resize', repos);
    if (window.ResizeObserver) new ResizeObserver(repos).observe(stage);
    // Any scroller that can move a cue target must re-position the cue.
    // .pdock belongs here: reveal() scrolls the dock itself when it overflows,
    // and without this listener a late dock scroll left the cue ~8px off its
    // target (seen only on Library-tile steps, where the dock is tallest).
    all('.pdock,.dgrp-b,.filmstrip,.libgrid', stage).forEach(function (sc) {
      sc.addEventListener('scroll', repos, { passive: true });
    });

    // deep link: ?step=5 opens the walkthrough on that step (handy for
    // pointing a reviewer at one moment in the flow)
    var deep = /[?&]step=(\d+)/.exec(location.search);
    show(deep ? parseInt(deep[1], 10) - 1 : 0);
  });

  /* ---- 10 · capture toasts (PRODUCT-MODEL §4e.3) ----
     [data-toast="#someToast"] fires another copy of that .ctoast into the
     .ctoast-stack it already lives in, so a page can demonstrate the real
     behavior: captures STACK, newest in the corner, and each one is
     transient — it leaves on its own and never grows a close button.
     The pointed-at .ctoast stays put, which is what an anatomy specimen
     wants; only the clones come and go. */
  var TOAST_HOLD = 4200, TOAST_OUT = 240;
  all('[data-toast]').forEach(function (btn) {
    var src = document.querySelector(btn.getAttribute('data-toast'));
    if (!src) return;
    var stack = src.closest('.ctoast-stack');
    if (!stack) return;
    btn.addEventListener('click', function () {
      var c = src.cloneNode(true);
      c.removeAttribute('id');
      all('[id]', c).forEach(function (n) { n.removeAttribute('id'); });
      stack.appendChild(c);
      setTimeout(function () {
        c.classList.add('out');
        setTimeout(function () { if (c.parentNode) c.parentNode.removeChild(c); }, TOAST_OUT);
      }, TOAST_HOLD);
    });
  });

  /* ---- 11 · THE color picker (one control, every color slot) ----
     Every `.cpick` in the page becomes a live picker: drag the SV field,
     drag hue and alpha, type a hex / rgb / hsl value, or click a derived
     shade. The shades ramp and the related-hue row are computed from the
     CURRENT color on every change, so "a bit darker" is always one click
     away and never needs a second dialog.

     Authoring contract, all on the .cpick element:
       data-cp-color="#7C4DFF"   the color it opens on
       data-cp-fill="sel,sel"    elements whose background follows the color
       data-cp-text="sel,sel"    elements whose text becomes the hex
     It also fires `cp:change` with {hex, rgba, r,g,b,a, h,s,l} so a page can
     do something bespoke (repaint a canvas layer, move a gradient stop)
     without re-implementing any color math. */
  function cpClamp(n, a, b) { return Math.min(b, Math.max(a, n)); }

  function hsv2rgb(h, s, v) {
    h = ((h % 360) + 360) % 360 / 60;
    var c = v * s, x = c * (1 - Math.abs(h % 2 - 1)), m = v - c, p;
    if (h < 1) p = [c, x, 0]; else if (h < 2) p = [x, c, 0]; else if (h < 3) p = [0, c, x];
    else if (h < 4) p = [0, x, c]; else if (h < 5) p = [x, 0, c]; else p = [c, 0, x];
    return p.map(function (n) { return Math.round((n + m) * 255); });
  }
  function rgb2hsv(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, h = 0;
    if (d) {
      if (mx === r) h = 60 * (((g - b) / d) % 6);
      else if (mx === g) h = 60 * ((b - r) / d + 2);
      else h = 60 * ((r - g) / d + 4);
    }
    return { h: ((h % 360) + 360) % 360, s: mx ? d / mx : 0, v: mx };
  }
  function rgb2hsl(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, l = (mx + mn) / 2, h = 0, s = 0;
    if (d) {
      s = d / (1 - Math.abs(2 * l - 1));
      if (mx === r) h = 60 * (((g - b) / d) % 6);
      else if (mx === g) h = 60 * ((b - r) / d + 2);
      else h = 60 * ((r - g) / d + 4);
    }
    return { h: ((h % 360) + 360) % 360, s: s, l: l };
  }
  function hsl2rgb(h, s, l) {
    h = ((h % 360) + 360) % 360;
    var c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2, p;
    if (h < 60) p = [c, x, 0]; else if (h < 120) p = [x, c, 0]; else if (h < 180) p = [0, c, x];
    else if (h < 240) p = [0, x, c]; else if (h < 300) p = [x, 0, c]; else p = [c, 0, x];
    return p.map(function (n) { return Math.round((n + m) * 255); });
  }
  function rgb2hex(r, g, b) {
    return '#' + [r, g, b].map(function (n) {
      return cpClamp(Math.round(n), 0, 255).toString(16).padStart(2, '0');
    }).join('').toUpperCase();
  }
  /* Accepts everything a designer actually pastes: #abc, #aabbcc, #aabbccdd,
     bare hex, rgb()/rgba(), hsl()/hsla(), with commas or spaces. */
  function cpParse(str) {
    if (!str) return null;
    var s = String(str).trim().toLowerCase(), m;
    m = /^#?([0-9a-f]{3,8})$/.exec(s);
    if (m) {
      var x = m[1];
      if (x.length === 3 || x.length === 4) x = x.split('').map(function (c) { return c + c; }).join('');
      if (x.length !== 6 && x.length !== 8) return null;
      return { r: parseInt(x.slice(0, 2), 16), g: parseInt(x.slice(2, 4), 16), b: parseInt(x.slice(4, 6), 16),
               a: x.length === 8 ? parseInt(x.slice(6, 8), 16) / 255 : 1 };
    }
    m = /^rgba?\(([^)]+)\)$/.exec(s);
    if (m) {
      var p = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
      if (p.length < 3 || p.some(isNaN)) return null;
      return { r: cpClamp(p[0], 0, 255), g: cpClamp(p[1], 0, 255), b: cpClamp(p[2], 0, 255),
               a: p.length > 3 ? cpClamp(p[3] > 1 ? p[3] / 100 : p[3], 0, 1) : 1 };
    }
    m = /^hsla?\(([^)]+)\)$/.exec(s);
    if (m) {
      var q = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
      if (q.length < 3 || q.some(isNaN)) return null;
      var c = hsl2rgb(q[0], cpClamp(q[1], 0, 100) / 100, cpClamp(q[2], 0, 100) / 100);
      return { r: c[0], g: c[1], b: c[2], a: q.length > 3 ? cpClamp(q[3] > 1 ? q[3] / 100 : q[3], 0, 1) : 1 };
    }
    return null;
  }
  function cpLum(r, g, b) {
    var c = [r, g, b].map(function (n) {
      n /= 255; return n <= 0.03928 ? n / 12.92 : Math.pow((n + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  }
  function cpContrast(l1, l2) { return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05); }

  // Nine steps of the SAME hue and saturation, light to dark. This is the
  // "one shade up / one shade down" row: it is derived, never authored, so
  // it is right for whatever color you are on.
  var CP_LS = [0.94, 0.86, 0.76, 0.65, 0.54, 0.44, 0.34, 0.24, 0.14];
  var CP_HARM = [-60, -30, 30, 60, 120, 180];

  // The channel sets. HSL and RGB are pure sliders - one control per
  // channel, so nothing is represented twice. HEX has no channels to
  // slide, so it keeps the hue and alpha tracks plus a text field, which
  // is also the paste target.
  var CP_SETS = {
    hsl: ['h', 's', 'l', 'a'],
    rgb: ['r', 'g', 'b', 'a'],
    hex: ['h', 'a']
  };
  var CP_CH = {
    h: { lb: 'H', max: 360, unit: '' },
    s: { lb: 'S', max: 100, unit: '%' },
    l: { lb: 'L', max: 100, unit: '%' },
    r: { lb: 'R', max: 255, unit: '' },
    g: { lb: 'G', max: 255, unit: '' },
    b: { lb: 'B', max: 255, unit: '' },
    a: { lb: 'A', max: 100, unit: '%' }
  };
  // A color slot holds a PAINT. Solid is one color; the gradient types are a
  // list of stops. Everything below the type row is shared between them,
  // which is why picking a gradient never feels like a different editor.
  var CP_TYPES = ['solid', 'linear', 'radial', 'angular'];
  var CP_GRAD = { linear: 1, radial: 1, angular: 1 };

  /* One path for the whole callout: a rounded rectangle whose bottom edge
     detours into a beak. Drawn as SVG rather than as a box plus a rotated
     square so there is a single fill and a single stroke, and therefore no
     junction where two semi-transparent 1px borders can meet and darken.
       w,h  the card's box            bx   where the point should aim
       R    corner radius             BH   how far the beak drops
       SH   shoulder easing          TIP   how blunt the point is */
  function drawBubble(svg, w, h, bx) {
    if (!svg) return;
    var R = 8, BH = 9, HALF = 9, SH = 3, TIP = 2.6, o = 0.5;   // o: keep the 1px stroke crisp
    var r = w - o, b = h - o;
    var d = [
      'M', R + o, o,
      'H', r - R, 'A', R, R, 0, 0, 1, r, R + o,
      'V', b - R, 'A', R, R, 0, 0, 1, r - R, b,
      // right shoulder: ease off the bottom edge into the beak's side
      'H', bx + HALF + SH,
      'Q', bx + HALF, b, bx + HALF - SH * 0.5, b + SH * 0.5,
      'L', bx + TIP, b + BH - TIP,
      // the point itself, blunted like every other corner in the app
      'Q', bx, b + BH, bx - TIP, b + BH - TIP,
      'L', bx - HALF + SH * 0.5, b + SH * 0.5,
      'Q', bx - HALF, b, bx - HALF - SH, b,
      // left shoulder, then back along the bottom
      'H', R + o, 'A', R, R, 0, 0, 1, o, b - R,
      'V', R + o, 'A', R, R, 0, 0, 1, R + o, o, 'Z'
    ].map(function (n) { return typeof n === 'number' ? Math.round(n * 100) / 100 : n; }).join(' ');
    svg.setAttribute('width', w);
    svg.setAttribute('height', h + BH + 2);
    svg.setAttribute('viewBox', '0 0 ' + w + ' ' + (h + BH + 2));
    svg.querySelector('path').setAttribute('d', d);
  }

  all('.cpick').forEach(function (cp) {
    var sv = cp.querySelector('[data-cp-sv]');
    var dot = cp.querySelector('.cp-dot');
    var stack = cp.querySelector('[data-cp-sliders]');
    var modeBox = cp.querySelector('[data-cp-mode]');
    var typeBox = cp.querySelector('[data-cp-types]');
    var geoBox = cp.querySelector('[data-cp-geo]');
    var scopeBox = cp.querySelector('[data-cp-scope]');
    var chipBox = cp.querySelector('[data-cp-chips]');
    var prevNow = cp.querySelector('.cp-prev .now');
    var prevWas = cp.querySelector('.cp-prev .was');
    var nameEl = cp.querySelector('.cp-name');
    var ctr = cp.querySelector('[data-cp-ctr]');
    var mode = 'hsl';
    var scope = 'shades';
    var refreshCard = function () {};   // replaced when the gradient body exists
    var st = { h: 258, s: 0.7, v: 1, a: 1 };
    var paint = { type: 'solid', angle: 135, cx: 50, cy: 50, stops: [], sel: 0 };
    // Colors the document already uses, authored by the page.
    var docColors = (cp.getAttribute('data-cp-recent') || '')
      .split(',').map(function (x) { return x.trim(); }).filter(Boolean);

    var seed = cpParse(cp.getAttribute('data-cp-color') || '#7C4DFF');
    if (seed) {
      var sh = rgb2hsv(seed.r, seed.g, seed.b);
      st = { h: sh.h, s: sh.s, v: sh.v, a: seed.a };
    }
    var opened = rgb2hex.apply(null, hsv2rgb(st.h, st.s, st.v));
    if (prevWas) prevWas.style.background = opened;

    // An unset binding is normal, and querySelectorAll('') throws, so resolve
    // the selector list here rather than at every call site.
    function bound(attr) {
      var sel = cp.getAttribute(attr);
      return sel ? all(sel) : [];
    }

    function rgb() { return hsv2rgb(st.h, st.s, st.v); }
    function hex() { return rgb2hex.apply(null, rgb()); }
    function rgba() {
      var c = rgb();
      return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + Math.round(st.a * 100) / 100 + ')';
    }
    function isGrad() { return !!CP_GRAD[paint.type]; }

    function setFromRGB(r, g, b, a) {
      var h = rgb2hsv(r, g, b);
      // A pure black or pure white has no hue of its own; keep the hue the
      // user was on so the SV dot does not jump when they drag to a corner.
      st.h = (h.s === 0 || h.v === 0) ? st.h : h.h;
      st.s = h.s; st.v = h.v;
      if (typeof a === 'number') st.a = a;
      sync();
    }

    /* ---- channels: read, write, and what the track looks like ---- */
    function chGet(k) {
      var c = rgb(), hsl = rgb2hsl(c[0], c[1], c[2]);
      if (k === 'h') return Math.round(hsl.h);
      if (k === 's') return Math.round(hsl.s * 100);
      if (k === 'l') return Math.round(hsl.l * 100);
      if (k === 'r') return c[0];
      if (k === 'g') return c[1];
      if (k === 'b') return c[2];
      return Math.round(st.a * 100);
    }

    function chSet(k, n) {
      n = cpClamp(n, 0, CP_CH[k].max);
      if (k === 'a') { st.a = n / 100; sync(); return; }
      if (k === 'r' || k === 'g' || k === 'b') {
        var c = rgb();
        c[{ r: 0, g: 1, b: 2 }[k]] = n;
        setFromRGB(c[0], c[1], c[2]);
        return;
      }
      var cur = rgb2hsl.apply(null, rgb());
      var o = hsl2rgb(k === 'h' ? n : cur.h,
                      k === 's' ? n / 100 : cur.s,
                      k === 'l' ? n / 100 : cur.l);
      var v = rgb2hsv(o[0], o[1], o[2]);
      st.h = k === 'h' ? n : cur.h;
      st.s = v.s; st.v = v.v;
      sync();
    }

    // Every track shows what moving IT does, with the other channels held
    // where they are. That is what makes a slider readable without a legend.
    function chTrack(k) {
      var c = rgb(), hsl = rgb2hsl(c[0], c[1], c[2]);
      var hs = Math.round(hsl.h), ss = Math.round(hsl.s * 100), ls = Math.round(hsl.l * 100);
      if (k === 'h') return 'linear-gradient(to right,hsl(0 100% 50%),hsl(60 100% 50%),hsl(120 100% 50%),' +
        'hsl(180 100% 50%),hsl(240 100% 50%),hsl(300 100% 50%),hsl(360 100% 50%))';
      if (k === 's') return 'linear-gradient(to right,hsl(' + hs + ' 0% ' + ls + '%),hsl(' + hs + ' 100% ' + ls + '%))';
      if (k === 'l') return 'linear-gradient(to right,#000,hsl(' + hs + ' ' + ss + '% 50%),#fff)';
      if (k === 'a') return 'linear-gradient(to right,transparent,' + hex() + ')';
      var lo = c.slice(), hi = c.slice(), i = { r: 0, g: 1, b: 2 }[k];
      lo[i] = 0; hi[i] = 255;
      return 'linear-gradient(to right,rgb(' + lo.join(',') + '),rgb(' + hi.join(',') + '))';
    }

    /* ---- the paint ---- */
    function stopList(shift) {
      shift = shift || 0;
      return paint.stops.slice().sort(function (a, b) { return a.pos - b.pos; })
        .map(function (s) { return s.hex + ' ' + Math.round(s.pos + shift) + '%'; }).join(',');
    }
    // A CSS linear gradient always runs through the middle of the box, so moving
    // its origin is expressed by sliding every stop along the axis instead. Only
    // the component of the move that lies ALONG the axis can show: sideways is
    // a no-op for a linear, which is exactly how the real thing behaves.
    function axisShift() {
      var a = paint.angle * Math.PI / 180;
      return ((paint.cx - 50) / 100) * Math.sin(a) + ((paint.cy - 50) / 100) * -Math.cos(a);
    }
    // What a gradient WOULD look like from here. A thumbnail has to predict the
    // result, so before any stops exist it previews the same pair that picking
    // the type would actually seed.
    function previewList() {
      if (paint.stops.length) return stopList();
      var hsl = rgb2hsl.apply(null, rgb());
      var second = rgb2hex.apply(null, hsl2rgb((hsl.h + 40) % 360, hsl.s, Math.min(0.86, hsl.l + 0.18)));
      return hex() + ' 0%,' + second + ' 100%';
    }
    // `type` lets the thumbnails render a type they are not currently on.
    function paintCSS(type) {
      var t = type || paint.type;
      if (!CP_GRAD[t]) return type ? (paint.stops[0] ? paint.stops[0].hex : rgba()) : rgba();
      if (t === 'linear') {
        // thumbnails render the type as-is; the live paint carries its origin
        var list = type ? previewList() : stopList(axisShift() * 100);
        return 'linear-gradient(' + Math.round(paint.angle) + 'deg,' + list + ')';
      }
      var list = previewList();
      if (t === 'radial') return 'radial-gradient(circle at ' + Math.round(paint.cx) + '% ' +
        Math.round(paint.cy) + '%,' + list + ')';
      return 'conic-gradient(from ' + Math.round(paint.angle) + 'deg at ' +
        Math.round(paint.cx) + '% ' + Math.round(paint.cy) + '%,' + list + ')';
    }
    function rampCSS() { return 'linear-gradient(90deg,' + stopList() + ')'; }

    // Turning a solid into a gradient starts from the color you already had,
    // so the first thing you see is your color fading out, not a stock preset.
    function seedStops() {
      if (paint.stops.length) return;
      var hsl = rgb2hsl.apply(null, rgb());
      paint.stops = [
        { hex: hex(), pos: 0 },
        { hex: rgb2hex.apply(null, hsl2rgb((hsl.h + 40) % 360, hsl.s, Math.min(0.86, hsl.l + 0.18))), pos: 100 }
      ];
      paint.sel = 0;
    }

    function loadSel() {
      var s = paint.stops[paint.sel];
      if (!s) return;
      var p = cpParse(s.hex);
      if (!p) return;
      var h = rgb2hsv(p.r, p.g, p.b);
      if (!(h.s === 0 || h.v === 0)) st.h = h.h;
      st.s = h.s; st.v = h.v; st.a = p.a;
    }

    /* ---- type thumbnails: four outcomes, not four words ---- */
    function buildTypes() {
      if (!typeBox) return;
      typeBox.innerHTML = CP_TYPES.map(function (t) {
        return '<button class="cp-tt" data-cp-t="' + t + '" title="' + t + '">' +
          '<span class="th"></span><span class="tn">' + t[0].toUpperCase() + t.slice(1) + '</span></button>';
      }).join('');
      all('[data-cp-t]', typeBox).forEach(function (b) {
        b.addEventListener('click', function () { setType(b.getAttribute('data-cp-t')); });
      });
    }
    function paintTypes() {
      if (!typeBox) return;
      all('[data-cp-t]', typeBox).forEach(function (b) {
        var t = b.getAttribute('data-cp-t');
        b.classList.toggle('on', t === paint.type);
        b.setAttribute('aria-pressed', t === paint.type ? 'true' : 'false');
        b.querySelector('.th').style.background = paintCSS(t);
      });
    }
    function setType(t) {
      if (t === paint.type) return;
      var wasSolid = !isGrad();
      paint.type = t;
      if (isGrad()) {
        if (wasSolid) { paint.stops = []; seedStops(); }
        paint.sel = Math.min(paint.sel, paint.stops.length - 1);
        loadSel();
      }
      buildGeo();
      sync();
    }

    /* ---- the aim pad: a direction is something you point at ---- */
    function buildGeo() {
      if (!geoBox) return;
      geoBox.classList.toggle('wt-off', !isGrad());
      if (!isGrad()) { geoBox.innerHTML = ''; return; }
      geoBox.innerHTML =
        '<div class="cp-pad" data-cp-pad tabindex="0" role="slider" aria-label="Gradient direction">' +
          '<svg class="cp-padline" viewBox="0 0 64 64" aria-hidden="true">' +
            '<line x1="32" y1="32" x2="32" y2="4"></line>' +
            '<circle class="pivot" cx="32" cy="32" r="3.5"></circle>' +
            '<circle class="grip" cx="32" cy="4" r="4"></circle>' +
          '</svg>' +
          '<span class="cp-padval" data-cp-padval></span>' +
        '</div>' +
        '<div class="cp-gside">' +
          '<div class="cp-gwrap">' +
            '<div class="cp-stopcard" data-cp-stopcard>' +
              '<svg class="cp-cardbg" data-cp-cardbg aria-hidden="true"><path></path></svg>' +
              '<span class="sw" data-cp-cardsw></span>' +
              '<span class="nm" data-cp-cardnm></span>' +
              '<span class="pl">Position</span>' +
              '<input data-cp-cardpos inputmode="numeric" aria-label="Stop position">' +
            '</div>' +
            '<div class="cp-gramp" data-cp-gramp></div>' +
          '</div>' +
          '<div class="cp-stopbar">' +
            '<span class="sp"></span>' +
            '<button class="cp-mini" data-cp-addstop title="Add a stop"><i class="ic xs ic-plus"></i></button>' +
            '<button class="cp-mini" data-cp-delstop title="Remove this stop"><i class="ic xs ic-minus"></i></button>' +
            '<button class="cp-mini" data-cp-revstops title="Reverse the ramp"><i class="ic xs ic-swap"></i></button>' +
          '</div>' +
        '</div>';

      var pad = geoBox.querySelector('[data-cp-pad]');
      // What the pad can actually change depends on the paint, and it only ever
      // DRAWS a handle for something it can change:
      //   linear   an axis through the middle. A CSS linear gradient has no
      //            movable origin, so there is no centre handle to grab - only
      //            the end of the axis, which rotates it.
      //   angular  a real centre plus a start angle: two handles, both live.
      //   radial   a centre: one handle.
      // GRAB, DO NOT TELEPORT: pressing near the centre keeps the offset so it
      // does not jump out from under the pointer. Press well away from it and a
      // radial places directly, which is the faster gesture when you mean it.
      var grab = null;
      drag(pad, function (x, y, first) {
        var cx = paint.cx / 100, cy = paint.cy / 100;
        if (first) {
          // The centre is a handle on every type: same object as the outer one,
          // drawn smaller. Press near it and you move the origin; press away
          // and you aim.
          var onCentre = Math.abs(x - cx) < 0.17 && Math.abs(y - cy) < 0.17;
          grab = onCentre ? { dx: cx - x, dy: cy - y } : null;
        }
        if (grab) {                                   // moving the centre
          paint.cx = Math.round(cpClamp((x + grab.dx) * 100, 0, 100));
          paint.cy = Math.round(cpClamp((y + grab.dy) * 100, 0, 100));
        } else if (paint.type === 'radial') {         // no angle to aim: place it
          paint.cx = Math.round(x * 100);
          paint.cy = Math.round(y * 100);
        } else {                                      // aiming, around the centre
          var dx = x - cx, dy = y - cy;
          if (!dx && !dy) return;
          paint.angle = Math.round(((Math.atan2(dx, -dy) * 180 / Math.PI) + 360) % 360);
        }
        sync();
      });
      pad.addEventListener('keydown', function (e) {
        var big = e.shiftKey ? 15 : 5;
        if (paint.type === 'radial') return;
        if (e.key === 'ArrowLeft') paint.angle = (paint.angle - big + 360) % 360;
        else if (e.key === 'ArrowRight') paint.angle = (paint.angle + big) % 360;
        else return;
        e.preventDefault(); sync();
      });

      buildStops();

      // The card is an overlay, so it must not sit on top of the field you are
      // trying to use next. It is up while you are working the ramp, and stays
      // up while ANYTHING in the ramp block holds focus - the stop key itself
      // or the Position field - because a focused thing must not lose its label
      // just because the pointer wandered off.
      var card = geoBox.querySelector('[data-cp-stopcard]');
      var pos = geoBox.querySelector('[data-cp-cardpos]');
      var wrap = geoBox.querySelector('.cp-gwrap');
      var overRamp = false, hideT = null;
      refreshCard = function () {
        var ae = document.activeElement;
        card.classList.toggle('on', overRamp || !!(ae && ae !== document.body && wrap.contains(ae)));
      };
      // The card floats clear of the ramp, so travelling from one to the other
      // crosses a few pixels of nothing. Hiding on that gap makes the card
      // impossible to reach: it vanishes exactly when you go for it. So leaving
      // only SCHEDULES the hide, and arriving anywhere in the pair cancels it.
      var setOver = function (on) {
        if (hideT) { clearTimeout(hideT); hideT = null; }
        if (on) { overRamp = true; refreshCard(); return; }
        hideT = setTimeout(function () { hideT = null; overRamp = false; refreshCard(); }, 160);
      };
      wrap.addEventListener('pointerenter', function () { setOver(true); });
      wrap.addEventListener('pointerleave', function () { setOver(false); });
      card.addEventListener('pointerenter', function () { setOver(true); });
      card.addEventListener('pointerleave', function () { setOver(false); });
      // focusout fires before activeElement settles, so read it on the next tick
      wrap.addEventListener('focusin', refreshCard);
      wrap.addEventListener('focusout', function () { setTimeout(refreshCard, 0); });
      pos.addEventListener('focus', function () { pos.select(); });
      pos.addEventListener('blur', paintGeo);
      pos.addEventListener('input', function () {
        var n = parseFloat(pos.value);
        if (isNaN(n)) return;
        paint.stops[paint.sel].pos = cpClamp(n, 0, 100);
        sync();
      });
      pos.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { pos.blur(); return; }
        if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
        e.preventDefault();
        var step = (e.shiftKey ? 10 : 1) * (e.key === 'ArrowUp' ? 1 : -1);
        paint.stops[paint.sel].pos = cpClamp(paint.stops[paint.sel].pos + step, 0, 100);
        sync(); pos.select();
      });

      geoBox.querySelector('[data-cp-addstop]').addEventListener('click', function () {
        var s = paint.stops[paint.sel];
        var next = paint.stops.filter(function (x) { return x.pos > s.pos; })
          .sort(function (a, b) { return a.pos - b.pos; })[0];
        paint.stops.push({ hex: s.hex, pos: Math.round(next ? (s.pos + next.pos) / 2 : Math.min(100, s.pos + 20)) });
        paint.sel = paint.stops.length - 1;
        buildStops(); sync();
      });
      geoBox.querySelector('[data-cp-delstop]').addEventListener('click', function () {
        if (paint.stops.length <= 2) return;      // a gradient needs two
        paint.stops.splice(paint.sel, 1);
        paint.sel = Math.max(0, paint.sel - 1);
        loadSel(); buildStops(); sync();
      });
      geoBox.querySelector('[data-cp-revstops]').addEventListener('click', function () {
        paint.stops.forEach(function (s) { s.pos = 100 - s.pos; });
        buildStops(); sync();
      });
    }

    // The stop keys live on the ramp; only the selected one gets a row.
    function buildStops() {
      var strip = geoBox && geoBox.querySelector('[data-cp-gramp]');
      if (!strip) return;
      strip.innerHTML = paint.stops.map(function (s, i) {
        return '<button class="cp-gstop" data-cp-stop="' + i + '" style="left:' + s.pos + '%" ' +
          'aria-label="Stop ' + (i + 1) + '"><span class="k"></span><span class="ln"></span></button>';
      }).join('');
      all('[data-cp-stop]', strip).forEach(function (k) {
        var i = +k.getAttribute('data-cp-stop');
        k.addEventListener('keydown', function (e) {
          var step = e.shiftKey ? 5 : 1;
          if (e.key === 'ArrowLeft') paint.stops[i].pos = cpClamp(paint.stops[i].pos - step, 0, 100);
          else if (e.key === 'ArrowRight') paint.stops[i].pos = cpClamp(paint.stops[i].pos + step, 0, 100);
          else return;
          paint.sel = i; loadSel(); e.preventDefault(); sync();
        });
        k.addEventListener('pointerdown', function (e) {
          if (e.button !== 0) return;
          paint.sel = i; loadSel(); sync();
          k.focus();                      // selected and focused are the same thing here
          refreshCard();
          try { k.setPointerCapture(e.pointerId); } catch (err) {}
          k.classList.add('drag');
          var move = function (ev) {
            var r = strip.getBoundingClientRect();
            var pos = cpClamp((ev.clientX - r.left) / r.width, 0, 1) * 100;
            // Shift snaps to fives, which is how you land an exact stop without
            // a number field to type into.
            paint.stops[i].pos = ev.shiftKey ? Math.round(pos / 5) * 5 : Math.round(pos);
            sync();
          };
          var up = function (ev) {
            k.classList.remove('drag');
            k.removeEventListener('pointermove', move);
            k.removeEventListener('pointerup', up);
            if (k.hasPointerCapture && k.hasPointerCapture(ev.pointerId)) k.releasePointerCapture(ev.pointerId);
          };
          k.addEventListener('pointermove', move);
          k.addEventListener('pointerup', up);
          e.preventDefault();
        });
      });
      // Clicking the bare strip adds a stop there, the way every ramp works.
      strip.addEventListener('pointerdown', function (e) {
        if (e.target !== strip || e.button !== 0) return;
        var r = strip.getBoundingClientRect();
        paint.stops.push({ hex: hex(), pos: Math.round(cpClamp((e.clientX - r.left) / r.width, 0, 1) * 100) });
        paint.sel = paint.stops.length - 1;
        buildStops(); sync();
      });
    }

    function paintGeo() {
      if (!geoBox || !isGrad()) return;
      var pad = geoBox.querySelector('[data-cp-pad]');
      if (pad) {
        pad.style.background = paintCSS();
        var svg = pad.querySelector('svg');
        var line = svg.querySelector('line'), c0 = svg.querySelectorAll('circle')[0],
            c1 = svg.querySelectorAll('circle')[1];
        var rad = paint.type === 'radial';
        // Two handles of the same family: the small one is the origin, the big
        // one is the direction, and the line says they belong together. Both are
        // grabbable, so both are drawn the same way - nothing here looks like a
        // grip it is not.
        var cx = paint.cx * 0.64, cy = paint.cy * 0.64;
        var a = paint.angle * Math.PI / 180, R = 26;
        var ux = Math.sin(a), uy = -Math.cos(a);
        var ex = cx + ux * R, ey = cy + uy * R;
        c0.style.display = '';
        c0.setAttribute('cx', cx); c0.setAttribute('cy', cy);
        if (rad) {                       // no direction to aim: origin only
          line.style.display = 'none';
          c1.style.display = 'none';
        } else {
          // Run the line between the two centres, not between their edges: the
          // circles are painted after it, so they cap it exactly. Starting it
          // clear of the dot just leaves a gap that has to be tuned by eye and
          // breaks the moment either radius changes.
          line.style.display = '';
          line.setAttribute('x1', cx); line.setAttribute('y1', cy);
          line.setAttribute('x2', ex); line.setAttribute('y2', ey);
          c1.style.display = '';
          c1.setAttribute('cx', ex); c1.setAttribute('cy', ey);
        }
        var val = pad.querySelector('[data-cp-padval]');
        if (val) val.textContent = rad
          ? Math.round(paint.cx) + ',' + Math.round(paint.cy)
          : Math.round(paint.angle) + '°';
        c0.setAttribute('r', rad ? 4 : 2.6);   // origin: the same dot, smaller
      }
      var strip = geoBox.querySelector('[data-cp-gramp]');
      if (strip) strip.style.background = rampCSS();
      all('[data-cp-stop]', geoBox).forEach(function (k) {
        var i = +k.getAttribute('data-cp-stop');
        k.style.left = paint.stops[i].pos + '%';
        k.querySelector('.k').style.background = paint.stops[i].hex;
        k.classList.toggle('sel', i === paint.sel);
      });
      var card = geoBox.querySelector('[data-cp-stopcard]');
      if (card) {
        var s = paint.stops[paint.sel];
        card.querySelector('[data-cp-cardsw]').style.background = s.hex;
        card.querySelector('[data-cp-cardnm]').textContent = 'Stop ' + (paint.sel + 1);
        var pos = card.querySelector('[data-cp-cardpos]');
        if (pos !== document.activeElement) pos.value = Math.round(s.pos) + '%';
        // The card follows the key but stays inside the POPOVER, not inside the
        // ramp: it is an overlay, so it is free to reach back over the aim pad
        // rather than being squeezed into the ramp's column. Once it runs out
        // of room to move, the beak does the pointing.
        var wrap = geoBox.querySelector('.cp-gwrap');
        var gRect = geoBox.getBoundingClientRect(), wRect = wrap.getBoundingClientRect();
        var offset = wRect.left - gRect.left;
        var cw = card.offsetWidth, ch = card.offsetHeight;
        var keyX = s.pos / 100 * wRect.width;
        var left = cpClamp(keyX - cw / 2, -offset, gRect.width - offset - cw);
        card.style.left = Math.round(left) + 'px';
        drawBubble(card.querySelector('[data-cp-cardbg]'), cw, ch,
                   cpClamp(keyX - left, 14, cw - 14));
      }
      var del = geoBox.querySelector('[data-cp-delstop]');
      if (del) del.disabled = paint.stops.length <= 2;
    }

    /* ---- the channel stack, rebuilt when the format changes ---- */
    function renderStack() {
      if (!stack) return;
      var rows = CP_SETS[mode].map(function (k) {
        var d = CP_CH[k];
        return '<span class="cp-sl" data-cp-ch="' + k + '"><b>' + d.lb + '</b>' +
          '<span class="cp-tr' + (k === 'a' ? ' alpha' : '') + '" data-cp-track role="slider" ' +
          'aria-label="' + d.lb + '" aria-valuemin="0" aria-valuemax="' + d.max + '" tabindex="0">' +
          '<i class="cp-knob"></i></span>' +
          '<input data-cp-val inputmode="numeric" spellcheck="false" aria-label="' + d.lb + ' value"></span>';
      });
      if (mode === 'hex') {
        rows.unshift('<span class="cp-hex"><b>#</b>' +
          '<input data-cp-hex spellcheck="false" aria-label="Hex value"></span>');
      }
      stack.innerHTML = rows.join('');

      all('[data-cp-track]', stack).forEach(function (tr) {
        var k = tr.closest('[data-cp-ch]').getAttribute('data-cp-ch');
        drag(tr, function (x) { chSet(k, x * CP_CH[k].max); });
        tr.addEventListener('keydown', function (e) {
          var step = (e.shiftKey ? 10 : 1) * (k === 'h' ? 2 : 1);
          if (e.key === 'ArrowLeft') chSet(k, chGet(k) - step);
          else if (e.key === 'ArrowRight') chSet(k, chGet(k) + step);
          else return;
          e.preventDefault();
        });
        // Right-clicking a track drops you straight into its number. That is
        // the whole reason the value is a field and not a label.
        tr.addEventListener('contextmenu', function (e) {
          e.preventDefault();
          var inp = tr.closest('[data-cp-ch]').querySelector('[data-cp-val]');
          if (inp) { inp.focus(); inp.select(); }
        });
      });

      all('[data-cp-val]', stack).forEach(function (inp) {
        var k = inp.closest('[data-cp-ch]').getAttribute('data-cp-ch');
        inp.addEventListener('input', function () {
          var n = parseFloat(inp.value);
          if (!isNaN(n)) chSet(k, n);
        });
        inp.addEventListener('blur', syncValues);
        inp.addEventListener('focus', function () { inp.select(); });
        inp.addEventListener('keydown', function (e) {
          if (e.key === 'Enter') { inp.blur(); return; }
          if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
          e.preventDefault();
          chSet(k, chGet(k) + (e.shiftKey ? 10 : 1) * (e.key === 'ArrowUp' ? 1 : -1));
          inp.select();
        });
      });

      var hexIn = stack.querySelector('[data-cp-hex]');
      if (hexIn) {
        // Paste is how a color usually arrives, so this takes hex, rgb() or
        // hsl() and works out which it got.
        hexIn.addEventListener('input', function () {
          var p = cpParse(hexIn.value);
          if (p) setFromRGB(p.r, p.g, p.b, p.a);
        });
        hexIn.addEventListener('blur', syncValues);
      }
      syncValues();
    }

    function syncValues() {
      if (!stack) return;
      all('[data-cp-ch]', stack).forEach(function (row) {
        var k = row.getAttribute('data-cp-ch'), v = chGet(k);
        var tr = row.querySelector('[data-cp-track]');
        tr.style.setProperty('--cp-track', chTrack(k));
        tr.querySelector('.cp-knob').style.left = (v / CP_CH[k].max * 100) + '%';
        tr.setAttribute('aria-valuenow', v);
        var inp = row.querySelector('[data-cp-val]');
        if (inp !== document.activeElement) inp.value = v + CP_CH[k].unit;
      });
      var hexIn = stack.querySelector('[data-cp-hex]');
      if (hexIn && hexIn !== document.activeElement) hexIn.value = hex().slice(1);
    }

    /* ---- one swatch row, three scopes ---- */
    function scopeList() {
      var c = rgb(), hsl = rgb2hsl(c[0], c[1], c[2]);
      if (scope === 'related') {
        return CP_HARM.map(function (d) { return rgb2hex.apply(null, hsl2rgb(hsl.h + d, hsl.s, hsl.l)); });
      }
      if (scope === 'document') return docColors;
      return CP_LS.map(function (l) { return rgb2hex.apply(null, hsl2rgb(hsl.h, hsl.s, l)); });
    }
    function paintChips() {
      if (!chipBox) return;
      var h = hex();
      chipBox.innerHTML = scopeList().map(function (x) {
        return '<button class="cp-chip' + (x.toUpperCase() === h ? ' on' : '') +
          '" style="background:' + x + '" title="' + x + '" data-cp-set="' + x + '"></button>';
      }).join('');
    }

    function sync(silent) {
      var c = rgb(), h = hex(), hsl = rgb2hsl(c[0], c[1], c[2]);
      // The color being edited belongs to the paint: it is either the solid,
      // or the selected stop.
      if (isGrad() && paint.stops[paint.sel]) paint.stops[paint.sel].hex = h;
      var css = paintCSS();

      if (sv) {
        sv.style.setProperty('--cp-h', Math.round(st.h));
        if (dot) { dot.style.left = (st.s * 100) + '%'; dot.style.top = ((1 - st.v) * 100) + '%'; }
      }
      if (prevNow) prevNow.style.background = css;
      if (nameEl) {
        var base = cp.getAttribute('data-cp-name') || nameEl.getAttribute('data-base') || nameEl.textContent;
        nameEl.setAttribute('data-base', base);
        nameEl.textContent = base;
      }
      syncValues();
      paintTypes();
      paintGeo();
      paintChips();

      if (ctr) {
        var L = cpLum(c[0], c[1], c[2]);
        var onW = cpContrast(L, 1), onB = cpContrast(L, 0);
        var best = onW >= onB ? onW : onB, over = onW >= onB ? 'white' : 'black';
        var cls = best >= 4.5 ? '' : (best >= 3 ? ' low' : ' bad');
        var tag = best >= 7 ? 'AAA' : (best >= 4.5 ? 'AA' : (best >= 3 ? 'AA L' : 'fail'));
        ctr.innerHTML = '<span class="g' + cls + '">' + tag + '</span> ' +
          (Math.round(best * 10) / 10) + ':1 on ' + over;
      }

      bound('data-cp-fill').forEach(function (el) { el.style.background = css; });
      bound('data-cp-text').forEach(function (el) {
        el.textContent = isGrad() ? (paint.type[0].toUpperCase() + paint.type.slice(1)) : h;
      });
      if (!silent) {
        cp.dispatchEvent(new CustomEvent('cp:change', {
          bubbles: true,
          detail: { hex: h, rgba: rgba(), css: css, r: c[0], g: c[1], b: c[2], a: st.a,
                    h: Math.round(hsl.h), s: hsl.s, l: hsl.l,
                    paint: { type: paint.type, angle: paint.angle, cx: paint.cx, cy: paint.cy,
                             stops: paint.stops.slice() } }
        }));
      }
    }

    // `first` is true on the press, so a handler can decide whether the press
    // grabbed something before it starts tracking.
    function drag(el, onMove) {
      if (!el) return;
      var live = false;
      var at = function (e, first) {
        var r = el.getBoundingClientRect();
        onMove(cpClamp((e.clientX - r.left) / r.width, 0, 1),
               cpClamp((e.clientY - r.top) / r.height, 0, 1), first);
      };
      el.addEventListener('pointerdown', function (e) {
        if (e.button !== 0) return;          // right-click belongs to "type a value"
        live = true;
        // A failed capture must not swallow the drag: without the guard the
        // control looks dead rather than degraded.
        try { el.setPointerCapture(e.pointerId); } catch (err) {}
        el.classList.add('drag');
        el.focus(); at(e, true); e.preventDefault();
      });
      el.addEventListener('pointermove', function (e) { if (live) at(e, false); });
      ['pointerup', 'pointercancel'].forEach(function (t) {
        el.addEventListener(t, function (e) {
          live = false;
          el.classList.remove('drag');
          if (el.hasPointerCapture && el.hasPointerCapture(e.pointerId)) el.releasePointerCapture(e.pointerId);
        });
      });
    }

    drag(sv, function (x, y) { st.s = x; st.v = 1 - y; sync(); });
    if (sv) {
      sv.setAttribute('tabindex', '0');
      sv.addEventListener('keydown', function (e) {
        var big = (e.shiftKey ? 5 : 1) / 100;
        if (e.key === 'ArrowLeft') st.s = cpClamp(st.s - big, 0, 1);
        else if (e.key === 'ArrowRight') st.s = cpClamp(st.s + big, 0, 1);
        else if (e.key === 'ArrowUp') st.v = cpClamp(st.v + big, 0, 1);
        else if (e.key === 'ArrowDown') st.v = cpClamp(st.v - big, 0, 1);
        else return;
        e.preventDefault(); sync();
      });
    }

    if (modeBox) {
      all('button[data-cp-m]', modeBox).forEach(function (b) {
        b.addEventListener('click', function () {
          mode = b.getAttribute('data-cp-m');
          all('button[data-cp-m]', modeBox).forEach(function (x) { x.classList.toggle('on', x === b); });
          renderStack();
        });
      });
    }

    if (scopeBox) {
      all('button[data-cp-sc]', scopeBox).forEach(function (b) {
        b.addEventListener('click', function () {
          scope = b.getAttribute('data-cp-sc');
          all('button[data-cp-sc]', scopeBox).forEach(function (x) { x.classList.toggle('on', x === b); });
          paintChips();
        });
      });
    }

    // One delegated handler covers every swatch in the popover.
    cp.addEventListener('click', function (e) {
      var chip = e.target.closest('[data-cp-set]');
      if (!chip || !cp.contains(chip)) return;
      var p = cpParse(chip.getAttribute('data-cp-set'));
      if (p) setFromRGB(p.r, p.g, p.b, p.a);
    });

    // Re-point the SAME picker at another slot. One popover serves the fill,
    // the stroke, a gradient stop and a shadow, so opening it on a new slot
    // is a re-seed, never a second picker:
    //   el.dispatchEvent(new CustomEvent('cp:set', {detail:{color:'#12C2E9'}}))
    cp.addEventListener('cp:set', function (e) {
      var d = e.detail || {};
      var p = cpParse(d.color || cp.getAttribute('data-cp-color'));
      if (!p) return;
      if (d.paint) {
        paint.type = d.paint.type || 'solid';
        if (typeof d.paint.angle === 'number') paint.angle = d.paint.angle;
        if (typeof d.paint.cx === 'number') paint.cx = d.paint.cx;
        if (typeof d.paint.cy === 'number') paint.cy = d.paint.cy;
        paint.stops = (d.paint.stops || []).slice();
        paint.sel = 0;
      } else {
        paint.type = 'solid';
        paint.stops = [];
      }
      if (isGrad()) { seedStops(); loadSel(); }
      else {
        var h = rgb2hsv(p.r, p.g, p.b);
        if (!(h.s === 0 || h.v === 0)) st.h = h.h;
        st.s = h.s; st.v = h.v; st.a = p.a;
      }
      buildGeo();
      opened = hex();
      if (prevWas) prevWas.style.background = paintCSS();
      // Not silent: re-pointing the picker at a slot should push that slot's
      // paint through the same binding path as any edit, so a page never has
      // to special-case "the value it opened on".
      sync();
    });

    buildTypes();
    if (typeBox) {
      var t0 = cp.getAttribute('data-cp-type');
      if (t0 && CP_TYPES.indexOf(t0) > -1) paint.type = t0;
      if (isGrad()) { seedStops(); loadSel(); }
    }
    buildGeo();
    renderStack();
    sync(true);
  });
})();
