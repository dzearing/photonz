import AppKit
import WebKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func report(_ name: String, _ tv: NSTextView) {
    var images = 0
    tv.textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: tv.textStorage?.length ?? 0)) { v, _, _ in if v != nil { images += 1 } }
    let text = tv.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    print("\(name): images=\(images) text=\(text.isEmpty ? "(none)" : text.debugDescription)")
}
let win = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
// TextEdit's rich document: rich text, imports graphics. Its plain mode: neither.
let rich = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300)); rich.isRichText = true; rich.importsGraphics = true
let plain = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300)); plain.isRichText = false; plain.importsGraphics = false
let richNoGraphics = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300)); richNoGraphics.isRichText = true; richNoGraphics.importsGraphics = false
for tv in [rich, plain, richNoGraphics] { win.contentView = tv; win.makeFirstResponder(tv); tv.paste(nil) }
report("NSTextView rich + graphics (TextEdit rich document)", rich)
report("NSTextView plain (TextEdit plain text document)", plain)
report("NSTextView rich, no graphics", richNoGraphics)

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 900))
win.contentView = web
win.orderFrontRegardless(); win.makeKey()
// webkit <path to index.html>
let page = URL(fileURLWithPath: CommandLine.arguments[1])
web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
Task { @MainActor in
    try await Task.sleep(for: .seconds(2))
    for box in ["plain", "rich"] {
        _ = try? await web.evaluateJavaScript("document.getElementById('\(box)').focus(); 1")
        win.makeFirstResponder(web)
        try await Task.sleep(for: .milliseconds(200))
        web.perform(Selector(("paste:")), with: nil)
        try await Task.sleep(for: .milliseconds(800))
    }
    let json = try await web.evaluateJavaScript("JSON.stringify(window.records.map(r => ({box: r.box, types: r.types, files: r.files, landed: r.landed.images ? {images: r.landed.images.length, text: r.landed.text} : {text: r.landed.text.slice(0, 50)}})))")
    print("WKWebView (WebKit) page: \(json ?? "nil")")
    exit(0)
}
app.run()
