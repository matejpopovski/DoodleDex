import Foundation

/// Vectors written by `python -m doodledex_ml.fixtures`, decoded once for both test bundles.
///
/// Coordinates are base64 little-endian float64 rather than JSON numbers, so the test cannot pass
/// or fail because of how a JSON parser rounds decimals.
public struct PipelineFixtures: Decodable, Sendable {
    public struct Case: Decodable, Sendable {
        public let id: String
        public let kind: String
        public let pointCounts: [Int]
        public let coordinates: String
        public let simplifiedPointCounts: [Int]
        public let simplifiedCoordinates: String
        public let pixels: String

        enum CodingKeys: String, CodingKey {
            case id, kind, coordinates, pixels
            case pointCounts = "point_counts"
            case simplifiedPointCounts = "simplified_point_counts"
            case simplifiedCoordinates = "simplified_coordinates"
        }

        /// Strokes as (x, y) pairs of doubles, one array per stroke.
        public var strokes: [[(x: Double, y: Double)]] {
            Self.unpack(coordinates, pointCounts)
        }

        public var simplifiedStrokes: [[(x: Double, y: Double)]] {
            Self.unpack(simplifiedCoordinates, simplifiedPointCounts)
        }

        public var expectedPixels: [UInt8] {
            Array(Data(base64Encoded: pixels) ?? Data())
        }

        private static func unpack(_ base64: String, _ counts: [Int]) -> [[(x: Double, y: Double)]] {
            let data = Data(base64Encoded: base64) ?? Data()
            let values = stride(from: 0, to: data.count, by: 8).map { offset -> Double in
                var bits: UInt64 = 0
                for byte in 0..<8 {
                    bits |= UInt64(data[data.startIndex + offset + byte]) << UInt64(byte * 8)
                }
                return Double(bitPattern: bits)
            }
            var cursor = 0
            return counts.map { count in
                defer { cursor += count * 2 }
                return (0..<count).map { (values[cursor + $0 * 2], values[cursor + $0 * 2 + 1]) }
            }
        }
    }

    public let cases: [Case]

    public static func load() throws -> PipelineFixtures {
        guard let url = Bundle.module.url(forResource: "pipeline_fixtures", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(PipelineFixtures.self, from: Data(contentsOf: url))
    }
}
