import DoodleCore
import PencilKit

/// The one place PencilKit meets the pure pipeline.
enum StrokeExtractor {
    /// Samples the rendered spline rather than its control points: a fast flick yields few control
    /// points, and joining them with straight lines would not match the curve on screen.
    static func strokes(from drawing: PKDrawing) -> [Stroke] {
        drawing.strokes.map { stroke in
            stroke.path.interpolatedPoints(by: .distance(1)).map { sample in
                let location = sample.location.applying(stroke.transform)
                return StrokePoint(x: Double(location.x), y: Double(location.y))
            }
        }
    }
}
