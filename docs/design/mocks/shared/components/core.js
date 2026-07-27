/* Photonz mock · shared page behaviours — CORE.
   The preamble every page needs (theme sync from the iframe shell, cross-page
   nav, collapsible inspector sections, subtabs, the legacy step slideshow) plus
   the four helpers every other component uses. Those are published on window.PZ
   because the components are separate files now; nothing else is shared.
   See shared/components/README.md. */
(function () {
  // Theme: the shell stamps data-theme; also honor prefers-color-scheme by default.
  window.addEventListener('message', function (e) {
    var d = e.data || {};
    if (d.photonzTheme) document.documentElement.setAttribute('data-theme', d.photonzTheme);
  });

  // Cross-page nav: any [data-target] asks the shell to load that page.
  document.querySelectorAll('[data-target]').forEach(function (el) {
    el.style.cursor = 'pointer';
    el.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      var id = el.getAttribute('data-target');
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ photonzNav: id }, '*');
      }
    });
  });

  // Inspector groups: any .section that has a .sec-h header becomes a collapsible
  // disclosure (chevron + click-to-collapse) so panels read as grouped, not a wall.
  document.querySelectorAll('.section > .sec-h').forEach(function (h) {
    var sec = h.parentNode;
    sec.classList.add('grp');
    if (!h.querySelector('.chev')) {
      var c = document.createElement('span');
      c.className = 'chev ic ic-chevron-down';
      h.insertBefore(c, h.firstChild);
    }
    h.addEventListener('click', function (e) {
      if (e.target.closest('[data-target]')) return; // let cross-links do their thing
      sec.classList.toggle('closed');
    });
  });

  // Subtabs (e.g. agent A/B/C): .subtab[data-alt] toggles matching .alt.
  var subtabs = [].slice.call(document.querySelectorAll('.subtab'));
  subtabs.forEach(function (t) {
    t.addEventListener('click', function () {
      subtabs.forEach(function (x) { x.classList.toggle('on', x === t); });
      document.querySelectorAll('.alt').forEach(function (a) {
        a.classList.toggle('on', a.id === t.getAttribute('data-alt'));
      });
    });
  });

  // Walkthrough stepper: .wstep sequence with .wprev/.wnext/.wdots i/.wlabel.
  // Step titles are read from each step's `.wcap .tx b` (or a data-title override).
  var wsteps = [].slice.call(document.querySelectorAll('.wstep'));
  if (wsteps.length) {
    var wdots = [].slice.call(document.querySelectorAll('.wdots i'));
    var wprev = document.querySelector('.wprev');
    var wnext = document.querySelector('.wnext');
    var wlabel = document.querySelector('.wlabel');
    var titles = wsteps.map(function (s) {
      if (s.getAttribute('data-title')) return s.getAttribute('data-title');
      var b = s.querySelector('.wcap .tx b');
      return b ? b.textContent.replace(/\.$/, '') : '';
    });
    var i = 0;
    var show = function (n) {
      i = Math.max(0, Math.min(wsteps.length - 1, n));
      wsteps.forEach(function (s, k) { s.classList.toggle('on', k === i); });
      wdots.forEach(function (d, k) { d.classList.toggle('on', k === i); });
      if (wlabel) wlabel.innerHTML = 'Step <b>' + (i + 1) + '</b> / ' + wsteps.length + ' · ' + titles[i];
      if (wprev) wprev.disabled = i === 0;
      if (wnext) wnext.disabled = i === wsteps.length - 1;
    };
    if (wprev) wprev.addEventListener('click', function () { show(i - 1); });
    if (wnext) wnext.addEventListener('click', function () { show(i + 1); });
    wdots.forEach(function (d, k) { d.addEventListener('click', function () { show(k); }); });
    show(0);
  }

  /* ============================================================
     THE SCALABLE DOCK SYSTEM (PRODUCT-MODEL.md §4b)
     Progressive enhancement for the shell vocabulary defined in
     photonz-ds.css: collapse, resize, scroll, overflow, overlay.
     Everything below is guarded, so a page that uses none of it is a
     no-op. Nothing here owns state a page cannot also set in markup.
     ============================================================ */

  // Keep in sync with the @container breakpoints in photonz-ds.css.
  var NARROW = 880;

  function winOf(el) { return el.closest('.win') || document.body; }
  function isNarrow(el) { return winOf(el).clientWidth <= NARROW; }
  function all(sel, root) { return [].slice.call((root || document).querySelectorAll(sel)); }

  // Published for the component files, which are separate scripts now.
  window.PZ = { all: all, winOf: winOf, isNarrow: isNarrow, NARROW: NARROW };
})();
