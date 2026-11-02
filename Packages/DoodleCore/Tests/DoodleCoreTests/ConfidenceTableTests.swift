import DoodleCore
import XCTest

final class ConfidenceTableTests: XCTestCase {
    private let table: ConfidenceTable = {
        let json = """
            {"stroke_bucket_starts": [1, 2, 4],
             "confidence_bins": 2,
             "probabilities": [[0.1, 0.2], [0.3, 0.4], [0.5, 0.6]],
             "sticker_threshold": 0.5,
             "typical_accuracy_by_strokes": [0.2, 0.4, 0.8]}
            """
        return try! JSONDecoder().decode(ConfidenceTable.self, from: Data(json.utf8))
    }()

    func testBucketsFollowStrokeCount() {
        XCTAssertEqual(table.probability(rawConfidence: 0.1, strokes: 1), 0.1)
        XCTAssertEqual(table.probability(rawConfidence: 0.1, strokes: 3), 0.3)
        XCTAssertEqual(table.probability(rawConfidence: 0.1, strokes: 4), 0.5)
        XCTAssertEqual(table.probability(rawConfidence: 0.1, strokes: 90), 0.5)
    }

    func testTopScoreStaysInsideTheLastBin() {
        XCTAssertEqual(table.probability(rawConfidence: 1.0, strokes: 1), 0.2)
    }

    func testTypicalAccuracyClampsPastTheMeasuredRange() {
        XCTAssertEqual(table.typicalAccuracy(strokes: 2), 0.4)
        XCTAssertEqual(table.typicalAccuracy(strokes: 40), 0.8)
    }

    func testVerdictFollowsProbability() {
        XCTAssertEqual(Verdict(label: nil, probability: 0, stickerThreshold: 0.8), .blank)
        XCTAssertEqual(Verdict(label: "cat", probability: 0.2, stickerThreshold: 0.8), .scribbling)
        XCTAssertEqual(Verdict(label: "cat", probability: 0.5, stickerThreshold: 0.8), .leaning("cat"))
        XCTAssertEqual(Verdict(label: "cat", probability: 0.8, stickerThreshold: 0.8), .sure("cat"))
        XCTAssertTrue(Verdict(label: "cat", probability: 0.9, stickerThreshold: 0.8).canCollect)
        XCTAssertFalse(Verdict(label: "cat", probability: 0.5, stickerThreshold: 0.8).canCollect)
    }

    func testArticlesReadNaturally() {
        XCTAssertEqual(Naming.withArticle("house"), "a house")
        XCTAssertEqual(Naming.withArticle("owl"), "an owl")
        XCTAssertEqual(Naming.withArticle("hourglass"), "an hourglass")
        XCTAssertEqual(Naming.withArticle("scissors"), "scissors")
    }
}
