/* Photonz mock · the blank-slate ENTRY template (PRODUCT-MODEL §4b req 5, §4e).
   Every "how do I start from nothing" clickthrough opens on the same screen:
   an empty desk, the resident menu-bar agent, and the global capture history.
   That chrome is IDENTICAL by definition — the agent has ONE menu and history
   has ONE shape — so it is built here, once, instead of being retyped per page
   (capture-wt and walk had already drifted a copy each; see AGENTS.md,
   "The shell is a COMPONENT").

   A page opts in by marking its desk:

     <div class="desk" data-entry>
       <div class="deskbody">
         …page artwork, hint, editor window(s), toasts…
         <div class="sheet down hist" id="histSheet" aria-hidden="true" aria-label="Capture history">
           <div class="sheet-b">
             <div class="filmstrip" data-radio=".filmcard" data-radio-class="sel" data-entry-fill>
               …this page's OWN capture card(s) — the artwork the flow is about…
             </div>
           </div>
         </div>
       </div>
     </div>

   What the component injects:
   · the canonical `.mbar` (spacer · Photonz status item + the FULL canonical
     menu from AGENTS.md · sound · clock) as the desk's first child, unless the
     page already authors a `.mbar`. Stable ids for walkthrough cues:
     #mbAgent #mbMenu #miCapture #miCaptureFull #miRecord #miHistory
     #miNewWindow #miNewClipboard #miOpen
   · `data-sheet` wiring from Show History to the desk's own history sheet
   · the canonical `.histbar` (centered All · Screenshots · Videos + Clear All)
     into a history sheet that has none. Ids: #hsAll #hsShots #hsVids
   · the standard PAST — filler filmcards appended after the page's own cards
     in any `[data-entry-fill]` strip, so every entry page shares one history.
     Screenshots carry .fk-shot, recordings .fk-clip; the strip filters with
     .flt-shot / .flt-vid (rules in history.css). Steps drive the filter with
     data-activate="#hsVids" data-class="#<strip>=flt-vid"; direct clicks on
     the injected histbar do the same live.

   Must run BEFORE overlays/popover/segmented/walkthrough bind (order.json). */
(function () {
  function el(html) {
    var t = document.createElement('template');
    t.innerHTML = html.trim();
    return t.content.firstChild;
  }

  var MENU =
    '<span class="sp"></span>' +
    '<span class="mbitem">' +
      '<button class="mbicon" id="mbAgent" aria-haspopup="menu" aria-expanded="false" ' +
              'data-menu="#mbMenu" title="Photonz"><i class="ic sm ic-aperture"></i></button>' +
      '<div class="popover menu mbmenu pop" id="mbMenu" role="menu" aria-label="Photonz">' +
        '<button type="button" class="menuitem" role="menuitem" id="miCapture">Capture Region <span class="sc">⇧⌘4</span></button>' +
        '<button type="button" class="menuitem" role="menuitem" id="miCaptureFull">Capture Full Screen <span class="sc">⇧⌘3</span></button>' +
        '<button type="button" class="menuitem" role="menuitem" id="miRecord">Record Screen / Video… <span class="sc">⇧⌘5</span></button>' +
        '<div class="menu-sep"></div>' +
        '<button type="button" class="menuitem" role="menuitem" id="miEditLast">Edit Last Capture <span class="sc">⇧⌘6</span></button>' +
        '<button type="button" class="menuitem" role="menuitem" id="miHistory">Show History <span class="sc">⇧⌘H</span></button>' +
        '<div class="menu-sep"></div>' +
        '<button type="button" class="menuitem" role="menuitem" id="miNewWindow">New Window</button>' +
        '<button type="button" class="menuitem" role="menuitem" id="miNewClipboard">New from Clipboard</button>' +
        '<button type="button" class="menuitem" role="menuitem" id="miOpen">Open…</button>' +
        '<div class="menu-sep"></div>' +
        '<button type="button" class="menuitem" role="menuitem">Check for Updates…</button>' +
        '<button type="button" class="menuitem" role="menuitem">Welcome &amp; Permissions…</button>' +
        '<button type="button" class="menuitem" role="menuitem">Experiments…</button>' +
        '<button type="button" class="menuitem" role="menuitem">About Photonz</button>' +
        '<div class="menu-sep"></div>' +
        '<button type="button" class="menuitem" role="menuitem">Quit Photonz <span class="sc">⌘Q</span></button>' +
      '</div>' +
    '</span>' +
    '<button class="mbicon" title="Sound"><i class="ic sm ic-volume"></i></button>' +
    '<span class="clock">Mon 9:41</span>';

  var HISTBAR =
    '<div class="histbar">' +
      '<div class="seg" data-radio="button">' +
        '<button class="on" id="hsAll">All</button>' +
        '<button id="hsShots">Screenshots</button>' +
        '<button id="hsVids">Videos</button>' +
      '</div>' +
      '<span class="hb-r"><button class="btn ghost sm"><i class="ic ic-trash"></i> Clear All</button></span>' +
    '</div>';

  /* the standard past: what "everyone's history already holds". Every entry
     page shares this set, after its own card(s). */
  var PAST = [
    { id: 'fcPricing',  nm: 'pricing-page',     ago: '22 minutes ago', bg: 'linear-gradient(135deg,#ffb36b,#ff5d8f)' },
    { id: 'fcRecording',nm: 'screen-recording', ago: '2 hours ago',    bg: 'linear-gradient(135deg,#12c2e9,#7c4dff)', dur: '0:18' },
    { id: 'fcHero',     nm: 'hero-card',        ago: '3 hours ago',    bg: 'linear-gradient(135deg,#7c4dff,#ff5d8f)' },
    { id: 'fcSettings', nm: 'settings-window',  ago: 'yesterday',      bg: 'linear-gradient(135deg,#5c6680,#26463a)' },
    { id: 'fcOnboard',  nm: 'onboarding-run',   ago: 'yesterday',      bg: 'linear-gradient(135deg,#3ecf8e,#12c2e9)', dur: '0:42' },
    { id: 'fcToasts',   nm: 'toast-states',     ago: '2 days ago',     bg: 'linear-gradient(135deg,#f0685c,#ffb057)' },
    { id: 'fcNavbar',   nm: 'nav-bar',          ago: '3 days ago',     bg: 'linear-gradient(135deg,#9a5cff,#c56cff)' },
    { id: 'fcBroll',    nm: 'b-roll',           ago: '4 days ago',     bg: 'linear-gradient(135deg,#1b7a8c,#12c2e9)', dur: '0:07' }
  ];

  function card(c) {
    return el(
      '<div class="filmcard ' + (c.dur ? 'fk-clip' : 'fk-shot') + '" id="' + c.id + '" tabindex="0" role="button">' +
        '<span class="th" style="background:' + c.bg + '">' +
          (c.dur ? '<span class="pl"><i class="ic ic-play"></i></span><span class="dur">' + c.dur + '</span>' : '') +
        '</span>' +
        '<span class="cap"><span class="nm">' + c.nm + '</span><span class="ago">' + c.ago + '</span></span>' +
        '<span class="acts">' +
          '<button class="btn ghost icon sm" title="Copy"><i class="ic ic-copy"></i></button>' +
          '<button class="btn ghost icon sm" title="Edit"><i class="ic ic-pencil"></i></button>' +
          '<button class="btn ghost icon sm" title="Pin"><i class="ic ic-pin"></i></button>' +
          '<button class="btn ghost icon sm" title="Delete"><i class="ic ic-trash"></i></button>' +
        '</span>' +
      '</div>');
  }

  document.querySelectorAll('.desk[data-entry]').forEach(function (desk) {
    // 1 · the menu-bar agent, unless the page authored its own strip
    if (!desk.querySelector('.mbar')) {
      var mb = document.createElement('div');
      mb.className = 'mbar';
      mb.innerHTML = MENU;
      desk.insertBefore(mb, desk.firstChild);
    }

    var hist = desk.querySelector('.sheet.down.hist');

    // 2 · Show History opens this desk's history sheet
    var mi = desk.querySelector('#miHistory');
    if (hist && hist.id && mi && !mi.hasAttribute('data-sheet')) {
      mi.setAttribute('data-sheet', '#' + hist.id);
    }

    // 3 · the canonical histbar, when the page did not author one
    var body = hist && hist.querySelector('.sheet-b');
    if (body && !body.querySelector('.histbar')) {
      body.insertBefore(el(HISTBAR), body.firstChild);
    }

    // 4 · the standard past, after the page's own cards
    var strip = desk.querySelector('.filmstrip[data-entry-fill]');
    if (strip) PAST.forEach(function (c) { strip.appendChild(card(c)); });

    // 5 · the scope filter is live for direct clicks too (a walkthrough step
    //     drives the same state declaratively with data-class on the strip)
    if (body && strip) {
      [['#hsAll', ''], ['#hsShots', 'flt-shot'], ['#hsVids', 'flt-vid']].forEach(function (p) {
        var b = body.querySelector(p[0]);
        if (!b) return;
        b.addEventListener('click', function () {
          strip.classList.remove('flt-shot', 'flt-vid');
          if (p[1]) strip.classList.add(p[1]);
        });
      });
    }
  });
})();
