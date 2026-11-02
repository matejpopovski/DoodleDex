import Foundation

/// The empirical P(top guess is right | strokes so far, raw score), fitted by
/// `ml/doodledex_ml/calibration.py` on drawings the network never trained on.
public struct ConfidenceTable: Decodable, Equatable, Sendable {
    public let strokeBucketStarts: [Int]
    public let confidenceBins: Int
    public let probabilities: [[Double]]
    public let stickerThreshold: Double
    public let typicalAccuracyByStrokes: [Double]

    enum CodingKeys: String, CodingKey {
        case strokeBucketStarts = "stroke_bucket_starts"
        case confidenceBins = "confidence_bins"
        case probabilities
        case stickerThreshold = "sticker_threshold"
        case typicalAccuracyByStrokes = "typical_accuracy_by_strokes"
    }

    /// The probability to display for a raw top-1 score after `strokes` strokes.
    public func probability(rawConfidence: Double, strokes: Int) -> Double {
        let bucket = strokeBucketStarts.lastIndex { $0 <= strokes } ?? 0
        let bin = Swift.min(Swift.max(Int(rawConfidence * Double(confidenceBins)), 0), confidenceBins - 1)
        return probabilities[bucket][bin]
    }

    /// Top-1 accuracy measured on held-out sketches stopped after this many strokes.
    public func typicalAccuracy(strokes: Int) -> Double {
        let index = Swift.min(Swift.max(strokes, 1), typicalAccuracyByStrokes.count) - 1
        return typicalAccuracyByStrokes[index]
    }
}
