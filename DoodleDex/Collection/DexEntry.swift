import Foundation
import SwiftData

/// One class the player has discovered.
@Model
final class DexEntry {
    @Attribute(.unique) var category: String
    var firstCollectedAt: Date
    var bestProbability: Double
    var fewestStrokes: Int

    @Relationship(deleteRule: .cascade, inverse: \Sticker.entry)
    var stickers: [Sticker] = []

    init(category: String, firstCollectedAt: Date, bestProbability: Double, fewestStrokes: Int) {
        self.category = category
        self.firstCollectedAt = firstCollectedAt
        self.bestProbability = bestProbability
        self.fewestStrokes = fewestStrokes
    }

    /// The sticker on the book page is the player's most recent drawing of this class.
    var latestSticker: Sticker? {
        stickers.max { $0.collectedAt < $1.collectedAt }
    }
}

/// One saved drawing. Art is kept as simplified strokes rather than an image: a few hundred bytes
/// each, and the book can draw them at any size in the chapter's colour.
@Model
final class Sticker {
    var collectedAt: Date
    var probability: Double
    var strokeCount: Int
    var strokesData: Data
    var entry: DexEntry?

    init(collectedAt: Date, probability: Double, strokeCount: Int, strokesData: Data) {
        self.collectedAt = collectedAt
        self.probability = probability
        self.strokeCount = strokeCount
        self.strokesData = strokesData
    }
}
