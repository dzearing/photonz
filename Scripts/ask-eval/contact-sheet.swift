// One PNG of every case in an eval run, each picture with its name and score
// under it (Scripts/ask-eval/README.md).
//
//   swift Scripts/ask-eval/contact-sheet.swift <out.png> <title> <picture> <label> [<picture> <label> ...]
//
// A picture path that does not exist draws an empty cell with its label.
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, (args.count - 2) % 2 == 0 else {
    FileHandle.standardError.write("usage: contact-sheet.swift <out.png> <title> (<picture> <label>)...\n".data(using: .utf8)!)
    exit(1)
}
let out = args[0]
let title = args[1]
let cells = stride(from: 2, to: args.count, by: 2).map { (args[$0], args[$0 + 1]) }

let columns = min(5, max(1, cells.count))
let rows = (cells.count + columns - 1) / columns
let cellWidth: CGFloat = 400, pictureHeight: CGFloat = 284, labelHeight: CGFloat = 52, pad: CGFloat = 16, header: CGFloat = 56
let width = CGFloat(columns) * (cellWidth + pad) + pad
let height = header + CGFloat(rows) * (pictureHeight + labelHeight + pad) + pad

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let flip = NSAffineTransform()
flip.translateX(by: 0, yBy: height)
flip.scaleX(by: 1, yBy: -1)
flip.concat()

NSColor(white: 0.12, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

func draw(_ string: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    let text = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ])
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    text.draw(with: NSRect(x: 0, y: 0, width: rect.width, height: rect.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    NSGraphicsContext.restoreGraphicsState()
}

draw(title, in: NSRect(x: pad, y: 16, width: width - 2 * pad, height: 30), size: 20, weight: .semibold, color: .white)

for (index, cell) in cells.enumerated() {
    let x = pad + CGFloat(index % columns) * (cellWidth + pad)
    let y = header + CGFloat(index / columns) * (pictureHeight + labelHeight + pad)
    let frame = NSRect(x: x, y: y, width: cellWidth, height: pictureHeight)
    NSColor(white: 0.2, alpha: 1).setFill()
    frame.fill()
    if let image = NSImage(contentsOfFile: cell.0), image.size.width > 0 {
        let scale = min(cellWidth / image.size.width, pictureHeight / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let target = NSRect(x: x + (cellWidth - size.width) / 2, y: y + (pictureHeight - size.height) / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current!.cgContext
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        image.draw(in: NSRect(origin: .zero, size: target.size))
        NSGraphicsContext.restoreGraphicsState()
    }
    let lines = cell.1.components(separatedBy: "\n")
    draw(lines[0], in: NSRect(x: x, y: y + pictureHeight + 6, width: cellWidth, height: 22), size: 15, weight: .semibold, color: .white)
    if lines.count > 1 {
        draw(lines[1], in: NSRect(x: x, y: y + pictureHeight + 27, width: cellWidth, height: 20), size: 12, weight: .regular, color: NSColor(white: 0.75, alpha: 1))
    }
}
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
