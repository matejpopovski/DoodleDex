import DoodleCore
import ParityFixtures
import PencilKit
import XCTest

@testable import DoodleDex

/// The last untested link: fixture strokes pushed through real PKDrawing objects, then back out
/// through the same extractor the app uses.
final class StrokeExtractorTests: XCTestCase {
    private func stroke(_ points: [CGPoint], transform: CGAffineTransform = .identity) -> PKStroke {
        let controlPoints = points.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.01,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path, transform: transform, mask: nil)
    }

    func testStrokeTransformIsApplied() throws {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let moved = stroke(line, transform: CGAffineTransform(translationX: 10, y: 20))
        let extracted = StrokeExtractor.strokes(from: PKDrawing(strokes: [moved]))
        let first = try XCTUnwrap(extracted.first?.first)
        XCTAssertEqual(first.x, 10, accuracy: 0.001)
        XCTAssertEqual(first.y, 20, accuracy: 0.001)
    }

    func testStrokesKeepTheirDrawingOrder() {
        let first = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0)])
        let second = stroke([CGPoint(x: 0, y: 40), CGPoint(x: 50, y: 40)])
        let extracted = StrokeExtractor.strokes(from: PKDrawing(strokes: [first, second]))
        XCTAssertEqual(extracted.count, 2)
        XCTAssertEqual(extracted[0].first?.y ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(extracted[1].first?.y ?? -1, 40, accuracy: 0.001)
    }

    func testTapStillYieldsAPoint() {
        let tap = stroke([CGPoint(x: 42, y: 42)])
        let extracted = StrokeExtractor.strokes(from: PKDrawing(strokes: [tap]))
        XCTAssertEqual(extracted.first?.isEmpty, false)
    }

    /// PencilKit treats points as spline control points, and the dataset's web touch samples are far
    /// sparser than a phone's, so feeding them in directly rounds off corners no phone would round.
    /// The strokes are densified first to match real input. What has to survive the trip through
    /// PKDrawing is then the picture and, above all, the model's answer.
    func testHumanStrokesThroughPencilKitKeepTheirPixelsAndTheirGuess() async throws {
        let dataset = try PipelineFixtures.load().cases.filter { $0.kind == "dataset" }
        let expected = Dictionary(uniqueKeysWithValues: try ModelFixtures.load().cases.map { ($0.id, $0) })
        let recognizer = try Recognizer.bundled(computeUnits: .cpuOnly)
        XCTAssertEqual(dataset.count, 100)

        var errors: [Double] = []
        var agreements = 0
        for fixture in dataset {
            let strokes = fixture.strokes.map { points in
                let dense = Preprocessor.resample(points.map { StrokePoint(x: $0.x, y: $0.y) }, spacing: 2)
                return stroke(dense.map { CGPoint(x: $0.x, y: $0.y) })
            }
            let extracted = StrokeExtractor.strokes(from: PKDrawing(strokes: strokes))
            let pixels = Preprocessor.preprocess(extracted)
            let total = zip(pixels, fixture.expectedPixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            errors.append(Double(total) / 784)
            let guess = try await recognizer.classify(pixels: pixels).first?.label
            if guess == expected[fixture.id]?.top.first?.label {
                agreements += 1
            }
        }
        let sorted = errors.sorted()
        print("PencilKit round trip: median \(sorted[50]), p90 \(sorted[90]), \(agreements)/100 same guess")
        XCTAssertLessThan(sorted[50], 3, "median per-pixel error, 0-255 scale")
        XCTAssertLessThan(sorted[90], 6, "p90 per-pixel error, 0-255 scale")
        XCTAssertGreaterThanOrEqual(agreements, 95)
    }
}
