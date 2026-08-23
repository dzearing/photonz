/* Photonz mock · VIEW — the third motion component, beside dialog.js (overlays)
   and listfx.js (lists). It owns the entrance a whole screen makes, so no page
   writes its own page-transition ever again.

     PZ.view.enter(el)   play the standard view entrance on a region

   Every page in the site gets it for free: on load this plays once on the
   page's stage, so navigating between mock pages, and switching sections
   inside one, are visibly the same motion rather than two hand-made ones. */
(function () {
  var PZ = window.PZ || (window.PZ = {});

  function enter(el) {
    if (!el) return;
    // restart rather than ignore: clicking through the rail quickly should
    // animate each arrival, not silently drop the ones that land mid-flight
    el.classList.remove('view-enter');
    void el.offsetWidth;
    el.classList.add('view-enter');
  }

  // The page's own stage. `.stage` is the canonical page wrapper in the page
  // template (AGENTS.md); the fallbacks cover the shell pages that predate it.
  function stage() {
    return document.querySelector('main.stage') ||
           document.querySelector('.screen.on') ||
           document.querySelector('.proto') ||
           null;
  }

  PZ.view = { enter: enter, stage: stage };

  // one entrance per document load, matching what a section switch does
  enter(stage());
})();
