import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// `Layer.resizeScalesUniformly` decides whether a live resize can be previewed
/// by scaling a start-frame sprite (cheap) or must re-render the frame each move
/// (correct for fixed-size detail). Getting it wrong is the "border stretches /
/// anchored edge drifts during a corner-drag" bug: a scaled sprite multiplies a
/// fixed-width stroke and, once padding scales too, walks the opposite corner.
@Suite("Resize preview scaling eligibility")
struct ResizePreviewScalingTests {
    private let frame = CGRect(x: 0, y: 0, width: 100, height: 80)
    private let ref = ImageRef(pixelSize: CGSize(width: 100, height: 80))

    // MARK: Content that scales uniformly — sprite scaling is faithful

    @Test func plainPhotoScalesUniformly() {
        let layer = Layer(name: "Photo", content: .image(ref), frame: frame)
        #expect(layer.resizeScalesUniformly)
    }

    // MARK: Fixed-size decoration on the STYLE — must re-render, not scale

    @Test func borderStrokeBlocksSpriteScaling() {
        var style = LayerStyle()
        style.borderWidth = 4
        let layer = Layer(name: "Bordered", content: .image(ref), frame: frame, style: style)
        // The reported case: scaling the sprite would stretch this stroke.
        #expect(!layer.resizeScalesUniformly)
    }

    @Test func cornerRadiusBlocksSpriteScaling() {
        var style = LayerStyle()
        style.cornerRadius = 12
        let layer = Layer(name: "Rounded", content: .image(ref), frame: frame, style: style)
        #expect(!layer.resizeScalesUniformly)
    }

    @Test func blurBlocksSpriteScaling() {
        var style = LayerStyle()
        style.blurRadius = 8
        let layer = Layer(name: "Blurred", content: .image(ref), frame: frame, style: style)
        #expect(!layer.resizeScalesUniformly)
    }

    @Test func visibleShadowBlocksSpriteScaling() {
        var style = LayerStyle()
        style.shadow = ShadowStyle(radius: 12, opacity: 0.4)
        let layer = Layer(name: "Shadowed", content: .image(ref), frame: frame, style: style)
        // Padding for the shadow scales with the sprite → the anchored edge drifts.
        #expect(!layer.resizeScalesUniformly)
    }

    @Test func invisibleShadowDoesNotBlockScaling() {
        var style = LayerStyle()
        style.shadow = ShadowStyle(radius: 12, opacity: 0)
        let layer = Layer(name: "GhostShadow", content: .image(ref), frame: frame, style: style)
        // A zero-opacity shadow renders nothing, so scaling stays faithful.
        #expect(layer.resizeScalesUniformly)
    }

    // MARK: Content whose detail is sized in fixed points — must re-render

    @Test func annotationRectangleBlocksSpriteScaling() {
        // The exact reported subject: a rectangle annotation with a stroke.
        let layer = Layer(name: "Rect",
                          content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 4)),
                          frame: frame)
        #expect(!layer.resizeScalesUniformly)
    }

    @Test func textBlocksSpriteScaling() {
        let layer = Layer(name: "Text", content: .text(TextContent(string: "hi")), frame: frame)
        #expect(!layer.resizeScalesUniformly)
    }
}
