/* ============================================================
   SEGMENTED CONTROL — behaviour
   ============================================================
   `.seg` had an owner for its LOOK (segmented.css) and no owner at all for
   what it DOES. There was no segmented.js. Nothing in the design system ever
   moved the `.on` class, so every segmented control on every page was inert
   markup that only looked like a control — clicking one did nothing.

   The places where it did work had each rebuilt it privately: the colour
   picker with `data-cp-m` / `data-cp-sc` handlers, `ui-grid` and
   `ui-autolayout` with page-local listeners. Same shape as the CSS problem
   the component file describes, one layer down.

   This file is the owner of the behaviour.

   IT DOES NOT FIGHT THE PRIVATE HANDLERS. The colour picker still runs its
   own click handler and still sets the same `.on` class; both handlers landing
   on the same click is harmless because they agree on the result. The plate
   does not listen for clicks at all — it follows the `.on` class with a
   MutationObserver, so it stays correct no matter WHO moved the selection: a
   private handler, a page script, or a devtools poke.

     PZ.segmented.sync(el)   reposition after you move `.on` yourself
     'change' event on .seg  { detail:{ index, value, button } }, bubbles

   `data-value` on a segment names it for the event; the label is the fallback.
   ============================================================ */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all;

  var REDUCED = window.matchMedia && window.matchMedia('(prefers-reduced-motion:reduce)').matches;

  function buttons(seg) { return all('button', seg).filter(function (b) { return b.parentNode === seg; }); }
  function selected(seg) {
    var b = buttons(seg);
    for (var i = 0; i < b.length; i++) if (b[i].classList.contains('on')) return b[i];
    return null;
  }

  /* Put the plate under the selected button. Measured from the button's own
     box rather than computed from a column count, because the natural-width
     form has unequal segments and the grid form changes width with the dock.
     `animate:false` lands it without a transition — used for first paint and
     for relayout, where a spring across a resize looks like a glitch. */
  function place(seg, animate) {
    var plate = seg.__plate;
    if (!plate) return;
    var btn = selected(seg);
    if (!btn) { plate.classList.add('off'); return; }
    // A control that is display:none has no box; measuring it would park the
    // plate at 0x0 and it would fly out of the corner when the panel opens.
    // Leave it hidden and wait — the ResizeObserver fires when it gets a size.
    if (!seg.offsetWidth) return;

    /* Suppressing the transition is done with an INLINE style, set and cleared
       inside this one successful placement. It used to be a `.notr` class put
       on the plate at creation and removed only on the snap path — so when a
       control was hidden at startup and this function early-returned above,
       `notr` stuck forever and that control never animated again. Anything
       that can outlive an early return is the wrong place for this. */
    var snap = !animate || REDUCED || !plate.__placed;
    if (snap) {
      plate.style.transition = 'none';
      void plate.offsetWidth;   // let the no-transition state take effect
    }
    plate.classList.remove('off');
    plate.style.width = btn.offsetWidth + 'px';
    plate.style.height = btn.offsetHeight + 'px';
    plate.style.transform = 'translate(' + btn.offsetLeft + 'px,' + btn.offsetTop + 'px)';
    plate.__placed = true;
    if (snap) {
      void plate.offsetWidth;
      plate.style.transition = '';
    }
  }

  function select(seg, btn) {
    if (!btn || btn.disabled || btn.classList.contains('disabled')) return;
    var b = buttons(seg);
    // A private handler bound straight to the button (the colour picker does
    // this) fires in the target phase, BEFORE this delegated one bubbles — so
    // `.on` may already be correct by the time we get here. Re-sync aria and
    // the roving tabindex regardless, and only suppress the change event.
    var was = btn.classList.contains('on');
    b.forEach(function (x) {
      x.classList.toggle('on', x === btn);
      x.setAttribute('aria-checked', x === btn ? 'true' : 'false');
      // roving tabindex: one stop for the whole control, arrows move inside it
      x.tabIndex = x === btn ? 0 : -1;
    });
    seg.dispatchEvent(new CustomEvent('change', {
      bubbles: true,
      detail: {
        index: b.indexOf(btn),
        value: btn.getAttribute('data-value') || btn.textContent.trim(),
        button: btn
      }
    }));
  }

  /* Arrow keys move the selection, which is what a radio group does and what
     the native macOS segmented control does. Home/End jump to the ends.
     Disabled segments are stepped OVER rather than landed on, so a control
     with an unavailable option in the middle does not trap the keyboard.

     IT DOES NOT WRAP. Arrowing off the last segment stays on the last segment
     — it does not cycle round to the first. A segmented control is a row you
     can see all of, so the ends are visible ends; jumping the plate from one
     side of the track to the other reads as the value having been reset rather
     than nudged. (A menu wraps because you cannot see where its list stops.
     This can, so it stops.) */
  function step(seg, from, dir) {
    var b = buttons(seg);
    var i = b.indexOf(from);
    if (i < 0) return null;
    for (i += dir; i >= 0 && i < b.length; i += dir) {
      if (!b[i].disabled && !b[i].classList.contains('disabled')) return b[i];
    }
    return null;   // already at that end: stay put
  }

  /* ============================================================
     TOO NARROW TO BE A SEGMENTED CONTROL
     ============================================================
     The spec always said "above 4 options, or below about 44px a segment, it
     is a `.select`" — but that was advice to whoever was writing the page, and
     a page cannot know how wide it will be. So the honest failure mode shipped
     instead: at 120px a four-option control truncated every label to 27px and
     read `U… S… I… E…`, which is not a control, it is a row of first letters.

     The control now does it itself. The trigger is not a magic number: it
     collapses exactly when a label would have to ellipsize, which is the same
     line the spec already drew, just measured instead of guessed.

     THE COLLAPSED FORM STAYS IN THE LAYOUT. The segments are hidden with
     `visibility`, not `display`, and the menu trigger is laid over them. That
     is deliberate — a control removed from the flow can no longer measure the
     space it was given, so deciding when to come BACK would mean measuring the
     parent and guessing, and any error there oscillates: expand, get squeezed,
     collapse, expand. Keeping the box means the control always knows its own
     width and the decision can never flip-flop.

     Icon-only controls never collapse: there is no label to truncate, and the
     icons are already the compact form. `.seg.no-collapse` opts out. */

  /* THE TRIGGER IS TRUNCATION ITSELF, not a reconstruction of it.
     The first version summed each segment's max-content width and compared
     that to the track. It over-triggered badly — 55 of 73 controls collapsed
     at full width — because rounding each segment up before summing invented
     about a pixel per segment, and the margins here are genuinely that tight
     (a 3-option control missed by 4px on a 148px track).

     Asking the browser whether a label is ACTUALLY clipped removes the
     arithmetic, and with it the rounding. It is also exactly the rule the spec
     states, rather than a proxy for it. Collapsing does not change the
     segments' layout — they keep their boxes and only lose `visibility` — so
     this stays measurable in both forms and cannot feed back on itself. */
  /* HOW MUCH CLIPPING IS TOO MUCH. Not any at all: the ellipsis glyph is
     10.2px at 11.5px/560, while an average character in these labels is 6.3px.
     So drawing `…` costs about two characters — a label overflowing by 2px
     loses ~12px of text to say so. Below one ellipsis of overflow the clip is
     cosmetically trivial and collapsing the whole control would be the larger
     loss; at or above it the label is genuinely losing words.

     Measured from the segment's own computed font rather than hard-coded, so
     `.sm` and `.lg` get their own thresholds and a font change cannot silently
     move the boundary. */
  function ellipsisWidth(btn) {
    var ctx = ellipsisWidth.ctx ||
      (ellipsisWidth.ctx = document.createElement('canvas').getContext('2d'));
    var cs = getComputedStyle(btn);
    ctx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily;
    return ctx.measureText('…').width;
  }

  function isCramped(seg) {
    return buttons(seg).some(function (b) {
      return b.scrollWidth - b.clientWidth > ellipsisWidth(b);
    });
  }

  function closeMenu(seg) {
    if (!seg.__menu) return;
    seg.__menu.classList.remove('on');
    if (seg.__alt) seg.__alt.setAttribute('aria-expanded', 'false');
  }

  function openMenu(seg) {
    var menu = seg.__menu, alt = seg.__alt;
    if (!menu || !alt) return;
    all('.seg-menu.on').forEach(function (m) { m.classList.remove('on'); });
    // rebuilt each open: the options never change, but which one is current does
    menu.innerHTML = '';
    buttons(seg).forEach(function (b) {
      var item = document.createElement('button');
      item.className = 'menuitem' + (b.classList.contains('on') ? ' on' : '');
      item.textContent = b.textContent.trim();
      if (b.disabled || b.classList.contains('disabled')) item.disabled = true;
      item.addEventListener('click', function (e) {
        e.stopPropagation();
        b.click();          // through the button, so private handlers still run
        closeMenu(seg);
        alt.focus();
      });
      menu.appendChild(item);
    });
    menu.classList.add('on');
    alt.setAttribute('aria-expanded', 'true');
    // positioned on open, in viewport coordinates: `.popover` carries no
    // position of its own, every page places its own popovers by hand.
    var r = alt.getBoundingClientRect();
    menu.style.minWidth = Math.round(r.width) + 'px';
    var mh = menu.offsetHeight;
    var below = window.innerHeight - r.bottom;
    menu.style.left = Math.round(Math.min(r.left, window.innerWidth - menu.offsetWidth - 8)) + 'px';
    menu.style.top = Math.round(below < mh && r.top > mh ? r.top - mh - 4 : r.bottom + 4) + 'px';
    var cur = menu.querySelector('.menuitem.on') || menu.querySelector('.menuitem');
    if (cur) cur.focus();
  }

  function buildAlt(seg) {
    if (seg.__alt) return;
    /* A SPAN, not a button, on purpose. Every `.seg > button` rule in
       segmented.css — the capsule radius, the centred flex, the transparent
       fill — outranks `.select`, so a button trigger came out shaped like a
       segment instead of a menu. Worse, `buttons()` selects by tag name, so
       the trigger counted itself as a fifth segment: it appeared in the menu,
       in the arrow-key order, and in the natural-width sum. Making it a span
       takes it out of both the cascade and the segment list by construction,
       rather than by remembering to exclude it in a dozen places. */
    var alt = document.createElement('span');
    alt.className = 'select seg-alt';
    alt.setAttribute('role', 'button');
    alt.setAttribute('tabindex', '0');
    alt.setAttribute('aria-haspopup', 'listbox');
    alt.setAttribute('aria-expanded', 'false');
    alt.innerHTML = '<span class="lead"></span><span class="car"><i class="ic xs ic-chevron-down"></i></span>';
    seg.appendChild(alt);
    seg.__alt = alt;

    var menu = document.createElement('div');
    menu.className = 'popover menu seg-menu';
    document.body.appendChild(menu);
    seg.__menu = menu;

    alt.addEventListener('click', function (e) {
      e.stopPropagation();
      if (menu.classList.contains('on')) closeMenu(seg); else openMenu(seg);
    });
    alt.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openMenu(seg); }
    });
    menu.addEventListener('keydown', function (e) {
      var items = all('.menuitem:not([disabled])', menu);
      var i = items.indexOf(document.activeElement);
      if (e.key === 'Escape') { e.preventDefault(); closeMenu(seg); alt.focus(); }
      else if (e.key === 'ArrowDown') { e.preventDefault(); (items[i + 1] || items[items.length - 1]).focus(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); (items[i - 1] || items[0]).focus(); }
    });
  }

  function syncAltLabel(seg) {
    var btn = selected(seg);
    if (seg.__alt && btn) seg.__alt.querySelector('.lead').textContent = btn.textContent.trim();
  }

  function fit(seg) {
    if (seg.classList.contains('icons') || seg.classList.contains('no-collapse')) return;
    if (!seg.offsetWidth) return;
    var want = isCramped(seg);
    if (want && !seg.__alt) buildAlt(seg);
    if (want !== seg.classList.contains('collapsed')) {
      seg.classList.toggle('collapsed', want);
      if (!want) closeMenu(seg);
    }
    if (want) syncAltLabel(seg);
  }

  function attach(seg) {
    if (seg.__segInit) return;
    seg.__segInit = true;

    var b = buttons(seg);
    if (!b.length) return;

    var plate = document.createElement('span');
    // starts hidden: until it has been placed against a real box there is
    // nothing meaningful to draw, and a 0x0 plate at the origin flashes.
    plate.className = 'seg-plate off';
    // decorative: the selected state is announced by aria-checked on the button
    plate.setAttribute('aria-hidden', 'true');
    seg.insertBefore(plate, seg.firstChild);
    seg.__plate = plate;
    seg.classList.add('has-plate');

    if (!seg.hasAttribute('role')) seg.setAttribute('role', 'radiogroup');
    var cur = selected(seg);
    b.forEach(function (x) {
      if (!x.hasAttribute('role')) x.setAttribute('role', 'radio');
      x.setAttribute('aria-checked', x === cur ? 'true' : 'false');
      x.tabIndex = (cur ? x === cur : x === b[0]) ? 0 : -1;
    });

    seg.addEventListener('click', function (e) {
      var btn = e.target.closest('button');
      if (btn && btn.parentNode === seg) select(seg, btn);
    });

    seg.addEventListener('keydown', function (e) {
      var d = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1
            : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 0;
      var next = null;
      if (d) next = step(seg, e.target, d);
      else if (e.key === 'Home') next = buttons(seg)[0];
      else if (e.key === 'End') next = buttons(seg).slice(-1)[0];
      else return;
      if (!next) return;
      e.preventDefault();
      select(seg, next);
      next.focus();
    });

    /* Follow `.on` wherever it goes, including when somebody else moves it.
       Only the BUTTONS carry selection. Records from the plate, the collapsed
       menu trigger, or the track itself are ignored — `place` and `fit` both
       write classes to those, so reacting to them would feed the observer its
       own output. */
    new MutationObserver(function (recs) {
      for (var i = 0; i < recs.length; i++) {
        var t = recs[i].target;
        if (t !== plate && t !== seg && t !== seg.__alt) {
          seg.__moveAt = Date.now();   // see the ResizeObserver below
          place(seg, true);
          syncAltLabel(seg);
          return;
        }
      }
    }).observe(seg, { subtree: true, attributeFilter: ['class'], attributes: true });

    /* Relayout: a splitter drag, a window resize, a panel opening, or a font
       finally loading all change the segment boxes without touching `.on`.
       Those should SNAP — springing the plate across a resize looks like a bug.

       But a selection change resizes the track too: `.on` is font-weight 620
       against 560, so the labels change width and the control's natural width
       changes with them. That fires this observer in the same frame as the
       move, and snapping there killed the move outright — the plate teleported
       instead of travelling. So a resize that lands in the wake of a selection
       change re-places WITH animation, which re-targets the in-flight
       transition instead of cancelling it.

       This observer's own initial fire is deliberately NOT skipped: a control
       that was hidden when the script ran gets its first real box here, and
       that is the only signal that it is finally measurable. */
    if (window.ResizeObserver) {
      new ResizeObserver(function () {
        fit(seg);                       // decide which form first...
        place(seg, Date.now() - (seg.__moveAt || 0) < 500);   // ...then place
      }).observe(seg);
    }

    place(seg, false);
    fit(seg);
  }

  all('.seg').forEach(attach);

  // Web fonts land after first paint and change every label's width — which
  // moves the collapse threshold too, so the natural width is re-measured.
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () {
      all('.seg').forEach(function (seg) { fit(seg); place(seg, false); });
    });
  }

  document.addEventListener('click', function () {
    all('.seg-menu.on').forEach(function (m) { m.classList.remove('on'); });
  });

  PZ.segmented = {
    attach: attach,
    sync: function (el) {
      (el ? [el] : all('.seg')).forEach(function (seg) { fit(seg); place(seg, false); });
    }
  };
  window.PZ = PZ;
})();
