/* ============================================================
   TOOLTIP — behaviour
   ============================================================
   One floating node for the whole document, moved and re-labelled as needed,
   rather than one node per trigger. See tooltip.css for the visual contract.

   Contract:
     data-tip="Label"                     the text
     data-tip="Label|⌘K"                  optional shortcut, shown quieter
     data-tip-side="top|bottom|left|right" default "top", flips if it would clip

   Shows on hover and on keyboard focus (the native `title` never does the
   latter, which is why every icon-only control in the shell was unreachable to
   explain without a mouse). Hides on leave, blur, Escape, scroll, or pointer
   down — a label must never outlive the thing it labels.

   ADOPTION: any element that has a `title` and no `data-tip` is upgraded
   automatically and its `title` is removed, so the browser does not also draw
   its own. That is how ~700 existing title= controls get the styled one without
   editing 51 pages. */
(function () {
  if (window.__photonzTip) return;           // idempotent: safe to run twice
  window.__photonzTip = true;

  /* GAP is the CLEAR SPACE BETWEEN THE BEAK'S TIP AND THE TRIGGER, not between
     the plate and the trigger. That distinction is the whole bug it fixes: the
     beak protrudes ~9px past the plate, so an 8px plate offset put the tip
     flat against the control and the tooltip read as growing out of it.
     The offset the plate actually gets is GAP + the beak's protrusion, and the
     side beak is smaller (see tooltip.css) so it gets its own number. */
  /* DELAY_IN IS REST TIME, NOT DWELL TIME. The clock restarts on every
     pointermove over the trigger, so a tooltip appears once the pointer has
     been STILL for this long — not once it has merely been inside the control
     for this long. Those two read completely differently in use:

       dwell  · crossing a toolbar to reach the far end pops a label on
                whichever button you happened to be over when the clock ran out
       rest   · crossing pops nothing at all, because you never stopped

     A plain dwell timer cannot be tuned out of that problem. Raise it and
     deliberate hovers get sluggish; lower it and sweeps flash labels. Gating on
     stillness removes the trade: sweeping is silent at ANY value, so the number
     only has to answer "how long is a pause that means I want help", and 1s of
     dead-still pointer is comfortably past accidental while still feeling like
     an answer rather than a wait.

     Keyboard focus does not go through this at all (DELAY_FOCUS): there is no
     pointer to hold still, and a tab-stop that waits over a second to explain
     itself is just broken. */
  /* LEAVING AND SWAPPING ARE DIFFERENT EVENTS AND NEED DIFFERENT NUMBERS. They
     had been sharing one 60ms constant, which made "move off the button" and
     "move to the next button" behave identically — and 60ms is right for only
     one of them:

       DELAY_SWAP · open -> neighbour. Stays fast. Walking a toolbar to read the
                    shortcuts should feel like one label tracking the pointer.
       DELAY_HIDE · open -> nothing. Was also 60ms, so the label evaporated the
                    instant you slipped off, including onto the 4px gap BETWEEN
                    two buttons. Reading a shortcut meant holding the pointer
                    perfectly still on the glyph. A grace period fixes both: a
                    brief excursion is treated as travel, not as dismissal.

     Anything that means "gone" rather than "moving on" — Escape, a click, a
     scroll — still hides immediately and ignores both. */
  var DELAY_IN = 1000, DELAY_FOCUS = 120, DELAY_SWAP = 60, DELAY_HIDE = 450, EDGE = 6;
  var GAP = 6, BEAK = 9, BEAK_SIDE = 5;
  /* `pending` is the trigger a scheduled show is aimed at, and it is tracked
     SEPARATELY from `current` (the one actually on screen) because there is a
     long window where a tooltip is owed to a control the pointer may already
     have left. Collapsing the two is what stranded them: see the pointerout
     handler below. */
  var node = null, timer = null, closer = null, current = null, pending = null;
  function offsetFor(side) {
    return GAP + (side === 'left' || side === 'right' ? BEAK_SIDE : BEAK);
  }

  function ensure() {
    if (node) return node;
    node = document.createElement('div');
    node.className = 'tip';
    node.setAttribute('role', 'tooltip');
    document.body.appendChild(node);
    return node;
  }

  function label(el) {
    var raw = el.getAttribute('data-tip') || '';
    var bits = raw.split('|');
    var out = document.createTextNode(bits[0].trim()).textContent
      .replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; });
    if (bits[1]) out += '<span class="k">' + bits[1].trim() + '</span>';
    return out;
  }

  function place(el) {
    var t = ensure();
    var side = el.getAttribute('data-tip-side') || 'top';
    var r = el.getBoundingClientRect();
    t.setAttribute('data-side', side);
    t.style.left = '0px';
    t.style.top = '0px';
    var b = t.getBoundingClientRect();
    var vw = window.innerWidth, vh = window.innerHeight;

    // flip to the opposite side when the preferred one would clip
    var off = offsetFor(side);
    if (side === 'top' && r.top - b.height - off < EDGE) side = 'bottom';
    else if (side === 'bottom' && r.bottom + b.height + off > vh - EDGE) side = 'top';
    else if (side === 'left' && r.left - b.width - off < EDGE) side = 'right';
    else if (side === 'right' && r.right + b.width + off > vw - EDGE) side = 'left';
    t.setAttribute('data-side', side);
    off = offsetFor(side);

    var x, y;
    if (side === 'top' || side === 'bottom') {
      x = r.left + r.width / 2 - b.width / 2;
      y = side === 'top' ? r.top - b.height - off : r.bottom + off;
    } else {
      x = side === 'left' ? r.left - b.width - off : r.right + off;
      y = r.top + r.height / 2 - b.height / 2;
    }
    // keep it on screen, then walk the beak back to the trigger's centre so it
    // still points at what it labels instead of at the tooltip's own middle
    var cx = r.left + r.width / 2;
    x = Math.max(EDGE, Math.min(x, vw - b.width - EDGE));
    y = Math.max(EDGE, Math.min(y, vh - b.height - EDGE));
    t.style.setProperty('--tip-x', (cx - x) + 'px');
    t.style.left = Math.round(x) + 'px';
    t.style.top = Math.round(y) + 'px';
  }

  function show(el, warm) {
    var t = ensure();
    t.innerHTML = label(el);
    current = el;
    pending = null;
    if (warm) {
      /* already open: land the new label in place with no animation at all,
         then hand the transition back so the eventual exit still fades */
      t.classList.add('warm');
      place(el);
      t.classList.add('on');
      requestAnimationFrame(function () { t.classList.remove('warm'); });
      return;
    }
    /* cold: the node has to be measurably in its FROM state before `.on` is
       added, or the browser coalesces both into one style resolution and no
       transition runs. Reading offsetWidth forces that flush — without it the
       entrance animation silently never played. */
    t.classList.remove('on', 'warm');
    place(el);
    void t.offsetWidth;
    t.classList.add('on');
  }

  /* Leaving a control and entering the next one fires pointerout BEFORE
     pointerover, so hiding immediately on leave meant the tooltip was always
     closed by the time the neighbour asked for one — and the "instant between
     neighbours" behaviour could never happen, because the swap path only runs
     when a tooltip is already open. So a leave SCHEDULES the hide and any new
     trigger cancels it. Sweeping a toolbar now keeps one tooltip alive the
     whole way across. Escape, a press or a scroll still hide immediately:
     those mean "gone", not "moving on". */
  function hide(immediate) {
    clearTimeout(timer);
    clearTimeout(closer);
    pending = null;
    if (immediate) {
      current = null;
      if (node) node.classList.remove('on');
      return;
    }
    closer = setTimeout(function () {
      current = null;
      if (node) node.classList.remove('on');
    }, DELAY_HIDE);
  }

  function trigger(e, wait) {
    var el = e.target.closest && e.target.closest('[data-tip]');
    if (!el) return;
    clearTimeout(closer);                                  // cancel a pending leave
    if (el === current) return;
    clearTimeout(timer);
    pending = el;
    var now = !!(node && node.classList.contains('on'));   // already open: swap
    timer = setTimeout(function () { show(el, now); }, now ? DELAY_SWAP : wait);
  }

  document.addEventListener('pointerover', function (e) { trigger(e, DELAY_IN); });
  document.addEventListener('focusin', function (e) { trigger(e, DELAY_FOCUS); });

  /* THE REST CLOCK. Every move over the queued trigger pushes the show back, so
     the tooltip is owed only to a pointer that has come to a stop. Once one is
     already open the swap path owns the timing instead — you have demonstrated
     intent by resting once, and re-earning it at every neighbour would make a
     deliberate walk along a toolbar feel broken. */
  document.addEventListener('pointermove', function (e) {
    if (!pending || current || !e.target.closest) return;
    if (e.target.closest('[data-tip]') !== pending) return;
    var el = pending;
    clearTimeout(timer);
    timer = setTimeout(function () { show(el, false); }, DELAY_IN);
  });
  /* `pointerout` fires when the pointer crosses onto a CHILD of the trigger —
     and every icon button has a child, the glyph. Hiding on that made the
     tooltip flicker off and on as you moved around inside a single button.
     The pointer has only really left when relatedTarget is outside the
     trigger, so check that rather than trusting the event's target. */
  document.addEventListener('pointerout', function (e) {
    if (!e.target.closest) return;
    /* Check the SCHEDULED tooltip too, not just the visible one. Guarding on
       `current` alone stranded every quick pass over a control: the pointer
       entered, a show was queued for 380ms out, the pointer left at 100ms, and
       this handler bailed because nothing was on screen yet — so the timer was
       never cleared. It fired into an empty room 280ms later, and since the
       pointer was long gone no further pointerout would ever arrive for that
       element. The label hung there until you hovered something else, pressed
       Escape, clicked or scrolled. That is the stuck "Volume" tooltip. */
    var active = current || pending;
    if (!active) return;
    if (e.target.closest('[data-tip]') !== active) return;
    var to = e.relatedTarget;
    if (to && to.nodeType === 1 && active.contains(to)) return;    // still inside
    if (!current) { clearTimeout(timer); pending = null; return; } // never opened: just cancel
    hide(false);                                                   // grace period
  });
  document.addEventListener('focusout', function () { hide(false); });
  document.addEventListener('pointerdown', function () { hide(true); });
  document.addEventListener('scroll', function () { hide(true); }, true);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') hide(true); });

  /* Upgrade native title= to the styled tooltip. Runs once now and again
     whenever the shell component adds controls (it sets title= on harvested
     buttons), so nothing has to know about tooltips to get one. */
  function upgrade(root) {
    var els = (root || document).querySelectorAll('[title]:not([data-tip])');
    [].slice.call(els).forEach(function (el) {
      var t = el.getAttribute('title');
      if (!t) return;
      // "Split at playhead (B)" / "Ask the agent, or run a command (⌘K)"
      var m = t.match(/^(.*?)\s*[（(]([^)）]{1,12})[)）]\s*$/);
      el.setAttribute('data-tip', m ? m[1] + '|' + m[2] : t);
      el.removeAttribute('title');
    });
  }
  window.photonzUpgradeTips = upgrade;
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { upgrade(); });
  } else {
    upgrade();
  }
  // Pages add controls after load (walkthrough steps swap panels, the shell
  // component builds chrome). Watch rather than guess at timing: a control that
  // appears in step 6 gets the same tooltip as one that was there at load.
  if (window.MutationObserver) {
    var queued = null;
    new MutationObserver(function () {
      /* A label must never outlive the thing it labels — including when that
         thing is REPLACED rather than left. Pages here re-render whole rows on
         every playhead move (the keyframe lanes, the timeline clips), so the
         element a tooltip is anchored to is routinely detached while the
         tooltip is still on screen, pointing at coordinates nothing occupies.
         No pointer event will ever arrive for a node that is no longer in the
         document, so the DOM change itself has to be the signal. */
      if (current && !document.contains(current)) hide(true);
      clearTimeout(queued);
      queued = setTimeout(function () { upgrade(); }, 50);
    }).observe(document.documentElement, {
      childList: true, subtree: true, attributeFilter: ['title']
    });
  }
})();
