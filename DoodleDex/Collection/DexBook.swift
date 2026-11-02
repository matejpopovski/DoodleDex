import DoodleCore
import Foundation
import SwiftData

/// All writes to the collection, so that the rules for updating an entry live in one place.
@MainActor
struct DexBook {
    enum Outcome: Equatable {
        case discovered
        case repeated(copies: Int)
    }

    let context: ModelContext

    @discardableResult
    func collect(
        category: String,
        probability: Double,
        strokes: [Stroke],
        at date: Date = .now
    ) throws -> Outcome {
        let sticker = Sticker(
            collectedAt: date,
            probability: probability,
            strokeCount: strokes.count,
            strokesData: try JSONEncoder().encode(strokes)
        )
        let matches = FetchDescriptor<DexEntry>(predicate: #Predicate { $0.category == category })
        let outcome: Outcome
        if let entry = try context.fetch(matches).first {
            entry.bestProbability = max(entry.bestProbability, probability)
            entry.fewestStrokes = min(entry.fewestStrokes, strokes.count)
            entry.stickers.append(sticker)
            outcome = .repeated(copies: entry.stickers.count)
        } else {
            let entry = DexEntry(
                category: category,
                firstCollectedAt: date,
                bestProbability: probability,
                fewestStrokes: strokes.count
            )
            context.insert(entry)
            entry.stickers.append(sticker)
            outcome = .discovered
        }
        // Saved at once rather than on autosave: a collected sticker must survive the app being
        // killed straight after.
        try context.save()
        return outcome
    }
}

extension Sticker {
    var strokes: [Stroke] {
        (try? JSONDecoder().decode([Stroke].self, from: strokesData)) ?? []
    }
}
