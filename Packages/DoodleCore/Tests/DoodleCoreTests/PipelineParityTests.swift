import DoodleCore
import ParityFixtures
import XCTest

/// Replays vectors produced by `ml/doodledex_ml/fixtures.py`. These run on macOS through
/// `swift test` and again inside the iOS simulator through the app's test bundle.
final class PipelineParityTests: XCTestCase {
    private static let fixtures = Result { try PipelineFixtures.load() }

    private func strokes(_ raw: [[(x: Double, y: Double)]]) -> [Stroke] {
        raw.map { $0.map { StrokePoint(x: $0.x, y: $0.y) } }
    }

    func testFixturesCoverEveryKindOfInput() throws {
        let kinds = Set(try Self.fixtures.get().cases.map(\.kind))
        XCTAssertEqual(kinds, ["edge", "dataset", "partial", "canvas"])
    }

    func testSimplifiedStrokesMatchPythonExactly() throws {
        for fixture in try Self.fixtures.get().cases {
            let actual = Preprocessor.simplify(strokes(fixture.strokes))
            XCTAssertEqual(actual, strokes(fixture.simplifiedStrokes), fixture.id)
        }
    }

    func testPixelsMatchPythonByteForByte() throws {
        for fixture in try Self.fixtures.get().cases {
            let actual = Preprocessor.preprocess(strokes(fixture.strokes))
            XCTAssertEqual(actual, fixture.expectedPixels, fixture.id)
        }
    }

    func testRasterizerAloneMatchesPythonOnPythonSimplifiedStrokes() throws {
        for fixture in try Self.fixtures.get().cases {
            let actual = Preprocessor.rasterize(strokes(fixture.simplifiedStrokes))
            XCTAssertEqual(actual, fixture.expectedPixels, fixture.id)
        }
    }
}
