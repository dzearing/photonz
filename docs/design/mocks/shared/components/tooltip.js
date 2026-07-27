/* ============================================================
   TOOLTIP — behaviour
   ============================================================
   One floating node for the whole document, moved and re-labelled as needed,
   rather than one node per trigger. See tooltip.css for the visual contract.

   Contract:
     data-tip="Label"                     the text
     data-tip="Label|⌘K"                  optional shortcut, shown quieter
     data-tip-side="top|bottom|left|right" default "top", flips if it would clip

   Shows on hover and on keyboard focus (the native `title` never does the
   latter, which is why every icon-only control in the shell was unreachable to
   explain without a mouse). Hides on leave, blur, Escape, scroll, or pointer
   down — a label must never outlive the thing it labels.

   ADOPTION: any element that has a `title` and no `data-tip` is upgraded
   automatically and its `title` is removed, so the browser does not also draw
   its own. That is how ~700 existing title= controls get the styled one without
   editing 51 pages. */
(function () {
  if (window.__photonzTip) return;           // idempotent: safe to run twice
  window.__photonzTip = true;

  var DELAY_IN = 380, DELAY_OUT = 60, GAP = 8, EDGE = 6;
  var node = null, timer = null, current = null;

  function ensure() {
    if (node) return node;
    node = document.createElement('div');
    node.className = 'tip';
    node.setAttribute('role', 'tooltip');
    document.body.appendChild(node);
    return node;
  }

  function label(el) {
    var raw = el.getAttribute('data-tip') || '';
    var bits = raw.split('|');
    var out = document.createTextNode(bits[0].trim()).textContent
      .replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; });
    if (bits[1]) out += '<span class="k">' + bits[1].trim() + '</span>';
    return out;
  }

  function place(el) {
    var t = ensure();
    var side = el.getAttribute('data-tip-side') || 'top';
    var r = el.getBoundingClientRect();
    t.setAttribute('data-side', side);
    t.style.left = '0px';
    t.style.top = '0px';
    var b = t.getBoundingClientRect();
    var vw = window.innerWidth, vh = window.innerHeight;

    // flip to the opposite side when the preferred one would clip
    if (side === 'top' && r.top - b.height - GAP < EDGE) side = 'bottom';
    else if (side === 'bottom' && r.bottom + b.height + GAP > vh - EDGE) side = 'top';
    else if (side === 'left' && r.left - b.width - GAP < EDGE) side = 'right';
    else if (side === 'right' && r.right + b.width + GAP > vw - EDGE) side = 'left';
    t.setAttribute('data-side', side);

    var x, y;
    if (side === 'top' || side === 'bottom') {
      x = r.left + r.width / 2 - b.width / 2;
      y = side === 'top' ? r.top - b.height - GAP : r.bottom + GAP;
    } else {
      x = side === 'left' ? r.left - b.width - GAP : r.right + GAP;
      y = r.top + r.height / 2 - b.height / 2;
    }
    // keep it on screen, then walk the beak back to the trigger's centre so it
    // still points at what it labels instead of at the tooltip's own middle
    var cx = r.left + r.width / 2;
    x = Math.max(EDGE, Math.min(x, vw - b.width - EDGE));
    y = Math.max(EDGE, Math.min(y, vh - b.height - EDGE));
    t.style.setProperty('--tip-x', (cx - x) + 'px');
    t.style.left = Math.round(x) + 'px';
    t.style.top = Math.round(y) + 'px';
  }

  function show(el) {
    var t = ensure();
    t.innerHTML = label(el);
    current = el;
    place(el);
    t.classList.add('on');
  }

  function hide() {
    clearTimeout(timer);
    current = null;
    if (node) node.classList.remove('on');
  }

  function trigger(e) {
    var el = e.target.closest && e.target.closest('[data-tip]');
    if (!el || el === current) return;
    clearTimeout(timer);
    var now = !!(node && node.classList.contains('on'));   // already open: swap
    timer = setTimeout(function () { show(el); }, now ? DELAY_OUT : DELAY_IN);
  }

  document.addEventListener('pointerover', trigger);
  document.addEventListener('focusin', trigger);
  document.addEventListener('pointerout', function (e) {
    if (current && e.target.closest && e.target.closest('[data-tip]') === current) hide();
  });
  document.addEventListener('focusout', hide);
  document.addEventListener('pointerdown', hide);
  document.addEventListener('scroll', hide, true);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') hide(); });

  /* Upgrade native title= to the styled tooltip. Runs once now and again
     whenever the shell component adds controls (it sets title= on harvested
     buttons), so nothing has to know about tooltips to get one. */
  function upgrade(root) {
    var els = (root || document).querySelectorAll('[title]:not([data-tip])');
    [].slice.call(els).forEach(function (el) {
      var t = el.getAttribute('title');
      if (!t) return;
      // "Split at playhead (B)" / "Ask the agent, or run a command (⌘K)"
      var m = t.match(/^(.*?)\s*[（(]([^)）]{1,12})[)）]\s*$/);
      el.setAttribute('data-tip', m ? m[1] + '|' + m[2] : t);
      el.removeAttribute('title');
    });
  }
  window.photonzUpgradeTips = upgrade;
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { upgrade(); });
  } else {
    upgrade();
  }
  // Pages add controls after load (walkthrough steps swap panels, the shell
  // component builds chrome). Watch rather than guess at timing: a control that
  // appears in step 6 gets the same tooltip as one that was there at load.
  if (window.MutationObserver) {
    var pending = null;
    new MutationObserver(function () {
      clearTimeout(pending);
      pending = setTimeout(function () { upgrade(); }, 50);
    }).observe(document.documentElement, {
      childList: true, subtree: true, attributeFilter: ['title']
    });
  }
})();
