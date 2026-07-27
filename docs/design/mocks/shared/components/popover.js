/* Photonz mock · toggled popovers (tool-bar overflow, group menus).
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
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
    // A MENU closes when you pick an item. A popover you OPERATE - the color
    // picker - must not vanish on the first click inside it, or dragging the
    // hue track would dismiss the thing you are dragging. `.cpick` and any
    // [data-sticky] popover stay open until you click outside or hit its
    // close button.
    var sticky = m.classList.contains('cpick') || m.hasAttribute('data-sticky');
    m.addEventListener('click', function (e) {
      e.stopPropagation();
      if (!sticky || e.target.closest('[data-cp-close]')) m.classList.remove('on');
    });
  });
  document.addEventListener('click', function () {
    all('.popover.pop.on').forEach(function (p) { p.classList.remove('on'); });
  });
})();
