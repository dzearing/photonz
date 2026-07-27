/* Photonz mock · exclusive selection inside a container ([data-radio]).
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
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
})();
