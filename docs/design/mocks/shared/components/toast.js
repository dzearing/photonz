/* Photonz mock · capture toasts (PRODUCT-MODEL §4e.3).
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
  /* ---- 10 · capture toasts (PRODUCT-MODEL §4e.3) ----
     [data-toast="#someToast"] fires another copy of that .ctoast into the
     .ctoast-stack it already lives in, so a page can demonstrate the real
     behavior: captures STACK, newest in the corner, and each one is
     transient — it leaves on its own. Hovering a card pins it and shows
     its .cact pill; the Dismiss button in it ([data-ctoast="dismiss"])
     sends that card away early, which is the one way a person ends a
     toast by hand. The pointed-at .ctoast stays put on the page (Dismiss
     only hides it, so a walkthrough can show it again); only the clones
     come and go. */
  var TOAST_HOLD = 4200, TOAST_OUT = 240;
  function leave(card) {
    if (!card || card.classList.contains('out')) return;
    card.classList.add('out');
    setTimeout(function () {
      if (!card.parentNode) return;
      if (card.id) { card.classList.remove('out'); card.classList.add('wt-off'); }
      else card.parentNode.removeChild(card);
    }, TOAST_OUT);
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('.ctoast [data-ctoast="dismiss"]');
    if (!b) return;
    e.preventDefault();
    leave(b.closest('.ctoast'));
  });
  all('[data-toast]').forEach(function (btn) {
    var src = document.querySelector(btn.getAttribute('data-toast'));
    if (!src) return;
    var stack = src.closest('.ctoast-stack');
    if (!stack) return;
    btn.addEventListener('click', function () {
      var c = src.cloneNode(true);
      c.removeAttribute('id');
      c.classList.remove('wt-off', 'out');
      all('[id]', c).forEach(function (n) { n.removeAttribute('id'); });
      stack.appendChild(c);
      setTimeout(function () { leave(c); }, TOAST_HOLD);
    });
  });
})();
