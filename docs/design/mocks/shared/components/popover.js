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
    var native = btn.matches('button,a[href]');
    /* A trigger drawn as a span is a button in every way but the one that
       matters to a keyboard: give it the role, the tab stop and the keys. */
    if (!native) {
      if (!btn.hasAttribute('role')) btn.setAttribute('role', 'button');
      if (!btn.hasAttribute('tabindex')) btn.setAttribute('tabindex', '0');
    }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var on = !m.classList.contains('on');
      all('.popover.pop.on').forEach(function (p) { if (p !== m) p.classList.remove('on'); });
      m.classList.toggle('on', on);
      btn.setAttribute('aria-expanded', on ? 'true' : 'false');
      if (on) {
        m.__opener = btn;
        // Opened from the keyboard, the keyboard goes in with it. A popover you
        // operate (the color picker) places its own focus, so it is left alone.
        if (btn.matches(':focus-visible') && !m.classList.contains('cpick') && PZ.menu) PZ.menu.enter(m);
      }
    });
    btn.addEventListener('keydown', function (e) {
      if (e.target !== btn) return;
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (!m.classList.contains('on')) btn.click();
        if (PZ.menu) PZ.menu.enter(m);
      } else if (e.key === 'Escape' && m.classList.contains('on')) {
        e.preventDefault();
        if (PZ.menu) PZ.menu.close(m);
      } else if (!native && (e.key === 'Enter' || e.key === ' ')) {
        e.preventDefault();
        btn.click();
      }
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
