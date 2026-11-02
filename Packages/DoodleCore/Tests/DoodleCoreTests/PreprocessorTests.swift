import DoodleCore
import XCTest

final class PreprocessorTests: XCTestCase {
    private func point(_ x: Double, _ y: Double) -> StrokePoint {
        StrokePoint(x: x, y: y)
    }

    func testBlankCanvasIsAllBackground() {
        XCTAssertEqual(Preprocessor.preprocess([]), [UInt8](repeating: 0, count: 784))
        XCTAssertEqual(Preprocessor.preprocess([[]]), [UInt8](repeating: 0, count: 784))
    }

    func testTapIsInkedAndCentred() {
        let pixels = Preprocessor.preprocess([[point(40, 90)]])
        XCTAssertGreaterThan(pixels.max() ?? 0, 0)
        var weightedRow = 0.0
        var total = 0.0
        for (index, value) in pixels.enumerated() {
            weightedRow += Double(index / 28) * Double(value)
            total += Double(value)
        }
        XCTAssertEqual(weightedRow / total, 13.5, accuracy: 0.01)
    }

    func testOutputIsRowMajorWithYDown() {
        let topLine = [[point(0, 0), point(100, 0)], [point(0, 40), point(0, 41)]]
        let pixels = Preprocessor.preprocess(topLine)
        let upperHalf = pixels[0..<(28 * 14)].reduce(0) { $0 + Int($1) }
        let lowerHalf = pixels[(28 * 14)...].reduce(0) { $0 + Int($1) }
        XCTAssertGreaterThan(upperHalf, lowerHalf)
    }

    func testRdpDropsCollinearPoints() {
        let line = (0...10).map { point(Double($0), 0) }
        XCTAssertEqual(Preprocessor.rdp(line, epsilon: 2), [point(0, 0), point(10, 0)])
    }

    func testResampleCarriesDistanceAcrossCorners() {
        let bent = [point(0, 0), point(1.5, 0), point(1.5, 1.5)]
        XCTAssertEqual(
            Preprocessor.resample(bent, spacing: 1),
            [point(0, 0), point(1, 0), point(1.5, 0.5), point(1.5, 1.5)]
        )
    }
}
