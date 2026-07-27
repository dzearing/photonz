/* Photonz mock · capture toasts (PRODUCT-MODEL §4e.3).
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
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
