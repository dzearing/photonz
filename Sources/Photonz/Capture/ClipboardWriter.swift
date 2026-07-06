import AppKit
import UniformTypeIdentifiers

/// Writes a media *file* to the general pasteboard with every flavor a paste
/// target might read. Native apps (Finder, Mail) take the modern
/// `public.file-url`; Chromium/Electron apps (Teams, Slack) historically read
/// only the legacy `NSFilenamesPboardType` plist for file pastes — omitting it
/// is why "copy recording → paste into Teams" silently did nothing. Optional
/// `data` adds an inline flavor (e.g. GIF bytes) for targets that paste content
/// rather than attach files.
@MainActor
enum ClipboardWriter {
    static func writeFile(_ url: URL, data: Data? = nil, dataType: UTType? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let data, let dataType {
            item.setData(data, forType: NSPasteboard.PasteboardType(dataType.identifier))
        }
        pasteboard.writeObjects([item])
        // Legacy flavor: an array-of-paths property list under the pre-UTI type
        // name. Attaches to the pasteboard's first item.
        pasteboard.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }
}
