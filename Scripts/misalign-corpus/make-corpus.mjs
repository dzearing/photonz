#!/usr/bin/env node
// Renders the misalignment test corpus: small web UIs (a settings pane, a feed,
// pricing cards, a tool bar, a form, a sidebar, chips, a dialog, a tile grid),
// each once clean and again with ONE planted fault (an element 1, 2 or 3 points
// off, an uneven gap, a card with different padding, a 2 point border among 1
// point ones), photographed by headless Chrome at 2x as a Retina screenshot is.
//
//   node Scripts/misalign-corpus/make-corpus.mjs
//
// Writes Tests/PhotonzRenderTests/Fixtures/misalign/<case>.png and truth.json:
// for every case the fault planted, where it is in the picture's own pixels
// (read off the page with getBoundingClientRect, never typed by hand) and how
// big it is in points. `MisalignmentCorpusTests` scores the detector against it.
//
// Only when the corpus itself changes: the tests pin numbers against the
// committed pictures. Chrome runs with a throwaway profile and is always killed.
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { crc32 } from 'node:zlib';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = join(ROOT, 'Tests/PhotonzRenderTests/Fixtures/misalign');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const SCALE = 2;
mkdirSync(OUT, { recursive: true });

const FONT = `-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif`;

// MARK: The pages. Every position is a whole CSS pixel, which at 2x is a whole
// point, so the clean page is exactly as consistent as its CSS says.

const pages = {
  settings: {
    size: [520, 440],
    css: `
      body{margin:0;background:#f2f2f7;font:15px ${FONT};color:#1c1c1e}
      .wrap{padding:24px 32px}
      h1{font-size:22px;font-weight:700;margin:0 0 16px;line-height:28px}
      .card{background:#fff;border-radius:10px;padding:0 16px;margin-bottom:20px}
      .row{display:flex;align-items:center;justify-content:space-between;height:44px;border-bottom:1px solid #e5e5ea}
      .row:last-child{border-bottom:none}
      .row span{position:relative}
      .sw{width:42px;height:24px;border-radius:12px;background:#34c759;position:relative}
      .sw::after{content:'';position:absolute;top:2px;left:20px;width:20px;height:20px;border-radius:10px;background:#fff}
      .sw.off{background:#e5e5ea}.sw.off::after{left:2px}
      .field{width:180px;height:24px;border:1px solid #c7c7cc;border-radius:6px;background:#fff;box-sizing:border-box;position:relative}
      .btns{display:flex;gap:12px}
      .btn{height:28px;padding:0 14px;border-radius:7px;display:flex;align-items:center;font-size:13px;background:#e5e5ea}
      .btn.primary{background:#0a84ff;color:#fff}`,
    html: `<div class="wrap"><h1>General</h1>
      <div class="card" id="c1">
        <div class="row"><span id="l0">Launch at login</span><div class="sw" id="sw0"></div></div>
        <div class="row"><span id="l1">Show in menu bar</span><div class="sw" id="sw1"></div></div>
        <div class="row"><span id="l2">Play sound on capture</span><div class="sw off" id="sw2"></div></div>
      </div>
      <div class="card" id="c2">
        <div class="row"><span id="l3">Save captures to</span><div class="field" id="f0"></div></div>
        <div class="row"><span id="l4">File name prefix</span><div class="field" id="f1"></div></div>
        <div class="row"><span id="l5">Copy to clipboard</span><div class="sw" id="sw3"></div></div>
      </div>
      <div class="btns"><div class="btn" id="reset">Reset</div><div class="btn primary" id="save">Save Changes</div></div></div>`,
    faults: [
      { id: 'label-1pt', css: '#l4{left:1px}', truth: [{ kind: 'edge', axis: 'x', el: '#l4', pt: 1 }] },
      { id: 'label-2pt', css: '#l1{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#l1', pt: 2 }] },
      { id: 'switch-3pt', css: '#sw1{left:-3px}', truth: [{ kind: 'edge', axis: 'x', el: '#sw1', pt: 3 }] },
      { id: 'card-padding', css: '#c2{padding:0 18px}', truth: [{ kind: 'padding', el: '#c2', pt: 2 }] },
      // Several at once, the way a real screen goes wrong: the walk's picture.
      { id: 'three-faults', css: '#l1{left:2px}#sw2{left:-3px}#f1{left:1px}',
        truth: [{ kind: 'edge', axis: 'x', el: '#l1', pt: 2 }, { kind: 'edge', axis: 'x', el: '#sw2', pt: 3 },
                { kind: 'edge', axis: 'x', el: '#f1', pt: 1 }] },
    ],
  },

  feed: {
    size: [460, 420],
    css: `
      body{margin:0;background:#f5f5f7;font:15px ${FONT};color:#1d1d1f}
      .wrap{padding:20px 24px}
      .k{background:#fff;border-radius:12px;padding:14px;display:flex;gap:12px;align-items:center;
         box-shadow:0 1px 2px rgba(0,0,0,.06);margin-bottom:12px;position:relative}
      .av{width:40px;height:40px;border-radius:20px;flex:none;position:relative}
      .t{font-weight:600;line-height:20px;position:relative}
      .s{font-size:13px;color:#6e6e73;line-height:18px}`,
    html: `<div class="wrap">
      <div class="k" id="k0"><div class="av" id="a0" style="background:#5e5ce6"></div><div><div class="t" id="t0">Avery Johnson</div><div class="s">Design lead</div></div></div>
      <div class="k" id="k1"><div class="av" id="a1" style="background:#ff9f0a"></div><div><div class="t" id="t1">Maya Kim</div><div class="s">Engineer</div></div></div>
      <div class="k" id="k2"><div class="av" id="a2" style="background:#30d158"></div><div><div class="t" id="t2">Sam Ortiz</div><div class="s">Research</div></div></div>
      <div class="k" id="k3"><div class="av" id="a3" style="background:#ff375f"></div><div><div class="t" id="t3">Lee Chen</div><div class="s">Product</div></div></div>
      </div>`,
    faults: [
      { id: 'gap-2pt', css: '#k1{margin-bottom:14px}', truth: [{ kind: 'gap', axis: 'y', between: ['#k1', '#k2'], pt: 2 }] },
      { id: 'gap-1pt', css: '#k2{margin-bottom:13px}', truth: [{ kind: 'gap', axis: 'y', between: ['#k2', '#k3'], pt: 1 }] },
      { id: 'title-3pt', css: '#t2{left:3px}', truth: [{ kind: 'edge', axis: 'x', el: '#t2', pt: 3 }] },
      { id: 'avatar-1pt', css: '#a3{left:1px}', truth: [{ kind: 'edge', axis: 'x', el: '#a3', pt: 1 }] },
      { id: 'card-padding', css: '#k1{padding:16px}', truth: [{ kind: 'padding', el: '#k1', pt: 2 }] },
    ],
  },

  pricing: {
    size: [560, 360],
    css: `
      body{margin:0;background:#fff;font:14px ${FONT};color:#1d1d1f}
      .wrap{padding:24px;display:flex;gap:16px;align-items:flex-start}
      .p{width:152px;border:1px solid #d2d2d7;border-radius:14px;padding:20px;position:relative}
      .n{font-size:13px;font-weight:600;color:#6e6e73;line-height:18px}
      .pr{font-size:28px;font-weight:700;line-height:34px;margin:6px 0 12px}
      .f{line-height:22px;color:#424245}
      .b{margin-top:16px;height:32px;border-radius:8px;background:#0071e3;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:600;position:relative}`,
    html: `<div class="wrap">
      <div class="p" id="p0"><div class="n">Basic</div><div class="pr">$0</div><div class="f">1 project</div><div class="f">Local files</div><div class="f">Export PNG</div><div class="b" id="b0">Start</div></div>
      <div class="p" id="p1"><div class="n">Pro</div><div class="pr">$8</div><div class="f">10 projects</div><div class="f">Cloud sync</div><div class="f">Export video</div><div class="b" id="b1">Upgrade</div></div>
      <div class="p" id="p2"><div class="n">Team</div><div class="pr">$20</div><div class="f">Unlimited</div><div class="f">Shared kits</div><div class="f">Admin tools</div><div class="b" id="b2">Contact</div></div>
      </div>`,
    faults: [
      { id: 'card-top-2pt', css: '#p1{top:2px}', truth: [{ kind: 'edge', axis: 'y', el: '#p1', pt: 2 }] },
      { id: 'border-2pt', css: '#p2{border-width:2px;padding:19px}', truth: [{ kind: 'border', el: '#p2', pt: 1 }] },
      { id: 'button-1pt', css: '#b1{left:1px}', truth: [{ kind: 'edge', axis: 'x', el: '#b1', pt: 1 }] },
      { id: 'gap-3pt', css: '#p2{margin-left:3px}', truth: [{ kind: 'gap', axis: 'x', between: ['#p1', '#p2'], pt: 3 }] },
    ],
  },

  toolbar: {
    size: [440, 120],
    css: `
      body{margin:0;background:#1e1e1e;font:13px ${FONT};color:#f5f5f7}
      .bar{margin:28px 24px;display:flex;gap:8px;padding:8px;background:#2c2c2e;border-radius:12px;width:max-content}
      .i{width:32px;height:32px;border-radius:8px;background:#3a3a3c;position:relative;display:flex;align-items:center;justify-content:center}
      .i b{display:block;width:14px;height:14px;border:2px solid #f5f5f7;border-radius:3px;box-sizing:border-box}
      .i.on{background:#0a84ff}`,
    html: `<div class="bar">
      <div class="i on" id="i0"><b></b></div><div class="i" id="i1"><b style="border-radius:7px"></b></div>
      <div class="i" id="i2"><b style="width:4px;border-radius:2px"></b></div><div class="i" id="i3"><b style="height:4px"></b></div>
      <div class="i" id="i4"><b style="border-style:dashed"></b></div><div class="i" id="i5"><b style="transform:rotate(45deg)"></b></div>
      <div class="i" id="i6"><b style="width:8px;height:8px"></b></div></div>`,
    faults: [
      { id: 'button-top-1pt', css: '#i3{top:1px}', truth: [{ kind: 'edge', axis: 'y', el: '#i3', pt: 1 }] },
      { id: 'gap-2pt', css: '#i4{margin-left:2px}', truth: [{ kind: 'gap', axis: 'x', between: ['#i3', '#i4'], pt: 2 }] },
      { id: 'gap-1pt', css: '#i2{margin-left:1px}', truth: [{ kind: 'gap', axis: 'x', between: ['#i1', '#i2'], pt: 1 }] },
    ],
  },

  form: {
    size: [440, 260],
    css: `
      body{margin:0;background:#ececec;font:13px ${FONT};color:#1d1d1f}
      .wrap{padding:28px 24px}
      .r{display:flex;align-items:center;height:28px;margin-bottom:12px}
      .r label{width:96px;text-align:right;margin-right:12px;position:relative}
      .r .in{width:220px;height:24px;background:#fff;border:1px solid #bdbdbd;border-radius:5px;box-sizing:border-box;position:relative}`,
    html: `<div class="wrap">
      <div class="r"><label id="lb0">Name</label><div class="in" id="in0"></div></div>
      <div class="r"><label id="lb1">Email</label><div class="in" id="in1"></div></div>
      <div class="r"><label id="lb2">Company</label><div class="in" id="in2"></div></div>
      <div class="r"><label id="lb3">Role</label><div class="in" id="in3"></div></div>
      <div class="r"><label id="lb4">Phone</label><div class="in" id="in4"></div></div></div>`,
    faults: [
      { id: 'field-2pt', css: '#in3{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#in3', pt: 2 }] },
      { id: 'field-1pt', css: '#in1{left:1px}', truth: [{ kind: 'edge', axis: 'x', el: '#in1', pt: 1 }] },
      { id: 'label-right-2pt', css: '#lb2{left:-2px}', truth: [{ kind: 'edge', axis: 'x', el: '#lb2', pt: 2 }] },
    ],
  },

  sidebar: {
    size: [300, 340],
    css: `
      body{margin:0;background:#f6f6f6;font:13px ${FONT};color:#1d1d1f}
      .nav{padding:16px 12px}
      .n{display:flex;align-items:center;gap:8px;height:28px;padding:0 8px;border-radius:6px;margin-bottom:4px;position:relative}
      .n.sel{background:#dcdcdc}
      .ic{width:16px;height:16px;border-radius:4px;flex:none;position:relative}
      .n span{position:relative}`,
    html: `<div class="nav">
      <div class="n sel" id="n0"><div class="ic" id="ni0" style="background:#0a84ff"></div><span id="nl0">Inbox</span></div>
      <div class="n" id="n1"><div class="ic" id="ni1" style="background:#ff9f0a"></div><span id="nl1">Drafts</span></div>
      <div class="n" id="n2"><div class="ic" id="ni2" style="background:#30d158"></div><span id="nl2">Sent</span></div>
      <div class="n" id="n3"><div class="ic" id="ni3" style="background:#bf5af2"></div><span id="nl3">Archive</span></div>
      <div class="n" id="n4"><div class="ic" id="ni4" style="background:#ff453a"></div><span id="nl4">Trash</span></div>
      <div class="n" id="n5"><div class="ic" id="ni5" style="background:#64d2ff"></div><span id="nl5">Notes</span></div>
      <div class="n" id="n6"><div class="ic" id="ni6" style="background:#8e8e93"></div><span id="nl6">Settings</span></div></div>`,
    faults: [
      { id: 'label-2pt', css: '#nl3{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#nl3', pt: 2 }] },
      { id: 'icon-1pt', css: '#ni5{left:1px}', truth: [{ kind: 'edge', axis: 'x', el: '#ni5', pt: 1 }] },
      { id: 'icon-3pt', css: '#ni2{left:3px}', truth: [{ kind: 'edge', axis: 'x', el: '#ni2', pt: 3 }] },
    ],
  },

  chips: {
    size: [480, 140],
    css: `
      body{margin:0;background:#fff;font:13px ${FONT};color:#1d1d1f}
      .wrap{padding:32px 24px;display:flex;gap:8px}
      .c{height:28px;padding:0 12px;border:1px solid #d1d1d6;border-radius:14px;display:flex;align-items:center;background:#f5f5f7;position:relative}`,
    html: `<div class="wrap"><div class="c" id="ch0">Design</div><div class="c" id="ch1">Video</div><div class="c" id="ch2">Capture</div>
      <div class="c" id="ch3">Audio</div><div class="c" id="ch4">Icons</div><div class="c" id="ch5">Motion</div></div>`,
    faults: [
      { id: 'gap-1pt', css: '#ch3{margin-left:1px}', truth: [{ kind: 'gap', axis: 'x', between: ['#ch2', '#ch3'], pt: 1 }] },
      { id: 'padding-2pt', css: '#ch1{padding:0 14px}', truth: [{ kind: 'padding', el: '#ch1', pt: 2 }] },
      { id: 'border-1pt', css: '#ch4{border-width:2px;padding:0 11px}', truth: [{ kind: 'border', el: '#ch4', pt: 1 }] },
    ],
  },

  dialog: {
    size: [440, 240],
    css: `
      body{margin:0;background:#1c1c1e;font:13px ${FONT};color:#f5f5f7}
      .d{margin:20px;padding:20px;background:#2c2c2e;border-radius:12px}
      h2{font-size:15px;font-weight:700;margin:0 0 8px;line-height:20px;position:relative}
      p{margin:0 0 6px;line-height:18px;color:#c7c7cc;position:relative}
      .btns{display:flex;justify-content:flex-end;gap:10px;margin-top:22px}
      .b{height:28px;padding:0 16px;border-radius:7px;background:#48484a;display:flex;align-items:center;position:relative}
      .b.ok{background:#0a84ff}`,
    html: `<div class="d"><h2 id="h">Replace the existing file?</h2>
      <p id="p0">A file with this name already exists.</p><p id="p1">Replacing it overwrites what it holds.</p>
      <div class="btns"><div class="b" id="keep">Keep Both</div><div class="b" id="cancel">Cancel</div><div class="b ok" id="ok">Replace</div></div></div>`,
    faults: [
      { id: 'body-2pt', css: '#p1{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#p1', pt: 2 }] },
      { id: 'button-top-3pt', css: '#cancel{top:3px}', truth: [{ kind: 'edge', axis: 'y', el: '#cancel', pt: 3 }] },
      { id: 'button-gap-2pt', css: '#ok{margin-left:2px}', truth: [{ kind: 'gap', axis: 'x', between: ['#cancel', '#ok'], pt: 2 }] },
    ],
  },

  tiles: {
    size: [460, 300],
    css: `
      body{margin:0;background:#fafafa;font:12px ${FONT};color:#1d1d1f}
      .g{padding:24px;display:grid;grid-template-columns:repeat(3,128px);gap:16px 12px}
      .tile{position:relative}
      .im{height:84px;border-radius:8px}
      .cap{margin-top:6px;line-height:16px}`,
    html: `<div class="g">
      <div class="tile" id="g0"><div class="im" style="background:linear-gradient(135deg,#5e5ce6,#bf5af2)"></div><div class="cap">Evening</div></div>
      <div class="tile" id="g1"><div class="im" style="background:linear-gradient(135deg,#30d158,#0a84ff)"></div><div class="cap">Lagoon</div></div>
      <div class="tile" id="g2"><div class="im" style="background:linear-gradient(135deg,#ff9f0a,#ff375f)"></div><div class="cap">Ember</div></div>
      <div class="tile" id="g3"><div class="im" style="background:linear-gradient(135deg,#64d2ff,#5e5ce6)"></div><div class="cap">Glacier</div></div>
      <div class="tile" id="g4"><div class="im" style="background:linear-gradient(135deg,#ffd60a,#ff9f0a)"></div><div class="cap">Citrus</div></div>
      <div class="tile" id="g5"><div class="im" style="background:linear-gradient(135deg,#8e8e93,#3a3a3c)"></div><div class="cap">Graphite</div></div></div>`,
    faults: [
      { id: 'tile-2pt', css: '#g4{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#g4 .im', pt: 2 },
                                                    { kind: 'gap', axis: 'x', between: ['#g4 .im', '#g5 .im'], pt: 2, alt: true }] },
      { id: 'tile-top-1pt', css: '#g2{top:1px}', truth: [{ kind: 'edge', axis: 'y', el: '#g2 .im', pt: 1 }] },
      { id: 'caption-3pt', css: '#g1 .cap{position:relative;left:3px}', truth: [{ kind: 'edge', axis: 'x', el: '#g1 .cap', pt: 3 }] },
    ],
  },
};

// MARK: The held-out pages
//
// Written after the detector was tuned on the pages above and scored once,
// untouched: the honest number. Never tune the detector against these.

const heldOut = {
  mail: {
    size: [520, 360],
    css: `
      body{margin:0;background:#fff;font:13px ${FONT};color:#1d1d1f}
      .list{padding:12px 0}
      .m{display:flex;align-items:center;height:56px;padding:0 20px;border-bottom:1px solid #e5e5ea;gap:10px;position:relative}
      .dot{width:8px;height:8px;border-radius:4px;background:#0a84ff;flex:none;position:relative}
      .dot.read{background:transparent}
      .tx{flex:1;min-width:0}
      .from{font-weight:600;line-height:18px;position:relative}
      .sub{color:#6e6e73;line-height:18px}
      .date{color:#8e8e93;font-size:12px;position:relative}`,
    html: `<div class="list">
      <div class="m"><div class="dot" id="o0"></div><div class="tx"><div class="from" id="s0">Jordan Lee</div><div class="sub">Notes from the design review</div></div><div class="date" id="d0">9:41</div></div>
      <div class="m"><div class="dot" id="o1"></div><div class="tx"><div class="from" id="s1">Priya Natarajan</div><div class="sub">Updated build is ready</div></div><div class="date" id="d1">Yesterday</div></div>
      <div class="m"><div class="dot read" id="o2"></div><div class="tx"><div class="from" id="s2">Chris Park</div><div class="sub">Lunch on Friday?</div></div><div class="date" id="d2">Tuesday</div></div>
      <div class="m"><div class="dot" id="o3"></div><div class="tx"><div class="from" id="s3">Morgan Diaz</div><div class="sub">Invoice for October</div></div><div class="date" id="d3">Monday</div></div>
      <div class="m"><div class="dot" id="o4"></div><div class="tx"><div class="from" id="s4">Riley Brooks</div><div class="sub">Photos from the trip</div></div><div class="date" id="d4">Oct 12</div></div></div>`,
    faults: [
      { id: 'date-2pt', css: '#d1{left:-2px}', truth: [{ kind: 'edge', axis: 'x', el: '#d1', pt: 2 }] },
      { id: 'sender-1pt', css: '#s3{left:1px}', truth: [{ kind: 'edge', axis: 'x', el: '#s3', pt: 1 }] },
      { id: 'dot-2pt', css: '#o4{top:2px}', truth: [{ kind: 'edge', axis: 'y', el: '#o4', pt: 2 }] },
    ],
  },

  stats: {
    size: [480, 320],
    css: `
      body{margin:0;background:#f2f2f7;font:13px ${FONT};color:#1d1d1f}
      .g{padding:20px;display:grid;grid-template-columns:repeat(2,200px);gap:12px}
      .s{background:#fff;border-radius:12px;padding:16px;position:relative}
      .l{color:#6e6e73;line-height:16px}
      .v{font-size:28px;font-weight:700;line-height:34px;margin-top:6px;position:relative}
      .c{display:inline-block;margin-top:8px;padding:2px 8px;border-radius:9px;background:#e3f9e5;color:#1f7a34;font-size:12px;line-height:14px}`,
    html: `<div class="g">
      <div class="s" id="t0"><div class="l">Visitors</div><div class="v" id="v0">12,480</div><div class="c">+8%</div></div>
      <div class="s" id="t1"><div class="l">Signups</div><div class="v" id="v1">1,032</div><div class="c">+3%</div></div>
      <div class="s" id="t2"><div class="l">Revenue</div><div class="v" id="v2">$8,240</div><div class="c">+12%</div></div>
      <div class="s" id="t3"><div class="l">Churn</div><div class="v" id="v3">2.1%</div><div class="c">+1%</div></div></div>`,
    faults: [
      { id: 'card-left-2pt', css: '#t3{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#t3', pt: 2 },
                                                         { kind: 'gap', axis: 'x', between: ['#t2', '#t3'], pt: 2, alt: true }] },
      { id: 'padding-3pt', css: '#t1{padding:16px 16px 16px 19px}', truth: [{ kind: 'padding', el: '#t1', pt: 3 }] },
      { id: 'number-2pt', css: '#v2{top:2px}', truth: [{ kind: 'edge', axis: 'y', el: '#v2', pt: 2 }] },
    ],
  },

  login: {
    size: [420, 420],
    css: `
      body{margin:0;background:#e9e9ee;font:13px ${FONT};color:#1d1d1f}
      .card{margin:30px auto;width:300px;background:#fff;border-radius:14px;padding:28px 30px}
      h3{margin:0 0 18px;font-size:20px;line-height:24px}
      .f{height:32px;border:1px solid #c7c7cc;border-radius:7px;box-sizing:border-box;margin-bottom:12px;position:relative}
      .b{height:34px;border-radius:8px;background:#0a84ff;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:600;position:relative;margin-top:6px}
      .k{margin-top:14px;color:#0a84ff;line-height:16px}`,
    html: `<div class="card"><h3>Sign in</h3><div class="f" id="f0"></div><div class="f" id="f1"></div><div class="f" id="f2"></div>
      <div class="b" id="b">Continue</div><div class="k">Forgot password?</div></div>`,
    faults: [
      { id: 'field-width-2pt', css: '#f1{width:298px}', truth: [{ kind: 'edge', axis: 'x', el: '#f1', pt: 2 }] },
      { id: 'field-gap-1pt', css: '#f1{margin-bottom:13px}', truth: [{ kind: 'gap', axis: 'y', between: ['#f1', '#f2'], pt: 1 }] },
      { id: 'button-1pt', css: '#b{left:1px}', truth: [{ kind: 'edge', axis: 'x', el: '#b', pt: 1 }] },
    ],
  },

  player: {
    size: [440, 180],
    css: `
      body{margin:0;background:#141414;font:13px ${FONT};color:#fff}
      .row{display:flex;gap:16px;padding:40px 60px 0;align-items:center}
      .p{width:44px;height:44px;border-radius:22px;background:#2c2c2e;position:relative}
      .p.main{background:#fff}
      .bar{margin:28px 60px 0;height:4px;border-radius:2px;background:#3a3a3c;width:320px}`,
    html: `<div class="row"><div class="p" id="q0"></div><div class="p" id="q1"></div><div class="p main" id="q2"></div>
      <div class="p" id="q3"></div><div class="p" id="q4"></div></div><div class="bar"></div>`,
    faults: [
      { id: 'button-top-2pt', css: '#q3{top:2px}', truth: [{ kind: 'edge', axis: 'y', el: '#q3', pt: 2 }] },
      { id: 'gap-1pt', css: '#q1{margin-left:1px}', truth: [{ kind: 'gap', axis: 'x', between: ['#q0', '#q1'], pt: 1 }] },
    ],
  },

  tabbar: {
    size: [420, 140],
    css: `
      body{margin:0;background:#fafafa;font:11px ${FONT};color:#8e8e93}
      .bar{position:absolute;left:0;right:0;top:40px;height:64px;border-top:1px solid #d1d1d6;display:flex;background:#fff}
      .t{flex:1;display:flex;flex-direction:column;align-items:center;padding-top:8px}
      .i{width:24px;height:24px;border-radius:6px;background:#c7c7cc;position:relative}
      .t.on .i{background:#0a84ff}.t.on{color:#0a84ff}
      .t span{margin-top:4px;line-height:13px;position:relative}`,
    html: `<div class="bar"><div class="t on"><div class="i" id="i0"></div><span id="n0">Home</span></div>
      <div class="t"><div class="i" id="i1"></div><span id="n1">Search</span></div>
      <div class="t"><div class="i" id="i2"></div><span id="n2">Library</span></div>
      <div class="t"><div class="i" id="i3"></div><span id="n3">Profile</span></div></div>`,
    faults: [
      { id: 'label-2pt', css: '#n2{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#n2', pt: 2 }] },
      { id: 'icon-top-1pt', css: '#i1{top:1px}', truth: [{ kind: 'edge', axis: 'y', el: '#i1', pt: 1 }] },
    ],
  },

  table: {
    size: [460, 260],
    css: `
      body{margin:0;background:#fff;font:13px ${FONT};color:#1d1d1f}
      table{margin:24px;border-collapse:collapse}
      td{height:36px;padding:0 24px 0 0;border-bottom:1px solid #e5e5ea}
      td span{position:relative}
      th{text-align:left;height:28px;color:#6e6e73;font-weight:600;padding:0 24px 0 0;border-bottom:1px solid #c7c7cc}`,
    html: `<table><tr><th>Name</th><th>Size</th><th>Modified</th></tr>
      <tr><td><span>Report.pdf</span></td><td><span>2.4 MB</span></td><td><span>Today</span></td></tr>
      <tr><td><span>Budget.numbers</span></td><td><span id="c22">380 KB</span></td><td><span>Yesterday</span></td></tr>
      <tr><td><span>Slides.key</span></td><td><span>18 MB</span></td><td><span id="c33">Oct 3</span></td></tr>
      <tr><td><span>Notes.txt</span></td><td><span>4 KB</span></td><td><span>Sep 28</span></td></tr></table>`,
    faults: [
      { id: 'cell-2pt', css: '#c22{left:2px}', truth: [{ kind: 'edge', axis: 'x', el: '#c22', pt: 2 }] },
      { id: 'cell-3pt', css: '#c33{left:3px}', truth: [{ kind: 'edge', axis: 'x', el: '#c33', pt: 3 }] },
    ],
  },
};

// MARK: Photographing them

const port = 9300 + Math.floor(Math.random() * 500);
const profile = mkdtempSync(join(tmpdir(), 'misalign-chrome-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', '--no-first-run', '--no-default-browser-check', 'about:blank',
], { stdio: 'ignore' });
const killChrome = () => { try { chrome.kill('SIGKILL'); } catch {} try { rmSync(profile, { recursive: true, force: true }); } catch {} };
process.on('exit', killChrome);
const watchdog = setTimeout(() => { console.error('corpus: gave up after 4 minutes'); process.exit(2); }, 4 * 60 * 1000);

async function connect() {
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = list.find(t => t.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('Chrome did not open its debugging port');
}
const ws = new WebSocket(await connect());
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let seq = 0; const waiting = new Map();
ws.onmessage = m => {
  const msg = JSON.parse(m.data);
  if (msg.id && waiting.has(msg.id)) { const { res, rej } = waiting.get(msg.id); waiting.delete(msg.id); msg.error ? rej(new Error(msg.error.message)) : res(msg.result); }
};
const send = (method, params = {}) => new Promise((res, rej) => { const id = ++seq; waiting.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params })); });
const evalJS = async expr => (await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result.value;

await send('Page.enable');

/// The box of `selector` in the picture's pixels, top-left origin.
const boxJS = sel => `(() => { const r = document.querySelector(${JSON.stringify(sel)}).getBoundingClientRect();
  return { x: r.left * ${SCALE}, y: r.top * ${SCALE}, width: r.width * ${SCALE}, height: r.height * ${SCALE} }; })()`;

/// The PNG marked 144 pixels per inch, as a Mac's own Retina screenshot is,
/// so Photonz opens it at 2x exactly as it opens one of those.
function retina(png) {
  const ppm = Math.round(144 / 0.0254);
  const body = Buffer.alloc(13);
  body.write('pHYs', 0, 'ascii');
  body.writeUInt32BE(ppm, 4);
  body.writeUInt32BE(ppm, 8);
  body.writeUInt8(1, 12);
  const chunk = Buffer.alloc(21);
  chunk.writeUInt32BE(9, 0);
  body.copy(chunk, 4);
  chunk.writeUInt32BE(crc32(body) >>> 0, 17);
  const ihdrEnd = 8 + 8 + 13 + 4;
  return Buffer.concat([png.subarray(0, ihdrEnd), chunk, png.subarray(ihdrEnd)]);
}

async function shoot(name, page, extraCSS) {
  const [w, h] = page.size;
  await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: SCALE, mobile: false });
  const doc = `<!doctype html><html><head><meta charset="utf-8"><style>${page.css}${extraCSS || ''}</style></head><body>${page.html}</body></html>`;
  await evalJS(`document.open(); document.write(${JSON.stringify(doc)}); document.close(); document.fonts.ready.then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(true)))))`);
  const shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: w, height: h, scale: 1 } });
  writeFileSync(join(OUT, `${name}.png`), retina(Buffer.from(shot.data, 'base64')));
}

const truth = { scale: SCALE, cases: [] };
const every = [...Object.entries(pages).map(([n, p]) => [n, p, 'climb']),
               ...Object.entries(heldOut).map(([n, p]) => [n, p, 'held-out'])];
for (const [pageName, page, set] of every) {
  await shoot(`${pageName}-clean`, page, '');
  truth.cases.push({ name: `${pageName}-clean`, set, faults: [] });
  for (const fault of page.faults) {
    const name = `${pageName}-${fault.id}`;
    await shoot(name, page, fault.css);
    const faults = [];
    for (const t of fault.truth) {
      const entry = { kind: t.kind, pt: t.pt };
      if (t.axis) entry.axis = t.axis;
      if (t.alt) entry.alternative = true;
      if (t.el) entry.box = await evalJS(boxJS(t.el));
      if (t.between) {
        const a = await evalJS(boxJS(t.between[0])), b = await evalJS(boxJS(t.between[1]));
        // The space between the two, where a gap mark lands.
        entry.box = t.axis === 'x'
          ? { x: a.x + a.width, y: Math.min(a.y, b.y), width: b.x - (a.x + a.width), height: Math.max(a.y + a.height, b.y + b.height) - Math.min(a.y, b.y) }
          : { x: Math.min(a.x, b.x), y: a.y + a.height, width: Math.max(a.x + a.width, b.x + b.width) - Math.min(a.x, b.x), height: b.y - (a.y + a.height) };
      }
      faults.push(entry);
    }
    truth.cases.push({ name, set, faults });
  }
}
writeFileSync(join(OUT, 'truth.json'), JSON.stringify(truth, null, 1) + '\n');
console.log(`corpus: ${truth.cases.length} pictures in ${OUT}`);
clearTimeout(watchdog);
ws.close();
killChrome();
process.exit(0);
