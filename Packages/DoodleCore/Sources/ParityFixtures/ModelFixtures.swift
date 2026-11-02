import Foundation

/// Core ML's output on each pipeline fixture, recorded by `python -m doodledex_ml.convert`.
public struct ModelFixtures: Decodable, Sendable {
    public struct Guess: Decodable, Sendable {
        public let label: String
        public let probability: Double
    }

    public struct Case: Decodable, Sendable {
        public let id: String
        public let top: [Guess]
        public let strokes: Int
        public let calibrated: Double
    }

    public let cases: [Case]

    public static func load() throws -> ModelFixtures {
        guard let url = Bundle.module.url(forResource: "model_fixtures", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(ModelFixtures.self, from: Data(contentsOf: url))
    }
}
