import DoodleCore
import PencilKit
import XCTest

@testable import DoodleDex

@MainActor
final class SketchSessionTests: XCTestCase {
    private func session() throws -> SketchSession {
        SketchSession(
            recognizer: try Recognizer.bundled(computeUnits: .cpuOnly),
            table: try BundledResources.load().confidenceTable
        )
    }

    private func line(_ from: CGPoint, _ to: CGPoint) -> PKStroke {
        let points = [from, to].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.05,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }

    func testEachStrokeAddsOneTimelinePoint() async throws {
        let session = try session()
        session.drawing.strokes.append(line(.init(x: 10, y: 10), .init(x: 200, y: 10)))
        await session.drawingDidChange()
        session.drawing.strokes.append(line(.init(x: 200, y: 10), .init(x: 200, y: 200)))
        await session.drawingDidChange()

        XCTAssertEqual(session.timeline.map(\.strokes), [1, 2])
        XCTAssertFalse(session.guesses.isEmpty)
        XCTAssertNotEqual(session.verdict, .blank)
    }

    func testUndoRewindsTheTimeline() async throws {
        let session = try session()
        session.drawing.strokes.append(line(.init(x: 10, y: 10), .init(x: 200, y: 10)))
        await session.drawingDidChange()
        session.drawing.strokes.append(line(.init(x: 200, y: 10), .init(x: 200, y: 200)))
        await session.drawingDidChange()

        session.undo()
        await session.drawingDidChange()

        XCTAssertEqual(session.timeline.map(\.strokes), [1])
    }

    func testClearingReturnsToBlank() async throws {
        let session = try session()
        session.drawing.strokes.append(line(.init(x: 10, y: 10), .init(x: 200, y: 10)))
        await session.drawingDidChange()

        session.clear()
        await session.drawingDidChange()

        XCTAssertEqual(session.verdict, .blank)
        XCTAssertTrue(session.timeline.isEmpty)
        XCTAssertTrue(session.guesses.isEmpty)
    }

    func testAppBundleCarriesTheAttribution() throws {
        let card = try BundledResources.load().modelCard
        XCTAssertTrue(card.attribution.contains("Quick, Draw!"))
        XCTAssertTrue(card.attribution.contains("CC BY 4.0"))
    }
}
