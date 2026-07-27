/* Photonz mock · zoom slider + scrubber readouts.
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
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
})();
