/* Photonz mock · DIALOG — the overlay behaviour every surface shares.
   Implements UX-PATTERNS D11: one enter/exit choreography, soft dismiss on
   three gestures (Escape, scrim click, close control), and focus that moves in
   on open and returns on close. The CSS owns the motion; this owns the rules.

   Markup (nothing page-specific):
     <div class="dlg-scrim center" id="task-detail">
       <div class="dlg"> … <button data-dialog-close>Done</button> … </div>
     </div>
   Open it from anything: <button data-dialog-open="#task-detail">
   Or from code: PZ.dialog.open(el) / PZ.dialog.close(el, done)

   The one rule callers must respect: a dialog that is CLOSING is still in the
   DOM. Code that re-renders its container (the dashboard rebuilds its markup on
   every poll) must wait for the `done` callback, or the exit animation is
   thrown away and the overlay vanishes instantly. */
(function () {
  var PZ = window.PZ || (window.PZ = {});
  var reduced = function () {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  };
  // stack, so Escape closes the TOPMOST overlay rather than all of them
  var stack = [];

  function focusables(root) {
    return Array.prototype.slice.call(root.querySelectorAll(
      'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )).filter(function (el) { return el.offsetParent !== null; });
  }

  function open(scrim, opts) {
    if (!scrim || scrim.classList.contains('on')) return;
    opts = opts || {};
    scrim.classList.remove('closing');
    // the entrance must start from the closed state, so force a frame between
    // "in the DOM" and "on" or the browser collapses both into one paint
    void scrim.offsetWidth;
    scrim.classList.add('on');
    scrim.setAttribute('aria-hidden', 'false');
    var entry = { scrim: scrim, restore: document.activeElement, onClose: opts.onClose };
    stack.push(entry);
    // focus moves in, so the keyboard is inside the overlay and Escape is ours
    var surface = scrim.querySelector('.dlg');
    if (surface && opts.focus !== false) {
      var first = focusables(surface)[0];
      if (first) first.focus();
      else { surface.setAttribute('tabindex', '-1'); surface.focus(); }
    }
  }

  function close(scrim, done) {
    if (!scrim || !scrim.classList.contains('on')) { if (done) done(); return; }
    var entry = null;
    for (var i = stack.length - 1; i >= 0; i--) {
      if (stack[i].scrim === scrim) { entry = stack.splice(i, 1)[0]; break; }
    }
    // focus leaves before the surface starts fading: focus must never sit on
    // something that is disappearing
    if (entry && entry.restore && entry.restore.focus) {
      try { entry.restore.focus(); } catch (e) { /* the opener may be gone */ }
    }
    var finish = function () {
      scrim.classList.remove('on', 'closing');
      scrim.setAttribute('aria-hidden', 'true');
      if (entry && entry.onClose) entry.onClose();
      if (done) done();
    };
    if (reduced()) return finish();
    scrim.classList.add('closing');
    var surface = scrim.querySelector('.dlg');
    var settled = false;
    var end = function () { if (settled) return; settled = true; finish(); };
    if (surface) surface.addEventListener('transitionend', end, { once: true });
    // a transitionend can be missed (display changes, interrupted transitions),
    // so the timer is the authority and the event is just the fast path
    setTimeout(end, 260);
  }

  function top() { return stack.length ? stack[stack.length - 1] : null; }

  // ---- the three dismiss gestures ----
  document.addEventListener('click', function (e) {
    var opener = e.target.closest && e.target.closest('[data-dialog-open]');
    if (opener) {
      var sel = opener.getAttribute('data-dialog-open');
      var target = sel && document.querySelector(sel);
      if (target) { e.preventDefault(); open(target); }
      return;
    }
    var closer = e.target.closest && e.target.closest('[data-dialog-close]');
    if (closer) {
      var scrim = closer.closest('.dlg-scrim');
      if (scrim) { e.preventDefault(); close(scrim); }
      return;
    }
    // scrim click: only when the press landed on the scrim ITSELF. A click that
    // merely bubbled from inside the surface is not a dismiss.
    var t = top();
    if (t && e.target === t.scrim) close(t.scrim);
  });

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    var t = top();
    if (!t) return;
    e.stopPropagation();   // the topmost overlay consumes it; nothing below closes
    close(t.scrim);
  }, true);

  PZ.dialog = { open: open, close: close, top: top };
})();
