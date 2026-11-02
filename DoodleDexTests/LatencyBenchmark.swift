import DoodleCore
import ParityFixtures
import UIKit
import XCTest

@testable import DoodleDex

/// Writes `simulator_latency.json` when `scripts/measure-latency.sh` provides a directory.
/// Skipped otherwise, since a timing has no meaning inside an ordinary test run.
final class LatencyBenchmark: XCTestCase {
    private struct Report: Encodable {
        let environment: String
        let host: String
        let computeUnits: String
        let simulatedDevice: String
        let runtime: String
        let drawings: Int
        let iterations: Int
        let preprocessMillisecondsP50: Double
        let preprocessMillisecondsP95: Double
        let inferenceMillisecondsP50: Double
        let inferenceMillisecondsP95: Double
    }

    private func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        (sorted[Int(Double(sorted.count - 1) * fraction)] * 1000).rounded() / 1000
    }

    func testMeasureLatency() async throws {
        let directory = ProcessInfo.processInfo.environment["DOODLEDEX_RESULTS_DIR"]
        try XCTSkipIf(directory == nil, "only runs under scripts/measure-latency.sh")

        let drawings = try PipelineFixtures.load().cases
            .filter { $0.kind == "dataset" }
            .map { $0.strokes.map { $0.map { StrokePoint(x: $0.x, y: $0.y) } } }
        let recognizer = try Recognizer.bundled(computeUnits: .all)
        _ = try await recognizer.recognize(strokes: drawings[0])

        var preprocess: [Double] = []
        var inference: [Double] = []
        for _ in 0..<5 {
            for strokes in drawings {
                let result = try await recognizer.recognize(strokes: strokes)
                preprocess.append(result.preprocessMilliseconds)
                inference.append(result.inferenceMilliseconds)
            }
        }
        preprocess.sort()
        inference.sort()

        let environment = ProcessInfo.processInfo.environment
        let runtime = await UIDevice.current.systemVersion
        let report = Report(
            environment: "iOS Simulator, running on the host Mac, not a phone",
            host: environment["DOODLEDEX_HOST"] ?? "unknown",
            computeUnits: "all (the simulator has no Neural Engine)",
            simulatedDevice: environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown",
            runtime: runtime,
            drawings: drawings.count,
            iterations: preprocess.count,
            preprocessMillisecondsP50: percentile(preprocess, 0.5),
            preprocessMillisecondsP95: percentile(preprocess, 0.95),
            inferenceMillisecondsP50: percentile(inference, 0.5),
            inferenceMillisecondsP95: percentile(inference, 0.95)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = URL(filePath: try XCTUnwrap(directory)).appending(path: "simulator_latency.json")
        try encoder.encode(report).write(to: url)
    }
}
