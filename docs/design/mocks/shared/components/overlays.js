/* Photonz mock · slide-down overlays (the capture-history front door).
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
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
})();
