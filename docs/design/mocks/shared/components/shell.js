/* Photonz mock · the shell component: builds the title bar, Ask and the command surface.
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
  /* ============================================================
     0 · THE SHELL COMPONENT — one shell, built once, not retyped
     ============================================================
     `pages/app-shell.html` is the spec. Before this existed, every page
     hand-authored its own title bar, its own command strip and its own Ask /
     ⌘K affordance, so 57 copies drifted apart: Share/Export/Done buttons the
     canonical shell says the menu bar owns, a `.toolbar` strip app-shell had
     already deleted, and a `.cmdk` search well that no longer exists. Sweeping
     copies only fixes them until the next page is written.

     So a page now declares what it IS, and this builds the chrome:

       <div class="win tall cq shell"
            data-shell="cloud-upload · 24 × 24 · SVG"   ← text before the first
            data-ws="ui">                                 "·" is bolded
         <div class="edit lean" data-dock="open"> … </div>
       </div>

     data-ws: image | ui | video, or "none" to omit the lens selector.

     What it emits is exactly app-shell's title bar — lights · title · the
     `.wsw` lens · the Ask launcher — plus the agent-chat overlay. What it
     REMOVES is the chrome the canonical shell does not have: any authored
     `.titlebar` (with its Share/Export/Done `.tbtns`) and any `.toolbar`
     command strip. Nothing is lost with the strip: its `…` command surface and
     History button are both reachable from Ask (`/history`), which is the
     point of D6. A page that needs a bespoke conversation can still author its
     own `.askpal` and this leaves it alone. */

  // "cloud-upload · 24 × 24" -> "<b>cloud-upload</b> · 24 × 24"
  function docTitle(s) {
    var i = s.indexOf('·');
    if (i < 0) return '<b>' + s + '</b>';
    return '<b>' + s.slice(0, i).trim() + '</b> ' + s.slice(i);
  }

  // The one command list. It is here, not in a page, for the same reason the
  // title bar is: 57 copies of it would drift the same way.
  var ASK_CMDS = [
    ['ic-image', 'Remove background', 'image.removeBackground'],
    ['ic-swatch', 'Reset to style', 'layer.resetStyle'],
    ['ic-frame', 'New frame', 'frame.create'],
    ['ic-component', 'Make component', 'component.create'],
    ['ic-sidebar', 'Hide the panel dock', 'panel.dock'],
    ['ic-history', 'Capture history', 'history.open'],
    ['ic-home', 'Home', 'app.home']
  ];

  /* The WORK CARD (`.work` in agent.css): the thing that says work is
     happening, and then what work happened. Collapsed by default — the header
     is a live sentence about the step running now, and you open it only if you
     want the receipt. It is here, next to the overlay it goes in, because the
     docked conversation is the SAME node moved, not a second copy. */
  function step(state, label, target, before, after, layer) {
    var val = before
      ? '<span>' + before + '</span><i class="ic ic-arrow-right"></i><b>' + after + '</b>'
      : '<b>' + after + '</b>';
    var tick = state === 'skip' ? 'ic-x' : state === 'fail' ? 'ic-warning' : 'ic-check';
    return '<div class="step" role="button" tabindex="0" data-state="' + state + '"' +
      (layer ? ' data-layer="' + layer + '"' : '') + '>' +
      '<span class="st"><i class="ic ' + tick + '"></i></span>' +
      '<span class="sl">' + target + ' · ' + label + '</span>' +
      '<span class="sv">' + val + '</span></div>';
  }

  function workHTML() {
    return '<div class="work collapsed" data-state="done">' +
      '<button class="work-h" type="button" aria-expanded="false">' +
      '<i class="chev ic xs ic-chevron-down"></i>' +
      '<span class="work-st"><i class="ic ic-check-circle"></i></span>' +
      '<span class="work-t">Made the headline bigger and added the card glow</span>' +
      '<span class="work-m">4 changes</span></button>' +
      '<div class="work-b">' +
      step('done', 'Size', 'Headline', '36', '44', 'headline') +
      step('done', 'Line height', 'Headline', '1.2', '1.1', 'headline') +
      step('done', 'Style', 'Card', '', 'Card glow', 'card') +
      step('skip', 'Corner radius', 'Card', '', 'already 14', 'card') +
      '</div>' +
      '<div class="work-note"><i class="ic ic-warning"></i><span class="t"></span></div>' +
      '<div class="work-f">' +
      '<span class="seg sm work-view"><button class="on">After</button><button>Before</button></span>' +
      '<span class="sp"></span>' +
      '<button class="btn ghost sm"><i class="ic ic-undo"></i> Undo</button>' +
      '<span class="cost">1.4s</span></div></div>';
  }

  /* The composer: multi-line, takes a pasted or dragged image, and a send
     button whose LABEL is the state — Ask, or Queue while the agent is busy.
     Both are `.primary` and both carry the chat glyph, because they are the
     same act: say something. (The send button used to wear the sparkle, which
     is the AGENT's mark, not the verb's — it read as "do AI" rather than
     "send", and a four-pointed star is hard to pick out at 12px besides.)

     STOP LIVES HERE, next to Queue, and only while busy. It was on the work
     card, which is wrong for the one control you reach for in a hurry: the
     card scrolls away with the transcript, and the composer is pinned to the
     bottom, so this is the only place Stop is guaranteed to be on screen. */
  function composerHTML(busy) {
    // Stop is icon-only: the square is unambiguous, it keeps the send button's
    // word the loudest thing in the row, and it needs a tooltip because an icon
    // with no label is unlabelled.
    var send = busy
      ? '<button class="btn secondary icon sm" data-tip="Stop" aria-label="Stop">' +
        '<i class="ic ic-stop"></i></button>' +
        '<button class="btn primary sm"><i class="ic ic-chat"></i> Queue</button>'
      : '<button class="btn primary sm"><i class="ic ic-chat"></i> Ask</button>';
    return '<div class="chat-in"><div class="composer">' +
      '<div class="ask-atts"></div>' +
      '<textarea class="box" rows="1" placeholder="' +
      (busy ? 'Steer it, you don\'t have to wait' : 'Ask for a change, or type / for a command') +
      '" aria-label="Ask the agent"></textarea>' +
      '<div class="composer-f">' +
      '<button class="btn ghost icon sm" title="Attach an image"><i class="ic ic-image"></i></button>' +
      (busy ? '' : '<span class="hint">or paste a screenshot</span>') +
      '<span class="sp"></span>' + send +
      '</div></div></div>';
  }

  function askPalHTML(id) {
    var rows = ASK_CMDS.map(function (c) {
      return '<div class="cpx"><i class="ic sm ' + c[0] + '"></i> ' + c[1] +
        ' <span class="k">' + c[2] + '</span></div>';
    }).join('');
    return '<div class="askpal" id="' + id + '" role="dialog" aria-modal="true"' +
      ' aria-label="Ask the agent" aria-hidden="true"><div class="chat">' +
      '<div class="chat-h"><i class="ic ic-sparkle sm"></i> Agent<span class="tspacer"></span>' +
      '<span class="val">on-device</span>' +
      '<button class="btn ghost icon sm" title="New conversation"><i class="ic ic-plus"></i></button>' +
      '<button class="btn ghost icon sm" data-ask-dock aria-pressed="false"' +
      ' title="Dock the conversation"><i class="ic ic-sidebar-left"></i></button>' +
      '<button class="btn ghost icon sm" data-ask-close title="Close (Esc)"><i class="ic ic-x"></i></button>' +
      '</div>' +
      '<div class="chat-b"><div class="msg u">make the headline bigger and add our card glow</div>' +
      '<div class="msg a">Done.' + workHTML() + '</div></div>' +
      '<div class="askcmd"><div class="lbl">Commands</div><div class="cplist">' + rows +
      '<div class="empty" style="display:none">No command matches.</div></div></div>' +
      composerHTML('Ask') +
      '</div></div>';
  }

  var askSeq = 0;
  all('[data-shell]').forEach(function (win) {
    var edit = win.querySelector('.edit.lean') || win.querySelector('.edit');
    if (!edit) return;

    // 1 · HARVEST, then drop. The old header rows mix chrome with real content:
    //     this scenario's own command popover, a live status readout, and the
    //     odd genuine control (Reset, Play, Browse library). Deleting the row
    //     wholesale would delete those too, and it does not announce itself —
    //     the attribute that referenced the popover dies in the same breath, so
    //     nothing dangles and nothing complains. So pull the content out first.
    //     Done here with real DOM APIs rather than by rewriting each page,
    //     because page-local ids (#aeCmd, #aeHist) and nested markup make a
    //     text transform quietly wrong.
    var cnvEl = edit.querySelector('.cnv') || edit;
    var harvestedStatus = [];
    var harvestedCtrls = [];

    function isChrome(el) {
      var txt = (el.textContent || '').replace(/\s+/g, ' ').trim();
      if (el.classList.contains('cmdk')) return true;
      if (el.getAttribute('title') === 'Commands' && el.hasAttribute('data-menu')) return true;
      if (el.hasAttribute('data-sheet') && /^History\b/i.test(txt)) return true;
      if (/^Ask( the)? agent$/i.test(txt)) return true;
      if (/^(Share|Export|Done)$/.test(txt) &&
          !el.id && !el.hasAttribute('data-menu')) return true;
      return false;
    }

    function harvest(src) {
      if (!src) return;
      // a · popovers are this page's own menus. The one the `…` pointed at
      //     becomes the shared .cmdpop; the rest keep their own anchoring.
      all('.popover', src).forEach(function (p) {
        if (p.id && src.querySelector('[data-menu="#' + p.id + '"][title="Commands"]')) {
          p.classList.add('cmdpop');
          p.removeAttribute('style');
        }
        cnvEl.appendChild(p);
      });
      // b · status readouts belong with the document name, not in a command row
      all(':scope > .chip, :scope > .val, :scope > .pill', src).forEach(function (c) {
        if (isChrome(c)) return;
        if (c.hasAttribute('data-menu') || c.hasAttribute('data-target') ||
            c.tagName === 'BUTTON') { harvestedCtrls.push(c); return; }
        c.querySelectorAll('.ic').forEach(function (i) { i.remove(); });
        harvestedStatus.push(c.innerHTML.trim());
      });
      // c · anything still interactive is a real control: it moves to the
      //     canvas action cluster as an icon tool, label kept as the tooltip.
      all(':scope > button, :scope > a', src).forEach(function (b) {
        if (isChrome(b)) return;
        harvestedCtrls.push(b);
      });
    }

    harvest(win.querySelector(':scope > .toolbar'));
    harvest(win.querySelector(':scope > .titlebar > .tbtns'));

    if (harvestedCtrls.length) {
      var act = cnvEl.querySelector(':scope > .cnv-act');
      if (!act) {
        act = document.createElement('div');
        act.className = 'cnv-act';
        cnvEl.appendChild(act);
      }
      harvestedCtrls.forEach(function (b) {
        var label = (b.getAttribute('title') || b.textContent || '').replace(/\s+/g, ' ').trim();
        var icon = b.querySelector('.ic');
        b.className = 'tool';
        b.setAttribute('title', label || 'Action');
        b.innerHTML = '';
        var i = document.createElement('i');
        i.className = 'ic sm ' + (icon ? (icon.className.match(/ic-[\w-]+/) || ['ic-more'])[0] : 'ic-more');
        b.appendChild(i);
        act.insertBefore(b, act.firstChild);
      });
    }
    if (harvestedStatus.length && !win.getAttribute('data-status')) {
      win.setAttribute('data-status', harvestedStatus.join(' · '));
    }

    // now the rows hold nothing but chrome, so drop them
    all(':scope > .titlebar', win).forEach(function (t) { t.parentNode.removeChild(t); });
    all(':scope > .toolbar', win).forEach(function (t) { t.parentNode.removeChild(t); });
    all('.wsw', win).forEach(function (t) { t.parentNode.removeChild(t); });

    // 2 · the ask overlay, one per shell, before the title bar needs its id
    // look anywhere in the shell, not just at direct children: a page that
    // authored its own overlay may have nested it in .cnv, and a direct-child
    // check would miss it and build a second one with the same id.
    var pal = edit.querySelector('.askpal');
    if (!pal) {
      var id = win.id ? win.id + '-ask' : 'askPal' + (askSeq ? '-' + askSeq : '');
      askSeq++;
      edit.insertAdjacentHTML('beforeend', askPalHTML(id));
      pal = edit.querySelector('#' + CSS.escape(id));
    }

    // 3 · panel-group sizing. A group's height budget is a ROLE, not a number
    //     a page picks (see the ladder in photonz-ds.css). Any hand-tuned
    //     inline --gh is stripped and replaced by the role's budget, so the
    //     Layers panel expands and contracts identically on every page. The
    //     role is read from data-grp, or inferred from the group's own title
    //     so the existing pages conform without being edited one by one.
    var ROLE = {
      layers: 'layers', properties: 'props', inspector: 'props',
      effects: 'effects', library: 'library', agent: 'agent'
    };
    all('.pdock .dgrp', edit).forEach(function (g) {
      if (!g.getAttribute('data-grp')) {
        var t = (g.querySelector('.dgrp-h .ttl') || {}).textContent || '';
        var role = ROLE[t.trim().toLowerCase()];
        if (role) g.setAttribute('data-grp', role);
      }
      // .grow takes the leftover space and needs no budget at all
      if (g.classList.contains('grow')) { g.style.removeProperty('--gh'); return; }
      if (g.getAttribute('data-grp') && !g.getAttribute('data-gh')) {
        g.style.removeProperty('--gh');
        return;
      }
      // A page-specific group (Tokens, Measurements, Layout grid…) still gets a
      // budget off the ladder rather than its own number: snap the authored
      // value to the nearest rung. Three heights in the whole dock, not thirty.
      var px = parseFloat(g.style.getPropertyValue('--gh'));
      if (!px || g.getAttribute('data-gh')) return;
      var rung = px < 156 ? 'sm' : (px < 222 ? 'md' : 'lg');
      g.style.removeProperty('--gh');
      g.setAttribute('data-gh', rung);
    });

    // 4 · the D3 command surface. The page still authors its OWN commands (a
    //     .popover.menu.cmdpop of scenario menu items — that is real content);
    //     the button that opens it is chrome, so it is built here, into the
    //     canvas action cluster, on every page identically.
    var cmdpop = edit.querySelector('.cmdpop');
    if (cmdpop) {
      var cnv = edit.querySelector('.cnv');
      if (cnv) {
        if (cmdpop.parentNode !== cnv) cnv.appendChild(cmdpop);
        if (!cmdpop.id) cmdpop.id = (win.id || 'shell') + '-cmds';
        var act = cnv.querySelector(':scope > .cnv-act');
        if (!act) {
          act = document.createElement('div');
          act.className = 'cnv-act';
          cnv.appendChild(act);
        }
        if (!act.querySelector('[data-menu="#' + cmdpop.id + '"]')) {
          act.insertAdjacentHTML('afterbegin',
            '<button class="tool" data-menu="#' + cmdpop.id + '" aria-haspopup="menu"' +
            ' title="Commands"><i class="ic sm ic-more"></i></button>');
        }
        // Every command menu ends with the way OUT of the document. Photonz is
        // one document per window, so "back" is the front door: New, Open,
        // Recent, and the four start scenarios. That is also where the
        // workspace is chosen, which is why the title bar no longer carries a
        // lens switcher — you do not change lens mid-document, you open a
        // different document. Appended here so all 67 shells get the same
        // item in the same place instead of 67 pages remembering to add it.
        if (!cmdpop.querySelector('[data-target="home"]')) {
          cmdpop.insertAdjacentHTML('beforeend',
            '<div class="menu-sep"></div>' +
            '<div class="menuitem" data-target="home">' +
            '<i class="ic ic-home"></i> Home</div>');
        }
      }
    }

    // 5 · the title bar. Lights · document · status · Ask. Nothing else.
    //     No Share/Export/Done (the native menu bar owns those) and NO
    //     segmented control: the workspace lens is not a title-bar decision,
    //     and three tabs up here read as app-level navigation, which is exactly
    //     what "one document, surfaces are lenses" is trying not to say.
    //     data-ws still records which lens the page is in, for the tool strip.
    var status = win.getAttribute('data-status') || '';
    var h = '<div class="lights"><i class="r"></i><i class="y"></i><i class="g"></i></div>' +
      '<div class="wtitle">' + docTitle(win.getAttribute('data-shell') || '') + '</div>' +
      (status ? '<span class="wstatus">' + status + '</span>' : '');
    h += '<button class="btn sm hero askbtn" data-ask="#' + pal.id + '" aria-expanded="false"' +
      ' aria-haspopup="dialog" title="Ask the agent, or run a command (⌘K)">' +
      '<i class="ic ic-sparkle"></i> Ask <span class="kbd">⌘K</span></button>';
    var tb = document.createElement('div');
    tb.className = 'titlebar';
    tb.innerHTML = h;
    win.insertBefore(tb, win.firstChild);
  });
})();
