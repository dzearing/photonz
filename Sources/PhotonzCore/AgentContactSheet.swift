import CoreGraphics
import Foundation

/// A grid of frames from a stretch of video, each with its time under it: how
/// an agent sees a whole edit at a glance (`contact_sheet`,
/// `docs/design/agent-mcp.md`). The moments and the geometry live here; the
/// app draws the frames into it.
public enum AgentContactSheet {

    public static let margin: CGFloat = 8
    public static let gap: CGFloat = 8
    public static let labelHeight: CGFloat = 22

    public struct Layout: Hashable, Sendable {
        public let columns: Int
        public let rows: Int
        /// Where each frame goes, top-left origin, in order.
        public let pictures: [CGRect]
        /// The strip under each frame its time is written in.
        public let labels: [CGRect]
        public let size: CGSize
    }

    /// `count` moments spread evenly from `fromMS` to the last frame before
    /// `toMS`, both ends included. A stretch shorter than a frame is one moment.
    public static func times(fromMS: Int, toMS: Int, count: Int) -> [Int] {
        let last = toMS - MovieRef.frameStepMS
        guard count > 1, last > fromMS else { return [fromMS] }
        let step = Double(last - fromMS) / Double(count - 1)
        return (0..<count).map { fromMS + Int((Double($0) * step).rounded()) }
    }

    public static func layout(count: Int, columns asked: Int?, cellWidth: CGFloat,
                              pictureSize: CGSize) -> Layout {
        let count = max(1, count)
        let square = Int(Double(count).squareRoot().rounded(.up))
        let columns = max(1, min(asked ?? square, count))
        let rows = (count + columns - 1) / columns
        let aspect = pictureSize.width > 0 && pictureSize.height > 0 ? pictureSize.height / pictureSize.width : 9.0 / 16
        let pictureHeight = (cellWidth * aspect).rounded()
        let rowHeight = pictureHeight + labelHeight
        var pictures: [CGRect] = []
        var labels: [CGRect] = []
        for index in 0..<count {
            let x = margin + CGFloat(index % columns) * (cellWidth + gap)
            let y = margin + CGFloat(index / columns) * (rowHeight + gap)
            let picture = CGRect(x: x, y: y, width: cellWidth, height: pictureHeight)
            pictures.append(picture)
            labels.append(CGRect(x: x, y: picture.maxY, width: cellWidth, height: labelHeight))
        }
        let size = CGSize(width: margin * 2 + CGFloat(columns) * cellWidth + CGFloat(columns - 1) * gap,
                          height: margin * 2 + CGFloat(rows) * rowHeight + CGFloat(rows - 1) * gap)
        return Layout(columns: columns, rows: rows, pictures: pictures, labels: labels, size: size)
    }

    /// m:ss.t, tenths cut rather than rounded so a label never names a moment
    /// after the frame it is under.
    public static func label(ms: Int) -> String {
        let tenths = max(0, ms) / 100
        let minutes = tenths / 600
        let seconds = (tenths / 10) % 60
        return "\(minutes):" + (seconds < 10 ? "0" : "") + "\(seconds).\(tenths % 10)"
    }
}
