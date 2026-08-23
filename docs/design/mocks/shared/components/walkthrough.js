/* Photonz mock · operated walkthroughs (PRODUCT-MODEL.md §4d).
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
  /* ============================================================
     8 · OPERATED WALKTHROUGHS (PRODUCT-MODEL.md §4d)

     ONE app screen, rendered once, that is DRIVEN. Nothing here
     re-renders the shell: a step declares STATE with data attributes,
     ds.js resets the stage to its authored baseline and replays steps
     0..n, then anchors a click cue over the REAL target element.

       <div class="wt">
         <div class="wt-stage"> …one .win.tall.cq shell… </div>
         <ol class="wt-steps">
           <li class="wt-step" data-title="…" data-cue="#tBlade"
               data-cue-label="Click the Blade tool" data-cue-place="top"
               data-tool="#tBlade" data-open="#gLibrary" data-scope="media"
               data-select="#lrClipA" data-show="#cvFrame" …>
             <div class="wt-cap vid">
               <span class="wt-n">3</span>
               <p class="wt-do">the <b>Blade</b> tool</p>
               <p class="wt-where">the floating tool bar</p>
               <p class="wt-res">Blade is the active tool.</p>
             </div>
           </li>
         </ol>
         <div class="wbar"> .wprev · .wdots · .wlabel · .wt-reset · .wnext </div>
       </div>

     Step directives (all optional, all resolved INSIDE the stage):
       data-tool="#id"           exclusive .on inside that tool's .tstrip
       data-open="#a,#b"         un-collapse those .dgrp groups
       data-collapse="#a,#b"     collapse those .dgrp groups
       data-dock="open|closed|overlay"   the .edit.lean dock state
       data-scope="media"        Library scope: .on the [data-scope] button,
                                 reveal [data-scope-body="media"], set
                                 [data-scope-label] text
       data-activate="#id"       exclusive .on among that element's
                                 like-classed siblings (workspace switcher)
       data-select="#a,#b"       exclusive selection across .lrow/.libtile/
                                 .filmcard/.clip/.editpt/.xband. Every listed
                                 target lights, so ONE step can mark the same
                                 selection in every surface that shows it
                                 (found-selection: the surfaces must agree).
                                 Class comes from the step's data-select-class,
                                 else the target's data-sel-class, else "sel"
       data-show / data-hide     drop or add .wt-off (reveal canvas content,
                                 selection rings, empty states, badges)
       data-sheet-open/-shut     the .sheet.down overlay (history)
       data-pop="#id"            open a .popover.pop (so a cue can sit on a
                                 real menu item)
       data-time="on|off"        the document has time: transport + timeline
       data-set="#id=text|#id2=text"     set a readout's text
       data-css="#id=width:26%"  inline geometry (a trimmed clip, a bar)
       data-class="#id=blk|#id2=-caret"  add a variant class ("-x" removes it)
       data-cue / data-cue-label / data-cue-place    the click cue

     Rule of thumb for authors: anchor the cue on a control that still
     EXISTS after this step's state applies. A step that cannot be
     expressed as a real click on a real surface is not a usage step.
     ============================================================ */
  all('.wt').forEach(function (wt) {
    var stage = wt.querySelector('.wt-stage') || wt.querySelector('.win');
    var steps = all('.wt-step', wt);
    if (!stage || !steps.length) return;

    function list(v) {
      if (!v) return [];
      var s = v.split(',').map(function (x) { return x.trim(); }).filter(Boolean).join(',');
      return s ? all(s, stage) : [];
    }
    function pairs(v, fn) {
      (v || '').split('|').forEach(function (p) {
        var k = p.indexOf('=');
        if (k < 0) return;
        var el = stage.querySelector(p.slice(0, k).trim());
        if (el) fn(el, p.slice(k + 1));
      });
    }

    /* ---- baseline snapshot, so every step replay is deterministic ----
       class + the dock attribute cover every state directive; text is
       snapshotted only for the elements some step actually rewrites. */
    var snapClass = all('*', stage).map(function (el) {
      return [el, el.getAttribute('class')];
    });
    var snapDock = all('.edit.lean', stage).map(function (el) {
      return [el, el.getAttribute('data-dock') || 'open'];
    });
    var snapText = [], snapStyle = [];
    function remember(store, el, val) {
      for (var k = 0; k < store.length; k++) if (store[k][0] === el) return;
      store.push([el, val]);
    }
    steps.forEach(function (s) {
      pairs(s.getAttribute('data-set'), function (el) { remember(snapText, el, el.textContent); });
      pairs(s.getAttribute('data-css'), function (el) { remember(snapStyle, el, el.getAttribute('style')); });
    });
    function resetStage() {
      snapClass.forEach(function (r) {
        if (r[1] === null) r[0].removeAttribute('class'); else r[0].setAttribute('class', r[1]);
      });
      snapDock.forEach(function (r) { r[0].setAttribute('data-dock', r[1]); });
      snapText.forEach(function (r) { r[0].textContent = r[1]; });
      snapStyle.forEach(function (r) {
        if (r[1] === null) r[0].removeAttribute('style'); else r[0].setAttribute('style', r[1]);
      });
    }

    function applyStep(s) {
      var v;

      v = s.getAttribute('data-tool');
      if (v) {
        var t = stage.querySelector(v);
        if (t) {
          all('.tool', t.closest('.tstrip') || t.parentNode || stage).forEach(function (x) {
            x.classList.toggle('on', x === t);
          });
        }
      }

      list(s.getAttribute('data-open')).forEach(function (g) {
        g.classList.remove('collapsed');
        var h = g.querySelector('.dgrp-h');
        if (h) h.setAttribute('aria-expanded', 'true');
      });
      list(s.getAttribute('data-collapse')).forEach(function (g) {
        g.classList.add('collapsed');
        var h = g.querySelector('.dgrp-h');
        if (h) h.setAttribute('aria-expanded', 'false');
      });

      v = s.getAttribute('data-dock');
      if (v) all('.edit.lean', stage).forEach(function (sh) { sh.setAttribute('data-dock', v); });

      v = s.getAttribute('data-scope');
      if (v) {
        var name = v;
        all('[data-scope]', stage).forEach(function (b) {
          var on = b.getAttribute('data-scope') === v;
          b.classList.toggle('on', on);
          if (on) name = b.getAttribute('data-scope-name') || b.textContent.trim();
        });
        all('[data-scope-body]', stage).forEach(function (p) {
          p.classList.toggle('wt-off', p.getAttribute('data-scope-body') !== v);
        });
        all('[data-scope-label]', stage).forEach(function (l) { l.textContent = name; });
      }

      // exclusive .on among an element's like-classed siblings (workspace
      // switcher segments, seg buttons, anything that is one-of-N)
      list(s.getAttribute('data-activate')).forEach(function (t) {
        if (!t.parentNode) return;
        // siblings are "like-classed" by the target's first REAL class, never
        // by `on` itself (the currently-selected segment carries it, which
        // would have matched only itself). A bare <button> in a .seg has no
        // class at all, so fall back to the tag: that is what one-of-N means.
        var cls = (t.getAttribute('class') || '').split(/\s+/).filter(function (c) {
          return c && c !== 'on';
        })[0];
        [].slice.call(t.parentNode.children).forEach(function (x) {
          var like = cls ? x.classList.contains(cls) : x.tagName === t.tagName;
          if (like) x.classList.toggle('on', x === t);
        });
      });

      v = s.getAttribute('data-select');
      if (v) {
        all('.lrow,.libtile,.filmcard,.clip,.editpt,.xband', stage).forEach(function (r) {
          r.classList.remove('sel', 'selc');
        });
        list(v).forEach(function (pick) {
          pick.classList.add(s.getAttribute('data-select-class') ||
            pick.getAttribute('data-sel-class') || 'sel');
        });
      }

      list(s.getAttribute('data-show')).forEach(function (e) { e.classList.remove('wt-off'); });
      list(s.getAttribute('data-hide')).forEach(function (e) { e.classList.add('wt-off'); });

      // a variant class the step turns on (a dip-to-black marker, a frozen
      // clip). The baseline class snapshot takes it off again on replay, so
      // this stays declarative like everything else.
      pairs(s.getAttribute('data-class'), function (el, cls) {
        cls.split(/\s+/).forEach(function (c) {
          if (!c) return;
          if (c.charAt(0) === '-') el.classList.remove(c.slice(1));  // "-caret" takes it off again
          else el.classList.add(c);
        });
      });

      list(s.getAttribute('data-sheet-open')).forEach(function (sh) {
        sh.classList.add('on'); sh.setAttribute('aria-hidden', 'false');
      });
      list(s.getAttribute('data-sheet-shut')).forEach(function (sh) {
        sh.classList.remove('on'); sh.setAttribute('aria-hidden', 'true');
      });

      /* A menu is transient, so it closes itself. Steps replay cumulatively
         (0..n), which used to leave a popover opened in step 2 still hanging
         open in step 8. Every step shuts every .popover.pop in the stage and
         then opens only the one it declares; a menu that should stay open
         across two steps declares data-pop on both. */
      all('.popover.pop', stage).forEach(function (p) { p.classList.remove('on'); });
      list(s.getAttribute('data-pop')).forEach(function (p) { p.classList.add('on'); });

      v = s.getAttribute('data-time');
      if (v) {
        all('.transport,.timeline', stage).forEach(function (e) {
          e.classList.toggle('wt-off', v !== 'on');
        });
      }

      pairs(s.getAttribute('data-set'), function (el, text) { el.textContent = text; });
      pairs(s.getAttribute('data-css'), function (el, css) { el.style.cssText += ';' + css; });
    }

    /* ---- the click cue ---- */
    var cue = document.createElement('div');
    cue.className = 'wt-cue';
    cue.innerHTML = '<span class="pulse"></span><span class="ring"></span><span class="lb"></span>';
    wt.appendChild(cue);
    var cueRing = cue.querySelector('.ring');
    var cuePulse = cue.querySelector('.pulse');
    var cueLb = cue.querySelector('.lb');

    // bring the target inside view of whatever group scroller holds it,
    // without ever scrolling the page itself
    function reveal(el) {
      var p = el.parentNode;
      while (p && p !== stage && p.getBoundingClientRect) {
        if (p.scrollHeight > p.clientHeight + 2 || p.scrollWidth > p.clientWidth + 2) {
          var pr = p.getBoundingClientRect(), er = el.getBoundingClientRect();
          if (er.top < pr.top) p.scrollTop -= (pr.top - er.top) + 8;
          else if (er.bottom > pr.bottom) p.scrollTop += (er.bottom - pr.bottom) + 8;
          if (er.left < pr.left) p.scrollLeft -= (pr.left - er.left) + 8;
          else if (er.right > pr.right) p.scrollLeft += (er.right - pr.right) + 8;
        }
        p = p.parentNode;
      }
    }

    // Narrow windows rail the dock, so a cue that points INTO the dock would
    // have nothing to point at. Summon the dock as an overlay for exactly
    // those steps, and put it away again for canvas steps. A step that sets
    // data-dock itself always wins.
    function autoDock(s, el) {
      if (!s || s.getAttribute('data-dock')) return;
      all('.edit.lean', stage).forEach(function (sh) {
        if (!isNarrow(sh)) return;
        var dock = sh.querySelector('.pdock');
        var wants = !!(el && dock && el.closest('.pdock') === dock);
        sh.setAttribute('data-dock', wants ? 'overlay' : 'open');
      });
    }

    function placeCue(s) {
      var sel = s && s.getAttribute('data-cue');
      var el = sel ? stage.querySelector(sel) : null;
      autoDock(s, el);
      if (!el || !el.getClientRects().length) { cue.classList.remove('on'); return; }
      reveal(el);
      var r = el.getBoundingClientRect(), w = wt.getBoundingClientRect();
      if (!r.width || !r.height) { cue.classList.remove('on'); return; }
      var pad = 4;
      cue.style.left = (r.left - w.left - pad) + 'px';
      cue.style.top = (r.top - w.top - pad) + 'px';
      cue.style.width = (r.width + pad * 2) + 'px';
      cue.style.height = (r.height + pad * 2) + 'px';
      var br = getComputedStyle(el).borderTopLeftRadius || '0px';
      var rad = (br === '0px' || br.indexOf(' ') > -1) ? '10px' : 'calc(' + br + ' + ' + pad + 'px)';
      cueRing.style.borderRadius = rad;
      cuePulse.style.borderRadius = rad;

      var label = s.getAttribute('data-cue-label') || '';
      cueLb.textContent = label;
      cueLb.style.display = label ? '' : 'none';
      var place = s.getAttribute('data-cue-place');
      if (!place) place = (r.top - w.top) > 96 ? 'top' : 'bottom';
      cue.className = 'wt-cue on p-' + place;

      // keep the label chip inside the walkthrough bounds
      cue.style.setProperty('--lbx', '0px');
      if (label && (place === 'top' || place === 'bottom')) {
        var lr = cueLb.getBoundingClientRect(), dx = 0;
        if (lr.left < w.left + 8) dx = (w.left + 8) - lr.left;
        else if (lr.right > w.right - 8) dx = (w.right - 8) - lr.right;
        if (dx) cue.style.setProperty('--lbx', Math.round(dx) + 'px');
      }
    }

    /* ---- nav ---- */
    var bar = wt.querySelector('.wbar');
    var prev = bar && bar.querySelector('.wprev');
    var next = bar && bar.querySelector('.wnext');
    var label = bar && bar.querySelector('.wlabel');
    var resetBtn = bar && bar.querySelector('.wt-reset');
    var dotbox = bar && bar.querySelector('.wdots');
    var dots = [];
    if (dotbox) {
      if (!dotbox.children.length) {
        steps.forEach(function () { dotbox.appendChild(document.createElement('i')); });
      }
      dots = all('i', dotbox);
      dots.forEach(function (d, k) {
        d.setAttribute('tabindex', '0');
        d.setAttribute('role', 'button');
        d.setAttribute('aria-label', 'Step ' + (k + 1));
        d.addEventListener('click', function (e) { e.stopPropagation(); show(k); });
        d.addEventListener('keydown', function (e) {
          if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); show(k); }
        });
      });
    }

    /* ---- VISUAL RULE 10: the controls belong IN the box, and Back sits
       beside Next ----
       The .wbar was authored as a SIBLING of .wt-steps, so it read as a
       detached strip floating under the caption card. Wrap the two into one
       .wt-panel here rather than editing twelve pages by hand, and reorder
       the bar's children in the DOM - not with CSS `order`, which would move
       the buttons visually while leaving tab order telling a different
       story. Left: step dots + label. Right, together: Reset · Back · Next.

       The bar goes FIRST in the panel, above the caption. You drive a
       walkthrough from the controls, so they must sit at a fixed spot the eye
       can return to; below the caption they moved down the page every time a
       step's text changed length. Bar-first also means the controls are the
       panel's first tab stops. */
    if (bar) {
      var stepsBox = wt.querySelector('.wt-steps');
      if (stepsBox && stepsBox.parentNode === bar.parentNode && !wt.querySelector('.wt-panel')) {
        var panel = document.createElement('div');
        panel.className = 'wt-panel';
        stepsBox.parentNode.insertBefore(panel, stepsBox);
        panel.appendChild(bar);
        panel.appendChild(stepsBox);
      }
      [dotbox, label, resetBtn, prev, next].forEach(function (el) {
        if (el) bar.appendChild(el);
      });
    }

    var i = 0, raf = null;
    function title(k) {
      var s = steps[k];
      if (s.getAttribute('data-title')) return s.getAttribute('data-title');
      var d = s.querySelector('.wt-do');
      return d ? d.textContent.trim() : '';
    }
    function repos() {
      if (raf) cancelAnimationFrame(raf);
      raf = requestAnimationFrame(function () { placeCue(steps[i]); });
    }
    function show(n) {
      i = Math.max(0, Math.min(steps.length - 1, n));
      resetStage();
      for (var k = 0; k <= i; k++) applyStep(steps[k]);
      steps.forEach(function (s, k) { s.classList.toggle('on', k === i); });
      dots.forEach(function (d, k) { d.classList.toggle('on', k === i); });
      if (label) label.innerHTML = 'Step <b>' + (i + 1) + '</b> / ' + steps.length + ' · ' + title(i);
      if (prev) prev.disabled = i === 0;
      if (next) next.disabled = i === steps.length - 1;
      placeCue(steps[i]);
      // re-measure after the shell's own transitions settle (sheets, dock)
      [90, 320, 560].forEach(function (t) { setTimeout(repos, t); });
    }
    // stopPropagation so the nav never counts as an "outside click" that would
    // dismiss an overlay the step just opened
    if (prev) prev.addEventListener('click', function (e) { e.stopPropagation(); show(i - 1); });
    if (next) next.addEventListener('click', function (e) { e.stopPropagation(); show(i + 1); });
    if (resetBtn) resetBtn.addEventListener('click', function (e) { e.stopPropagation(); show(0); });

    /* VISUAL RULE 10: stepping is arrow-key navigable. Bound per .wt and
       guarded to that walkthrough, so a page holding two of them steps the
       one you are actually in. A page with exactly one .wt responds without
       needing focus first; anything else requires focus, because guessing
       would steal arrows from the wrong widget. Never intercept arrows aimed
       at a control the user is editing. */
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;
      var t = e.target;
      if (t && t.closest && t.closest('input,textarea,select,[contenteditable="true"]')) return;
      var owner = t && t.closest ? t.closest('.wt') : null;
      if (!owner) {
        var only = all('.wt');
        if (only.length !== 1) return;
        owner = only[0];
      }
      if (owner !== wt) return;
      e.preventDefault();
      show(e.key === 'ArrowRight' ? i + 1 : i - 1);
    });

    window.addEventListener('resize', repos);
    if (window.ResizeObserver) new ResizeObserver(repos).observe(stage);
    // Any scroller that can move a cue target must re-position the cue.
    // .pdock belongs here: reveal() scrolls the dock itself when it overflows,
    // and without this listener a late dock scroll left the cue ~8px off its
    // target (seen only on Library-tile steps, where the dock is tallest).
    all('.pdock,.dgrp-b,.filmstrip,.libgrid', stage).forEach(function (sc) {
      sc.addEventListener('scroll', repos, { passive: true });
    });

    // deep link: ?step=5 opens the walkthrough on that step (handy for
    // pointing a reviewer at one moment in the flow)
    var deep = /[?&]step=(\d+)/.exec(location.search);
    show(deep ? parseInt(deep[1], 10) - 1 : 0);
  });
})();
