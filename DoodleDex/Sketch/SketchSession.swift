import DoodleCore
import Foundation
import Observation
import PencilKit

struct TimelinePoint: Identifiable, Equatable, Sendable {
    let strokes: Int
    let label: String
    let probability: Double
    let typicalAccuracy: Double
    var id: Int { strokes }
}

/// The state of the drawing in progress: one recognition per stroke, and its history.
@MainActor
@Observable
final class SketchSession {
    var drawing = PKDrawing()
    private(set) var guesses: [Guess] = []
    private(set) var timeline: [TimelinePoint] = []
    private(set) var verdict = Verdict.blank
    private(set) var latestLatencyMilliseconds: Double?
    private(set) var simplifiedStrokes: [Stroke] = []
    private(set) var failureMessage: String?

    private let recognizer: Recognizer
    private let table: ConfidenceTable
    private var generation = 0

    init(recognizer: Recognizer, table: ConfidenceTable) {
        self.recognizer = recognizer
        self.table = table
    }

    var strokeCount: Int { drawing.strokes.count }
    var probability: Double { timeline.last?.probability ?? 0 }

    func drawingDidChange() async {
        generation += 1
        let ticket = generation
        let strokes = StrokeExtractor.strokes(from: drawing)
        guard !strokes.isEmpty else {
            reset()
            return
        }
        do {
            let recognition = try await recognizer.recognize(strokes: strokes)
            // Strokes can arrive faster than inference finishes, and only the newest result counts.
            guard ticket == generation else { return }
            apply(recognition, strokes: strokes.count)
        } catch {
            guard ticket == generation else { return }
            failureMessage = "Recognition failed: \(error.localizedDescription)"
        }
    }

    func undo() {
        guard !drawing.strokes.isEmpty else { return }
        drawing.strokes.removeLast()
    }

    func clear() {
        drawing = PKDrawing()
    }

    private func apply(_ recognition: Recognition, strokes: Int) {
        guard let top = recognition.guesses.first else { return }
        let probability = table.probability(rawConfidence: top.probability, strokes: strokes)
        guesses = recognition.guesses
        simplifiedStrokes = recognition.simplifiedStrokes
        latestLatencyMilliseconds = recognition.preprocessMilliseconds + recognition.inferenceMilliseconds
        failureMessage = nil
        timeline = timeline.filter { $0.strokes < strokes }
        timeline.append(
            TimelinePoint(
                strokes: strokes,
                label: top.label,
                probability: probability,
                typicalAccuracy: table.typicalAccuracy(strokes: strokes)
            )
        )
        verdict = Verdict(label: top.label, probability: probability, stickerThreshold: table.stickerThreshold)
    }

    private func reset() {
        guesses = []
        timeline = []
        simplifiedStrokes = []
        verdict = .blank
        failureMessage = nil
    }
}
