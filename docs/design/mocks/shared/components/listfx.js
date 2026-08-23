/* Photonz mock · LISTFX — the list choreography (UX-PATTERNS D11).
   One sequence for every list whose contents change: exits, then moves, then
   enters, never all at once, and interruptible without jumping.

   Usage: wrap the mutation instead of writing innerHTML directly.

     PZ.listfx(container, function () { container.innerHTML = rows(); });

   Every child that should be tracked carries `data-key`; children without one
   are ignored (they cannot be matched across a render, so they just appear).

   WHY IT IS BUILT THIS WAY

   The naive version measures where rows "were" from the old data and animates
   from there. That breaks the moment a second change lands mid-flight: rows
   snap back to their logical old position and start again, which is the jump
   this component exists to prevent. So the before-state is read from
   getBoundingClientRect DURING the previous animation, which reports the row
   where it currently IS. Retargeting from live geometry is what makes an
   interrupted list curve toward its new home instead of restarting. */
(function () {
  var PZ = window.PZ || (window.PZ = {});
  var D2 = 180, D3 = 240;                 // dur-2 / dur-3, matching the tokens
  var STANDARD = 'cubic-bezier(.4,0,.2,1)';
  var DECEL = 'cubic-bezier(0,0,.2,1)';
  var STAGGER = 24, STAGGER_MAX = 6;      // enter stagger, capped so a big batch stays quick
  var OVERLAP = 20;                       // phases overlap slightly so it reads as one motion

  function reduced() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  // Ghosts are clones, so they carry the same data-key as the row they stand
  // for. Counting one as a list item is how an interrupted sequence starts
  // animating a ghost of a ghost, so they are excluded here, once, rather than
  // guarded against at each call site.
  function keyed(container) {
    var map = new Map();
    Array.prototype.forEach.call(container.children, function (el) {
      if (!el.getAttribute || el.hasAttribute('data-lfx-ghost')) return;
      var k = el.getAttribute('data-key');
      if (k) map.set(k, el);
    });
    return map;
  }

  // Never re-choreograph something the user is working in: a focused field or a
  // held pointer inside the list means the list is furniture right now.
  function busy(container) {
    var a = document.activeElement;
    if (a && a !== document.body && container.contains(a)) return true;
    return container.__lfxPointerDown === true;
  }

  function listfx(container, mutate, opts) {
    opts = opts || {};
    if (!container || typeof mutate !== 'function') return;
    if (reduced() || busy(container)) { mutate(); return; }

    // ---- 1. measure the CURRENT on-screen geometry (mid-flight is fine) ----
    var before = new Map();
    keyed(container).forEach(function (el, k) { before.set(k, el.getBoundingClientRect()); });
    var outgoingNodes = [];
    var prev = keyed(container);

    // In-flight animations on real rows are abandoned, not finished: the new
    // state is the truth, and we already captured where everything visually is.
    // Ghosts are deliberately skipped, because an exit that is already playing
    // finishes (D11: in-flight exits do not resurrect).
    Array.prototype.forEach.call(container.children, function (el) {
      if (el.hasAttribute && el.hasAttribute('data-lfx-ghost')) return;
      if (el.getAnimations) el.getAnimations().forEach(function (a) { a.cancel(); });
    });

    // clone the rows that are about to disappear so they can fade in place
    var containerRect = container.getBoundingClientRect();

    // ---- 2. apply the change ----
    mutate();

    var now = keyed(container);
    var entering = [], moving = [];
    now.forEach(function (el, k) {
      var b = before.get(k);
      if (!b) { entering.push(el); return; }
      var a = el.getBoundingClientRect();
      var dy = b.top - a.top, dx = b.left - a.left;
      if (Math.abs(dy) > 0.5 || Math.abs(dx) > 0.5) moving.push({ el: el, dx: dx, dy: dy });
    });
    prev.forEach(function (el, k) {
      if (now.has(k)) return;
      var b = before.get(k);
      if (!b) return;
      outgoingNodes.push({ node: el.cloneNode(true), rect: b });
    });

    // ---- 3. phase one: exits fade out in place, alone, so the eye sees what left ----
    var exitMs = 0;
    if (outgoingNodes.length) {
      exitMs = D2;
      if (getComputedStyle(container).position === 'static') container.style.position = 'relative';
      var ghosts = [];
      outgoingNodes.forEach(function (o) {
        var g = o.node;
        g.setAttribute('data-lfx-ghost', '');
        g.style.position = 'absolute';
        g.style.left = (o.rect.left - containerRect.left) + 'px';
        g.style.top = (o.rect.top - containerRect.top) + 'px';
        g.style.width = o.rect.width + 'px';
        g.style.height = o.rect.height + 'px';
        g.style.margin = '0';
        g.style.pointerEvents = 'none';
        container.appendChild(g);
        ghosts.push(g);
        var drop = function () { if (g.parentNode) g.parentNode.removeChild(g); };
        g.animate([{ opacity: 1 }, { opacity: 0, transform: 'scale(.99)' }],
          { duration: D2, easing: STANDARD, fill: 'forwards' })
          .finished.then(drop, function () { /* cancelled */ });
        // a cancelled animation never resolves, so the timer is the authority:
        // a ghost must never outlive its own exit and become permanent litter
        setTimeout(drop, D2 + 60);
      });
      container.__lfxGhosts = ghosts;
    }

    // ---- 4. phase two: survivors travel to their new places ----
    var moveStart = Math.max(0, exitMs - OVERLAP);
    moving.forEach(function (m) {
      m.el.animate(
        [{ transform: 'translate(' + m.dx + 'px,' + m.dy + 'px)' }, { transform: 'none' }],
        { duration: D3, delay: moveStart, easing: STANDARD, fill: 'backwards' }
      );
    });

    // ---- 5. phase three: arrivals rise in last, staggered so a batch reads as arriving ----
    var enterStart = moveStart + (moving.length ? D3 - OVERLAP : 0);
    entering.forEach(function (el, i) {
      el.animate(
        [{ opacity: 0, transform: 'translateY(6px)' }, { opacity: 1, transform: 'none' }],
        { duration: D3, delay: enterStart + Math.min(i, STAGGER_MAX) * STAGGER, easing: DECEL, fill: 'backwards' }
      );
    });

    if (opts.onDone) setTimeout(opts.onDone, enterStart + D3 + STAGGER * Math.min(entering.length, STAGGER_MAX));
  }

  // a held pointer inside a list suspends choreography until it is released
  document.addEventListener('pointerdown', function (e) {
    var c = e.target.closest && e.target.closest('[data-lfx]');
    if (c) c.__lfxPointerDown = true;
  }, true);
  document.addEventListener('pointerup', function () {
    document.querySelectorAll('[data-lfx]').forEach(function (c) { c.__lfxPointerDown = false; });
  }, true);

  PZ.listfx = listfx;
})();
