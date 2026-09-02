/* Photonz mock · shared page behaviours — CORE.
   The preamble every page needs (theme sync from the iframe shell, cross-page
   nav, collapsible inspector sections, subtabs, the legacy step slideshow) plus
   the helpers every other component uses. Those are published on window.PZ
   because the components are separate files now; nothing else is shared.
   See shared/components/README.md. */
(function () {
  // Theme: the shell stamps data-theme; also honor prefers-color-scheme by default.
  window.addEventListener('message', function (e) {
    var d = e.data || {};
    if (d.photonzTheme) document.documentElement.setAttribute('data-theme', d.photonzTheme);
  });

  function all(sel, root) { return [].slice.call((root || document).querySelectorAll(sel)); }

  /* ============================================================
     KEYBOARD REACH
     A menu row in the study is a <div>. A card that opens another page is
     a <div>. A bold word that jumps you somewhere is a <b>. The mouse
     reaches every one of them because the click is bound here, so the pages
     look finished; Tab reaches none of them, and a screen reader does not
     know they exist, because a div with a click listener is still a div.

     This is the one place that pays that debt, so a page never has to:
       · a [data-target] that is not a real button or link gets role="link",
         a tab stop, and Enter;
       · a collapsible section header gets role="button", a tab stop,
         aria-expanded, and Enter/Space;
       · every .menuitem is a real menu item: the MENU is one tab stop, the
         arrow keys walk its rows, Enter/Space picks, Escape closes a popover
         menu and hands focus back to whatever opened it. One stop per menu
         rather than one per row, because a page can hold forty rows and a
         keyboard user should not pay forty Tabs to get past them.

     Everything here is a sweep that runs at load and again when the DOM
     changes, because the shell, the dock and the segmented control all build
     rows after this file has run; a control that appears later gets the
     same treatment as one that was there at load.
     ============================================================ */
  var NATIVE = 'button,input,select,textarea,summary,a[href]';
  var ITEM = '.menuitem';
  var MENU = '.menu,[role="menu"],.popover';

  function isNative(el) { return el.matches(NATIVE); }
  function enabled(el) {
    return !(el.disabled || el.classList.contains('disabled') || el.getAttribute('aria-disabled') === 'true');
  }
  function shown(el) { return el.offsetParent !== null || getComputedStyle(el).position === 'fixed'; }

  /* Enter (and Space, for anything that is not a link) presses the element
     the key landed on. Only that element: a card can hold its own buttons,
     and a key pressed on one of those must not also open the card. */
  function pressable(el, spaceToo) {
    if (el.dataset.pzKeyed) return;
    el.dataset.pzKeyed = '1';
    el.addEventListener('keydown', function (e) {
      if (e.target !== el) return;
      var space = spaceToo || el.getAttribute('role') !== 'link';
      if (e.key === 'Enter' || (space && e.key === ' ')) { e.preventDefault(); el.click(); }
    });
  }

  // Cross-page nav: any [data-target] asks the shell to load that page.
  function upgradeLinks(root) {
    all('[data-target]', root).forEach(function (el) {
      if (!el.dataset.pzNav) {
        el.dataset.pzNav = '1';
        el.style.cursor = 'pointer';
        el.addEventListener('click', function (e) {
          e.preventDefault();
          e.stopPropagation();
          var id = el.getAttribute('data-target');
          if (window.parent && window.parent !== window) {
            window.parent.postMessage({ photonzNav: id }, '*');
          }
        });
      }
      if (el.classList.contains('menuitem') || isNative(el)) return; // a row belongs to its menu
      if (!el.hasAttribute('role')) el.setAttribute('role', 'link');
      if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '0');
      pressable(el);
    });
  }

  // Inspector groups: any .section that has a .sec-h header becomes a collapsible
  // disclosure (chevron + click-to-collapse) so panels read as grouped, not a wall.
  function upgradeSections(root) {
    all('.section > .sec-h', root).forEach(function (h) {
      if (h.dataset.pzSec) return;
      h.dataset.pzSec = '1';
      var sec = h.parentNode;
      sec.classList.add('grp');
      if (!h.querySelector('.chev')) {
        var c = document.createElement('span');
        c.className = 'chev ic ic-chevron-down';
        h.insertBefore(c, h.firstChild);
      }
      var sync = function () { h.setAttribute('aria-expanded', sec.classList.contains('closed') ? 'false' : 'true'); };
      h.addEventListener('click', function (e) {
        if (e.target.closest('[data-target]')) return; // let cross-links do their thing
        sec.classList.toggle('closed');
        sync();
      });
      if (!isNative(h)) {
        if (!h.hasAttribute('role')) h.setAttribute('role', 'button');
        if (!h.hasAttribute('tabindex')) h.setAttribute('tabindex', '0');
        pressable(h, true);
      }
      sync();
    });
  }

  /* ---- menus ---- */
  function menuOf(el) { return el.closest(MENU); }
  function rows(m, onlyShown) {
    return all(ITEM, m).filter(function (it) {
      return menuOf(it) === m && enabled(it) && (!onlyShown || shown(it));
    });
  }
  /* Roving tab stop: the current row is the menu's one Tab stop. */
  function rove(m, cur) {
    all(ITEM, m).forEach(function (it) {
      if (menuOf(it) === m) it.setAttribute('tabindex', it === cur ? '0' : '-1');
    });
  }
  function current(m) {
    var r = rows(m);
    return r.filter(function (it) { return it.classList.contains('on'); })[0] || r[0] || null;
  }
  function ensureStop(m) {
    var has = all(ITEM, m).some(function (it) { return menuOf(it) === m && it.getAttribute('tabindex') === '0'; });
    if (!has) rove(m, current(m));
  }

  /* Whatever opened a popover is where focus goes back to. popover.js and
     dock.js record the trigger on open; a menu with no recorded trigger falls
     back to the [data-menu] that points at it, then to the last thing focused
     outside any popover. */
  var lastOutside = null;
  document.addEventListener('focusin', function (e) {
    if (e.target && e.target.closest && !e.target.closest('.popover')) lastOutside = e.target;
  });
  function opener(m) {
    return m.__opener || (m.id && document.querySelector('[data-menu="#' + m.id + '"]')) || lastOutside;
  }
  function closeMenu(m, refocus) {
    if (!m.classList.contains('pop') || !m.classList.contains('on')) return false;
    m.classList.remove('on');
    var o = opener(m);
    if (o) {
      if (o.hasAttribute('aria-expanded')) o.setAttribute('aria-expanded', 'false');
      if (refocus !== false && o.focus) o.focus();
    }
    return true;
  }
  /* Move the keyboard into a menu: the checked row if it has one, else the first. */
  function enterMenu(m) {
    bindMenu(m);
    var cur = rows(m, true)[0] || null;
    var on = rows(m, true).filter(function (it) { return it.classList.contains('on'); })[0];
    cur = on || cur;
    if (!cur) return false;
    rove(m, cur);
    cur.focus();
    return true;
  }

  function bindMenu(m) {
    if (m.dataset.pzMenu) { ensureStop(m); return; }
    m.dataset.pzMenu = '1';
    if (!m.hasAttribute('role')) m.setAttribute('role', 'menu');
    ensureStop(m);
    m.addEventListener('focusin', function (e) {
      var it = e.target.closest(ITEM);
      if (it && menuOf(it) === m) rove(m, it);
    });
    m.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        if (closeMenu(m)) { e.preventDefault(); e.stopPropagation(); }
        return;
      }
      var it = e.target.closest(ITEM);
      if (!it || menuOf(it) !== m) return;
      var list = rows(m, true), i = list.indexOf(it), next = null;
      if (e.key === 'ArrowDown') next = list[i + 1] || list[0];
      else if (e.key === 'ArrowUp') next = list[i - 1] || list[list.length - 1];
      else if (e.key === 'Home') next = list[0];
      else if (e.key === 'End') next = list[list.length - 1];
      else if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        it.click();
        // a popover menu closes itself on a pick; the keyboard must not be
        // left standing on a row that is no longer displayed
        if (m.classList.contains('pop') && !m.classList.contains('on')) {
          var o = opener(m);
          if (o && o.focus) o.focus();
        }
        return;
      } else if (e.key === 'Tab') {
        // Tab leaves the menu, so a popover menu should not stay open behind
        // it; focus returns to the trigger and the Tab then moves on from there
        closeMenu(m);
        return;
      } else return;
      if (next) { e.preventDefault(); next.focus(); }
    });
  }

  function upgradeMenus(root) {
    var touched = [];
    all(ITEM, root).forEach(function (it) {
      var m = menuOf(it);
      if (!m || m.getAttribute('data-keys') === 'own') return; // component runs its own keys
      if (!it.hasAttribute('role')) it.setAttribute('role', 'menuitem');
      if (it.classList.contains('disabled') && !it.hasAttribute('aria-disabled')) it.setAttribute('aria-disabled', 'true');
      if (!it.dataset.pzItem) {
        it.dataset.pzItem = '1';
        if (!it.hasAttribute('tabindex')) it.setAttribute('tabindex', '-1');
      }
      if (touched.indexOf(m) < 0) touched.push(m);
    });
    touched.forEach(bindMenu);
  }

  function upgrade(root) {
    upgradeLinks(root);
    upgradeSections(root);
    upgradeMenus(root);
  }
  upgrade(document);
  if (window.MutationObserver) {
    /* Trailing debounce with a ceiling, same reason as tooltip.js: a busy
       page never falls quiet, and a sweep that waits for quiet never runs. */
    var MAX_WAIT = 200, queued = null, since = 0;
    new MutationObserver(function () {
      clearTimeout(queued);
      if (!since) since = Date.now();
      if (Date.now() - since >= MAX_WAIT) { since = 0; upgrade(document); return; }
      queued = setTimeout(function () { since = 0; upgrade(document); }, 50);
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  /* Effect / adjustment enable switches. `.efx .en` is a real BUTTON on every
     page — a span cannot be pressed, focused or announced, and half the effect
     stacks in the study had shipped as inert spans. The press itself is the
     same everywhere, so it lives here: flip `.off`, keep aria-pressed honest,
     and stop the click before the row's own [data-target] treats it as "open
     that page". A page that paints the result adds its own listener on the
     same button and reads the class afterwards. */
  document.querySelectorAll('.efx button.en').forEach(function (sw) {
    sw.addEventListener('click', function (e) {
      e.stopPropagation();
      var on = !sw.classList.toggle('off');
      sw.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
  });

  // Subtabs (e.g. agent A/B/C): .subtab[data-alt] toggles matching .altpane.
  var subtabs = [].slice.call(document.querySelectorAll('.subtab'));
  subtabs.forEach(function (t) {
    t.addEventListener('click', function () {
      subtabs.forEach(function (x) { x.classList.toggle('on', x === t); });
      document.querySelectorAll('.altpane').forEach(function (a) {
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

  // Published for the component files, which are separate scripts now.
  // `menu` is the keyboard contract for anything that opens a menu: call
  // enter(m) after opening from the keyboard, close(m) to dismiss and hand
  // focus back. A component that walks its own rows marks the menu
  // data-keys="own" and is left alone.
  window.PZ = {
    all: all, winOf: winOf, isNarrow: isNarrow, NARROW: NARROW,
    menu: { enter: enterMenu, close: closeMenu, upgrade: upgradeMenus }
  };
})();
