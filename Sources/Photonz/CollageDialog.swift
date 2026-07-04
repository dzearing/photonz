import PhotonzCore
import SwiftUI

/// The Layer → Arrange in Collage… sheet: template, page format, gutter, and
/// backdrop for laying the selected (or all) photo layers into cells. The
/// layout itself is Collage (PhotonzCore); this sheet only gathers options.
struct CollageDialog: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss
    @State private var template: CollageTemplate = .grid
    @State private var format: PageFormat = .current
    @State private var gutter: Double = 24
    @State private var backdrop: Backdrop = .white
    private let canvasSize: CGSize
    private let itemCount: Int

    init(canvasSize: CGSize, itemCount: Int) {
        self.canvasSize = canvasSize
        self.itemCount = itemCount
    }

    /// Page aspect presets. The canvas keeps its width; height follows.
    enum PageFormat: String, CaseIterable {
        case current = "Current"
        case square = "Square"
        case fourThree = "4:3"
        case sixteenNine = "16:9"

        private var ratio: CGFloat? {
            switch self {
            case .current: nil
            case .square: 1
            case .fourThree: 4.0 / 3.0
            case .sixteenNine: 16.0 / 9.0
            }
        }

        func canvasSize(from current: CGSize) -> CGSize? {
            ratio.map { CGSize(width: current.width, height: (current.width / $0).rounded()) }
        }
    }

    enum Backdrop: String, CaseIterable {
        case none = "None"
        case white = "White"
        case black = "Black"

        var cgColor: CGColor? {
            switch self {
            case .none: nil
            case .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            case .black: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Arrange in Collage")
                .font(.headline)
            Text("\(itemCount) photo layers")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                labeled("Layout") {
                    Picker("", selection: $template) {
                        ForEach(CollageTemplate.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                labeled("Page") {
                    Picker("", selection: $format) {
                        ForEach(PageFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                labeled("Backdrop") {
                    Picker("", selection: $backdrop) {
                        ForEach(Backdrop.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                labeled("Spacing") {
                    HStack(spacing: 6) {
                        TextField("Spacing", value: $gutter,
                                  format: .number.precision(.fractionLength(0)).grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                        Text("px")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Arrange") {
                    editorState.arrangeCollage(template: template,
                                               gutter: CGFloat(max(0, gutter)),
                                               canvasSize: format.canvasSize(from: canvasSize),
                                               backgroundColor: backdrop.cgColor)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(itemCount < 2)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
