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
      b.classList.toggle('on', showing);
      b.setAttribute('aria-pressed', showing ? 'true' : 'false');
    });
  }
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
        if (grp.scrollIntoView) grp.scrollIntoView({ block: 'nearest' });
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
    m.addEventListener('click', function (e) { e.stopPropagation(); m.classList.remove('on'); });
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
        var cls = (t.getAttribute('class') || '').split(/\s+/)[0];
        if (!cls || !t.parentNode) return;
        [].slice.call(t.parentNode.children).forEach(function (x) {
          if (x.classList.contains(cls)) x.classList.toggle('on', x === t);
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

      list(s.getAttribute('data-sheet-open')).forEach(function (sh) {
        sh.classList.add('on'); sh.setAttribute('aria-hidden', 'false');
      });
      list(s.getAttribute('data-sheet-shut')).forEach(function (sh) {
        sh.classList.remove('on'); sh.setAttribute('aria-hidden', 'true');
      });

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
})();
