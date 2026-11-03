import AppKit
import PhotonzCore
import WebKit

/// Opens a web page for Ask, the way app code and not a model opens it
/// (`docs/design/ask.md`, "A web page from its address"). A throwaway web view
/// with its own empty store (no cookies, no logins, nothing saved), no new
/// windows, no downloads, no file or script addresses, and once the page has
/// started showing, no going anywhere else. It reads the page's top at the
/// canvas's size into a picture and a checked description (`AskWebPage`),
/// and that is all a model ever sees of it. Every address the view asked
/// for is kept, for the trace and the eval's network check.
@MainActor
final class AskWebReader: NSObject, WKNavigationDelegate, WKUIDelegate {

    struct Read {
        let page: AskWebPage
        /// The top of the page at one pixel a point, for the model.
        let png: Data
        /// Each picture part, cut from the page at its full sharpness, by id.
        let pictures: [String: CGImage]
        /// Every address the page loaded, the typed one first.
        let requests: [String]
    }

    enum Trouble: Error { case couldNotOpen, nothingRead }

    /// The longest the page may take to load. What has shown by then is read.
    static let seconds: Double = 20
    /// A moment for late layout and fonts once the page says it is loaded.
    static let settle: Double = 1.2

    private let view: WKWebView
    private let address: URL
    private var committed = false
    private var finished = false
    private var failed = false
    private(set) var requests: [String] = []

    private init(address: URL, size: CGSize) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isElementFullscreenEnabled = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.allowsAirPlayForMediaPlayback = false
        view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        self.address = address
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
    }

    /// Reads the page at `address` (an address the person typed: `AskWeb.address(in:)`)
    /// at `size` points.
    static func read(_ address: URL, size: CGSize) async -> Result<Read, Trouble> {
        let reader = AskWebReader(address: address, size: size)
        defer { reader.close() }
        return await reader.read()
    }

    private func read() async -> Result<Read, Trouble> {
        view.load(URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.seconds))
        let start = Date()
        while !finished, !failed, Date().timeIntervalSince(start) < Self.seconds, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard committed, !Task.isCancelled else { return .failure(.couldNotOpen) }
        try? await Task.sleep(for: .milliseconds(Int(Self.settle * 1000)))
        // The page's own scrolling put back to its top.
        _ = try? await view.evaluateJavaScript("window.scrollTo(0, 0); 0")
        guard let said = try? await view.evaluateJavaScript(Self.reading) as? String,
              let page = AskWebPage.checked(Data(said.utf8), address: address, viewport: view.frame.size) else {
            return .failure(.nothingRead)
        }
        if let loaded = (try? AgentJSON.parse(Data(said.utf8)))?["loaded"]?.arrayValue {
            for entry in loaded.prefix(400) {
                if let name = entry.stringValue, !requests.contains(name) { requests.append(name) }
            }
        }
        guard let snapshot = await snapshot() else { return .failure(.nothingRead) }
        // The pictures are cut from the page with everything else made
        // see-through: cut from the page as shown, a hero picture carried its
        // own headline and buttons, and the words landed twice (apple.com,
        // 2026-11-03).
        var pictures: [String: CGImage] = [:]
        if page.parts.contains(where: { $0.kind == .image }) {
            view.setValue(false, forKey: "drawsBackground")
            _ = try? await view.evaluateJavaScript(Self.picturesOnly)
            try? await Task.sleep(for: .milliseconds(150))
            if let bare = await self.snapshot() {
                let scale = CGFloat(bare.width) / max(1, view.frame.width)
                for part in page.parts where part.kind == .image {
                    let box = CGRect(x: part.frame.minX * scale, y: part.frame.minY * scale,
                                     width: part.frame.width * scale, height: part.frame.height * scale).integral
                    if let cut = bare.cropping(to: box) { pictures[part.id] = cut }
                }
            }
        }
        guard let png = Self.png(snapshot, width: Int(view.frame.width), height: Int(view.frame.height)) else {
            return .failure(.nothingRead)
        }
        return .success(Read(page: page, png: png, pictures: pictures, requests: requests))
    }

    private func snapshot() async -> CGImage? {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: view.frame.size)
        config.afterScreenUpdates = true
        guard let image = try? await view.takeSnapshot(configuration: config) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// The picture at one pixel a point, as PNG.
    private static func png(_ image: CGImage, width: Int, height: Int) -> Data? {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    private func close() {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }

    // MARK: Where the page may go

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let main = action.targetFrame?.isMainFrame ?? true
        let scheme = url.scheme?.lowercased() ?? ""
        // A frame the page holds may be blank; nothing may be a file, a script or a download.
        let web = scheme == "http" || scheme == "https"
        guard web || (!main && (scheme == "about" || scheme == "blob")) else { return .cancel }
        guard !action.shouldPerformDownload else { return .cancel }
        // Once the page has started showing, it stays where it is.
        if main && committed { return .cancel }
        if web { requests.append(url.absoluteString) }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        response.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { committed = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { failed = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        failed = true
    }

    // No windows, no panels, no files.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {}
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool { false }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? { nil }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? { nil }

    // MARK: Reading it

    /// Leaves only the pictures showing: every word, fill, edge and shadow
    /// made see-through, the page's own background too, while images, SVGs,
    /// canvases, videos and background pictures paint as they were. Words
    /// painted with a gradient lose the gradient.
    static let picturesOnly = #"""
    (() => {
      // An SVG paints in its parent's text colour: it keeps the one it had.
      for (const svg of document.querySelectorAll('svg')) {
        svg.style.setProperty('color', getComputedStyle(svg).color, 'important');
      }
      const style = document.createElement('style');
      style.textContent = `
        *:not(svg):not(svg *), *:not(svg):not(svg *)::before, *:not(svg):not(svg *)::after {
          color: transparent !important; -webkit-text-fill-color: transparent !important;
          text-shadow: none !important; background-color: transparent !important;
          border-color: transparent !important; box-shadow: none !important;
          outline-color: transparent !important; text-decoration-color: transparent !important;
          caret-color: transparent !important;
        }`;
      document.documentElement.appendChild(style);
      for (const el of document.querySelectorAll('*')) {
        const cs = getComputedStyle(el);
        if (cs.webkitBackgroundClip === 'text' || cs.backgroundClip === 'text') {
          el.style.setProperty('background-image', 'none', 'important');
        }
      }
      return 0;
    })()
    """#

    /// Walks the page as drawn: every box with a fill or an edge, every run of
    /// words a person can see (not hidden, clipped away, see-through or off the
    /// top), and every picture, with their places, paint and type, in paint
    /// order. Plain data only; `AskWebPage.checked` checks every field.
    static let reading = #"""
(() => {
  const W = window.innerWidth, H = window.innerHeight;
  const parts = [];
  const opacityOf = new Map();
  const clipOf = new Map();
  const view = { l: 0, t: 0, r: W, b: H };
  const inter = (a, b) => ({ l: Math.max(a.l, b.l), t: Math.max(a.t, b.t), r: Math.min(a.r, b.r), b: Math.min(a.b, b.b) });
  const area = (a) => Math.max(0, a.r - a.l) * Math.max(0, a.b - a.t);
  const rectOf = (r) => ({ l: r.left, t: r.top, r: r.right, b: r.bottom });
  const px = (v) => { const n = parseFloat(v); return isFinite(n) ? n : 0; };
  const clear = (c) => !c || c === 'transparent' || /rgba\([^)]*,\s*0(\.0+)?\)$/.test(c);
  function opacity(el) {
    if (!el || el.nodeType !== 1) return 1;
    if (opacityOf.has(el)) return opacityOf.get(el);
    const cs = getComputedStyle(el);
    let o = (parseFloat(cs.opacity) || 0) * opacity(el.parentElement);
    if (cs.visibility === 'hidden' || cs.visibility === 'collapse') o = 0;
    opacityOf.set(el, o);
    return o;
  }
  function clip(el) {
    if (!el || el.nodeType !== 1) return view;
    if (clipOf.has(el)) return clipOf.get(el);
    const parent = el.parentElement;
    let c = parent ? clip(parent) : view;
    const cs = getComputedStyle(el);
    if (cs.position === 'fixed') c = view;
    if (cs.overflowX !== 'visible' || cs.overflowY !== 'visible' || (cs.clip && cs.clip !== 'auto') || (cs.clipPath && cs.clipPath !== 'none')) {
      c = inter(c, rectOf(el.getBoundingClientRect()));
    }
    clipOf.set(el, c);
    return c;
  }
  const stackOf = new Map();
  // The stacking contexts from the page down to this element, each its
  // z-index: compared in order, so a nav bar's own links paint above it.
  function stack(el) {
    if (!el || el.nodeType !== 1) return [];
    if (stackOf.has(el)) return stackOf.get(el);
    const cs = getComputedStyle(el);
    let path = stack(el.parentElement);
    // A positioned element paints above the page's flow around it, at its
    // z-index, or at 0 when it has none.
    if (cs.position !== 'static') path = path.concat([cs.zIndex === 'auto' ? 0 : (parseInt(cs.zIndex) || 0)]);
    stackOf.set(el, path);
    return path;
  }
  function compare(a, b) {
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
      const x = i < a.length ? a[i] : -0.5, y = i < b.length ? b[i] : -0.5;
      if (x !== y) return x - y;
    }
    return 0;
  }
  const box = (r) => ({ x: r.l, y: r.t, w: r.r - r.l, h: r.b - r.t });
  let order = 0;
  function push(part, el) { part.z = stack(el); part.o = order++; parts.push(part); }
  function transform(text, cs) {
    switch (cs.textTransform) {
      case 'uppercase': return text.toUpperCase();
      case 'lowercase': return text.toLowerCase();
      case 'capitalize': return text.replace(/\b\w/g, (m) => m.toUpperCase());
      default: return text;
    }
  }
  function words(el, cs, text, r, lines) {
    let color = cs.color;
    // Words painted with a gradient show the gradient's first colour.
    const clipped = cs.webkitBackgroundClip === 'text' || cs.backgroundClip === 'text';
    if (clear(color) && clipped) {
      const inks = (cs.backgroundImage || '').match(/rgba?\([^)]*\)/g) || [];
      const first = inks.find((c) => !clear(c));
      if (first) color = first;
    }
    push({ kind: 'text', text: transform(text, cs), ...box(r), fontSize: px(cs.fontSize),
           weight: cs.fontWeight === 'bold' ? 700 : cs.fontWeight === 'normal' ? 400 : px(cs.fontWeight),
           family: cs.fontFamily, color, align: cs.textAlign, lines }, el);
  }
  function element(el) {
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return false;
    const tag = el.tagName.toLowerCase();
    if (['script', 'style', 'noscript', 'template', 'head', 'meta', 'link'].includes(tag)) return false;
    const o = opacity(el);
    if (o < 0.05) return false;
    const seen = inter(inter(rectOf(el.getBoundingClientRect()), clip(el.parentElement)), view);
    const shows = area(seen) >= 1 && seen.r - seen.l >= 1 && seen.b - seen.t >= 1;
    if (shows) {
      const picture = ['img', 'svg', 'canvas', 'video', 'picture', 'iframe'].includes(tag) || (cs.backgroundImage && cs.backgroundImage.includes('url('));
      if (!clear(cs.backgroundColor) || tag === 'html') {
        if (!clear(cs.backgroundColor)) push({ kind: 'box', ...box(seen), fill: cs.backgroundColor, radius: px(cs.borderTopLeftRadius) }, el);
      }
      const sides = ['Top', 'Right', 'Bottom', 'Left'].map((s) => ({ s, w: px(cs['border' + s + 'Width']), c: cs['border' + s + 'Color'], st: cs['border' + s + 'Style'] }))
        .filter((d) => d.w > 0 && d.st !== 'none' && d.st !== 'hidden' && !clear(d.c));
      const r = rectOf(el.getBoundingClientRect());
      if (sides.length === 4 && sides.every((d) => d.w === sides[0].w && d.c === sides[0].c)) {
        push({ kind: 'box', ...box(seen), stroke: sides[0].c, strokeWidth: sides[0].w, radius: px(cs.borderTopLeftRadius) }, el);
      } else {
        for (const d of sides) {
          let e;
          if (d.s === 'Top') e = { l: r.l, t: r.t, r: r.r, b: r.t + d.w };
          if (d.s === 'Bottom') e = { l: r.l, t: r.b - d.w, r: r.r, b: r.b };
          if (d.s === 'Left') e = { l: r.l, t: r.t, r: r.l + d.w, b: r.b };
          if (d.s === 'Right') e = { l: r.r - d.w, t: r.t, r: r.r, b: r.b };
          const s = inter(inter(e, clip(el.parentElement)), view);
          if (area(s) >= 1) push({ kind: 'box', ...box(s), fill: d.c }, el);
        }
      }
      if (picture) { push({ kind: 'image', ...box(seen) }, el); }
      if (['input', 'textarea', 'select', 'button'].includes(tag) && tag !== 'button') {
        const value = tag === 'select' ? (el.selectedOptions[0] || {}).text : (el.value || el.placeholder || '');
        if (value && el.type !== 'hidden' && el.type !== 'checkbox' && el.type !== 'radio') {
          const pad = { l: seen.l + px(cs.paddingLeft) + px(cs.borderLeftWidth), r: seen.r - px(cs.paddingRight), t: seen.t, b: seen.b };
          const size = px(cs.fontSize);
          const mid = (seen.t + seen.b) / 2;
          let ink = cs.color;
          if (!el.value) { try { ink = getComputedStyle(el, '::placeholder').color || ink; } catch (e) {} }
          words(el, { ...cs, color: ink, textTransform: cs.textTransform, fontSize: cs.fontSize, fontWeight: cs.fontWeight, fontFamily: cs.fontFamily, textAlign: cs.textAlign },
                value, { l: pad.l, r: pad.r, t: mid - size * 0.6, b: mid + size * 0.6 }, 1);
        }
      }
      if (['svg', 'canvas', 'video', 'iframe', 'img', 'picture'].includes(tag)) return false;
    }
    return true;
  }
  function walk(node) {
    for (let child = node.firstChild; child; child = child.nextSibling) {
      if (child.nodeType === 1) {
        if (element(child)) walk(child);
      } else if (child.nodeType === 3) {
        const raw = child.textContent;
        if (!raw || !raw.trim()) continue;
        const el = child.parentElement;
        if (!el || opacity(el) < 0.05) continue;
        const cs = getComputedStyle(el);
        const range = document.createRange();
        range.selectNodeContents(child);
        const c = inter(clip(el), view);
        let u = null; const tops = new Set(); let full = 0, kept = 0;
        for (const rr of range.getClientRects()) {
          if (rr.width < 1 || rr.height < 1) continue;
          const r = rectOf(rr);
          full += area(r);
          const s = inter(r, c);
          if (area(s) < 1) continue;
          kept += area(s);
          tops.add(Math.round(r.t));
          u = u ? { l: Math.min(u.l, r.l), t: Math.min(u.t, r.t), r: Math.max(u.r, r.r), b: Math.max(u.b, r.b) } : r;
        }
        if (!u || kept < full * 0.6) continue;
        // Words the edge of the page's top cuts through are left for the
        // next screen: measured whole, they hung off the canvas.
        if (u.b > H + 1 || u.r > W + 1 || u.t < -1 || u.l < -1) continue;
        words(el, cs, raw, inter(u, view), tops.size);
      }
    }
  }
  const root = document.documentElement;
  const rootStyle = getComputedStyle(root), bodyStyle = document.body ? getComputedStyle(document.body) : rootStyle;
  const background = !clear(bodyStyle.backgroundColor) ? bodyStyle.backgroundColor : !clear(rootStyle.backgroundColor) ? rootStyle.backgroundColor : 'rgb(255, 255, 255)';
  if (document.body) walk(document.body);
  parts.sort((a, b) => compare(a.z, b.z) || (a.o - b.o));
  for (const p of parts) { delete p.z; delete p.o; }
  const loaded = performance.getEntriesByType('resource').map((e) => e.name).slice(0, 400);
  return JSON.stringify({ title: document.title, background, parts, loaded });
})()
"""#
}
