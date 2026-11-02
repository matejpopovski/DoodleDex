import DoodleCore
import ParityFixtures
import XCTest

@testable import DoodleDex

/// End-to-end parity: strokes through the Swift pipeline, then the compiled model in this runtime,
/// against what coremltools produced from the Python pipeline on macOS.
final class ModelParityTests: XCTestCase {
    private func strokes(_ fixture: PipelineFixtures.Case) -> [Stroke] {
        fixture.strokes.map { $0.map { StrokePoint(x: $0.x, y: $0.y) } }
    }

    func testPipelineBytesMatchPythonInsideTheSimulatorToo() throws {
        for fixture in try PipelineFixtures.load().cases {
            XCTAssertEqual(Preprocessor.preprocess(strokes(fixture)), fixture.expectedPixels, fixture.id)
        }
    }

    func testStrokesToGuessesMatchPythonForEveryFixture() async throws {
        let pipeline = try PipelineFixtures.load().cases
        let expected = Dictionary(uniqueKeysWithValues: try ModelFixtures.load().cases.map { ($0.id, $0) })
        let recognizer = try Recognizer.bundled(computeUnits: .cpuOnly)
        XCTAssertEqual(expected.count, pipeline.count)

        for fixture in pipeline {
            let wanted = try XCTUnwrap(expected[fixture.id])
            let guesses = try await recognizer.classify(pixels: Preprocessor.preprocess(strokes(fixture)))
            XCTAssertEqual(guesses.first?.label, wanted.top.first?.label, fixture.id)
            let actual = Dictionary(uniqueKeysWithValues: guesses.map { ($0.label, $0.probability) })
            for guess in wanted.top where guess.probability > 0.001 {
                let probability = try XCTUnwrap(actual[guess.label], "\(fixture.id): \(guess.label)")
                XCTAssertEqual(probability, guess.probability, accuracy: 0.001, fixture.id)
            }
        }
    }

    func testConfidenceLookupMatchesPython() throws {
        let table = try BundledResources.load().confidenceTable
        for fixture in try ModelFixtures.load().cases {
            let raw = try XCTUnwrap(fixture.top.first?.probability)
            XCTAssertEqual(
                table.probability(rawConfidence: raw, strokes: fixture.strokes),
                fixture.calibrated,
                fixture.id
            )
        }
    }

    func testBundledCatalogCoversExactlyTheModelLabels() throws {
        let catalog = try BundledResources.load().catalog
        let labels = Set(try ModelFixtures.load().cases.flatMap { $0.top.map(\.label) })
        let categories = Set(catalog.chapters.flatMap(\.categories))
        XCTAssertEqual(catalog.total, 100)
        XCTAssertEqual(categories.count, 100)
        XCTAssertTrue(labels.isSubset(of: categories))
    }
}
