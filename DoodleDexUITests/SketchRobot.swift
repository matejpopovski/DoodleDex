import XCTest

/// Draws with real synthesized touches. Public XCUITest can only drag in a straight line, so every
/// shape here is built from straight strokes, each of which reaches the app as one PKStroke.
@MainActor
struct SketchRobot {
    let app: XCUIApplication

    var canvas: XCUIElement {
        app.descendants(matching: .any)["sketch.canvas"]
    }

    func stroke(_ start: CGPoint, _ end: CGPoint) {
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: start.x, dy: start.y))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: end.x, dy: end.y))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    func draw(_ strokes: [(CGPoint, CGPoint)]) {
        for (start, end) in strokes {
            stroke(start, end)
        }
    }

    func waitForFootnote(strokes: Int) -> Bool {
        let noun = strokes == 1 ? "1 stroke" : "\(strokes) strokes"
        let predicate = NSPredicate(format: "label CONTAINS %@", "Sketches at \(noun)")
        return app.staticTexts.containing(predicate).firstMatch.waitForExistence(timeout: 10)
    }
}

enum Shapes {
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    private static func chain(_ points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        Array(zip(points, points.dropFirst()))
    }

    static let house: [(CGPoint, CGPoint)] =
        chain([p(0.2, 0.45), p(0.2, 0.9), p(0.8, 0.9), p(0.8, 0.45), p(0.2, 0.45)])
        + chain([p(0.2, 0.45), p(0.5, 0.12), p(0.8, 0.45)])
        + chain([p(0.43, 0.9), p(0.43, 0.65), p(0.57, 0.65), p(0.57, 0.9)])

    static let star: [(CGPoint, CGPoint)] = chain([
        p(0.2, 0.9), p(0.5, 0.08), p(0.8, 0.9), p(0.08, 0.38), p(0.92, 0.38), p(0.2, 0.9),
    ])

    static let ladder: [(CGPoint, CGPoint)] =
        [(p(0.32, 0.08), p(0.32, 0.92)), (p(0.68, 0.08), p(0.68, 0.92))]
        + [0.2, 0.34, 0.48, 0.62, 0.76].map { (p(0.32, $0), p(0.68, $0)) }

    static let envelope: [(CGPoint, CGPoint)] =
        chain([p(0.1, 0.25), p(0.9, 0.25), p(0.9, 0.75), p(0.1, 0.75), p(0.1, 0.25)])
        + chain([p(0.1, 0.25), p(0.5, 0.55), p(0.9, 0.25)])

    static let tent: [(CGPoint, CGPoint)] =
        chain([p(0.1, 0.85), p(0.5, 0.15), p(0.9, 0.85), p(0.1, 0.85)])
        + chain([p(0.5, 0.15), p(0.38, 0.85)])
        + chain([p(0.5, 0.15), p(0.62, 0.85)])

    static let fish: [(CGPoint, CGPoint)] = chain([
        p(0.1, 0.5), p(0.3, 0.3), p(0.55, 0.3), p(0.75, 0.5), p(0.92, 0.3), p(0.92, 0.7),
        p(0.75, 0.5), p(0.55, 0.7), p(0.3, 0.7), p(0.1, 0.5),
    ])
}
