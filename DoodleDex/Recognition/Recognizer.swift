import CoreML
import DoodleCore
import Foundation

struct Guess: Equatable, Sendable {
    let label: String
    let probability: Double
}

struct Recognition: Equatable, Sendable {
    /// Best first, at most five. Probabilities are the model's raw softmax.
    let guesses: [Guess]
    let simplifiedStrokes: [Stroke]
    let preprocessMilliseconds: Double
    let inferenceMilliseconds: Double
}

enum RecognizerError: Error {
    case modelMissing
    case outputMissing
}

/// Runs the pipeline and the model off the main actor. Core ML is called directly rather than
/// through Vision: Vision would rescale and colour-convert an image the pipeline has already
/// produced at exactly the model's input size, adding a step that the parity tests would not cover.
actor Recognizer {
    private let model: MLModel
    private let probabilitiesName: String

    init(contentsOf url: URL, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: configuration)
        probabilitiesName = model.modelDescription.predictedProbabilitiesName ?? "classLabel_probs"
    }

    static func bundled(in bundle: Bundle = .main, computeUnits: MLComputeUnits = .all) throws -> Recognizer {
        guard let url = bundle.url(forResource: "DoodleClassifier", withExtension: "mlmodelc") else {
            throw RecognizerError.modelMissing
        }
        return try Recognizer(contentsOf: url, computeUnits: computeUnits)
    }

    func recognize(strokes: [Stroke]) throws -> Recognition {
        let clock = ContinuousClock()
        var simplified: [Stroke] = []
        var pixels: [UInt8] = []
        let preprocessing = clock.measure {
            simplified = Preprocessor.simplify(strokes)
            pixels = Preprocessor.rasterize(simplified)
        }
        var guesses: [Guess] = []
        let inference = try clock.measure {
            guesses = try classify(pixels: pixels)
        }
        return Recognition(
            guesses: guesses,
            simplifiedStrokes: simplified,
            preprocessMilliseconds: preprocessing.milliseconds,
            inferenceMilliseconds: inference.milliseconds
        )
    }

    func classify(pixels: [UInt8]) throws -> [Guess] {
        let array = try MLMultiArray(shape: [1, 1, 28, 28], dataType: .float32)
        array.withUnsafeMutableBytes { bytes, _ in
            let floats = bytes.bindMemory(to: Float32.self)
            for (index, pixel) in pixels.enumerated() {
                floats[index] = Float32(pixel)
            }
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["pixels": MLFeatureValue(multiArray: array)])
        let output = try model.prediction(from: input)
        guard let scores = output.featureValue(for: probabilitiesName)?.dictionaryValue else {
            throw RecognizerError.outputMissing
        }
        return
            scores
            .compactMap { key, value in (key as? String).map { Guess(label: $0, probability: value.doubleValue) } }
            .sorted { ($0.probability, $1.label) > ($1.probability, $0.label) }
            .prefix(5)
            .map { $0 }
    }
}

extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
