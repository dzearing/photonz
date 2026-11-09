import Foundation

/// The page Preview as Web Page writes around an icon, so it can be tried the
/// way it will be used: inside a button that plays it while the pointer is on
/// the button, at the sizes icons are set at, on a light page and a dark one,
/// and once more on its own going round.
///
/// Plain HTML with the SVG written inline and a few lines of script: nothing
/// is fetched, so it works opened from a temporary folder with no network.
/// Every copy of the icon on the page gets ids of its own
/// (`SVGPlayback.uniquingIDs`), so a hover reaches the copy under the pointer
/// and no other.
public enum SVGPreviewPage {

    /// The sizes an icon is shown at, in CSS pixels.
    public static let sizes = [16, 24, 32, 48, 96]

    /// The id the icon carries in the SVG the page copies.
    public static let iconID = SVGPlayback.defaultID

    /// The whole page. `svg` is the file exactly as Export writes it, before
    /// `playback` is applied; `name` is what the page and its button are
    /// called.
    public static func html(svg: String, name: String, playback: SVGPlayback) -> String {
        let chosen = playback.apply(to: svg, id: iconID)
        let looping = SVGPlayback(plays: .always, ink: playback.ink).apply(to: svg, id: iconID)
        let title = escaped(name.isEmpty ? "Icon" : name)

        func copy(_ text: String, _ suffix: String) -> String {
            SVGPlayback.uniquingIDs(in: text, suffix: suffix)
        }
        func strip(_ scheme: String) -> String {
            var cells = ["      <button class=\"try-button\" type=\"button\" data-plays=\"\(playback.plays.rawValue)\">"
                + copy(chosen, "_button_\(scheme)") + "<span>\(title)</span></button>"]
            for size in sizes {
                cells.append("      <div class=\"cell\" data-size=\"\(size)\">"
                    + "<div class=\"box\" style=\"width:\(size)px;height:\(size)px\">"
                    + copy(chosen, "_\(size)_\(scheme)") + "</div><span>\(size)</span></div>")
            }
            return "    <div class=\"strip \(scheme)\">\n" + cells.joined(separator: "\n") + "\n    </div>"
        }

        let hint = playback.plays == .onHover ? "<p class=\"hint\">Point at an icon or a button to play it.</p>" : ""
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
        \(style)
        </style>
        </head>
        <body>
          <header>
            <h1>\(title)</h1>
            <span class="chip">Plays <b>\(playback.plays.title)</b></span>
            <span class="chip">Colour <b>\(playback.ink.title)</b></span>
            <div class="actions">
              <button type="button" data-copy="svg-source">Copy SVG</button>
              <button type="button" data-copy="html-source">Copy HTML</button>
              <button type="button" onclick="location.reload()">Refresh</button>
            </div>
          </header>
          \(hint)
          <section>
            <h2>Light</h2>
        \(strip("light"))
          </section>
          <section>
            <h2>Dark</h2>
        \(strip("dark"))
          </section>
          <section>
            <h2>Going round</h2>
            <div class="strip light loop">
              <div class="cell" data-plays="always"><div class="box">\(copy(looping, "_loop"))</div><span>96</span></div>
            </div>
          </section>
          <textarea id="svg-source" hidden>\(escaped(chosen))</textarea>
          <textarea id="html-source" hidden>\(escaped(snippet(svg: svg, name: name, playback: playback)))</textarea>
        <script>
        \(script)
        </script>
        </body>
        </html>

        """
    }

    /// What Copy HTML hands over: the icon in a button, ready to paste into a
    /// page. A button whose icon plays on hover carries the few lines that
    /// hand the button's hover to the icon, so the whole button is the target
    /// rather than only the icon inside it.
    public static func snippet(svg: String, name: String, playback: SVGPlayback) -> String {
        var icon = playback.apply(to: svg, id: iconID)
        let label = escaped(name.isEmpty ? "Icon" : name)
        guard playback.plays == .onHover else {
            return "<button type=\"button\" class=\"icon-button\">\n\(icon)<span>\(label)</span>\n</button>\n"
        }
        // The icon takes no pointer of its own, so moving from it to the
        // button's words does not count as leaving.
        icon = icon.replacingOccurrences(of: "<svg ", with: "<svg style=\"pointer-events: none\" ",
                                         options: [], range: icon.range(of: "<svg "))
        return """
        <button type="button" class="icon-button">
        \(icon)<span>\(label)</span>
        </button>
        <script>
        (function (button) {
          var icon = button.querySelector('svg');
          ['mouseenter', 'mouseleave'].forEach(function (type) {
            button.addEventListener(type, function () { icon.dispatchEvent(new MouseEvent(type)); });
          });
        })(document.currentScript.previousElementSibling);
        </script>

        """
    }

    /// Text made safe to sit in HTML, as text or inside an attribute.
    public static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - The page's own look and behaviour

    static let style = """
    :root { color-scheme: light dark; font: 13px -apple-system, BlinkMacSystemFont, system-ui, sans-serif; }
    body { margin: 0; padding: 28px 32px 40px; background: #f5f5f7; color: #1d1d1f; }
    @media (prefers-color-scheme: dark) { body { background: #161617; color: #f5f5f7; } }
    header { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
    h1 { font-size: 20px; font-weight: 600; margin: 0 8px 0 0; }
    .chip { font-size: 12px; padding: 3px 9px; border-radius: 999px; background: rgba(127,127,127,.16); }
    .actions { margin-left: auto; display: flex; gap: 8px; }
    .actions button { font: inherit; padding: 5px 12px; border-radius: 7px; border: 1px solid rgba(127,127,127,.35);
      background: transparent; color: inherit; cursor: pointer; }
    .actions button:hover { background: rgba(127,127,127,.14); }
    .hint { margin: 14px 0 0; opacity: .7; }
    section { margin-top: 24px; }
    h2 { font-size: 12px; font-weight: 600; margin: 0 0 8px; opacity: .7; }
    .strip { display: flex; align-items: flex-end; gap: 28px; padding: 20px 24px; border-radius: 12px; flex-wrap: wrap; }
    .strip.light { background: #ffffff; color: #1d1d1f; box-shadow: inset 0 0 0 1px rgba(0,0,0,.08); }
    .strip.dark { background: #1c1c1e; color: #f5f5f7; box-shadow: inset 0 0 0 1px rgba(255,255,255,.1); }
    .cell { display: flex; flex-direction: column; align-items: center; gap: 8px; }
    .cell > span { font-size: 11px; opacity: .6; }
    .box svg { width: 100%; height: 100%; display: block; }
    .loop .box { width: 96px; height: 96px; }
    .try-button { display: inline-flex; align-items: center; gap: 8px; padding: 8px 14px 8px 10px; margin-right: 12px;
      font: inherit; font-size: 14px; border-radius: 8px; cursor: pointer; color: inherit;
      border: 1px solid rgba(127,127,127,.35); background: rgba(127,127,127,.08); }
    .try-button:hover { background: rgba(127,127,127,.2); }
    .try-button svg { width: 20px; height: 20px; pointer-events: none; }
    """

    static let script = """
    // The button's hover is the icon's hover: the icon itself takes no pointer,
    // so the whole button is the target.
    document.querySelectorAll('.try-button').forEach(function (button) {
      var icon = button.querySelector('svg');
      ['mouseenter', 'mouseleave'].forEach(function (type) {
        button.addEventListener(type, function () { icon.dispatchEvent(new MouseEvent(type)); });
      });
    });
    document.querySelectorAll('[data-copy]').forEach(function (button) {
      var label = button.textContent;
      button.addEventListener('click', function () {
        var text = document.getElementById(button.dataset.copy).value;
        function fallback() {
          var area = document.createElement('textarea');
          area.value = text; document.body.appendChild(area); area.select();
          document.execCommand('copy'); area.remove();
        }
        var done = navigator.clipboard ? navigator.clipboard.writeText(text).catch(fallback) : Promise.resolve(fallback());
        done.then(function () {
          button.textContent = 'Copied';
          setTimeout(function () { button.textContent = label; }, 1200);
        });
      });
    });
    """
}
