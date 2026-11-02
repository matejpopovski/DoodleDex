import Charts
import DoodleCore
import SwiftUI

/// Everything shown here comes from the calibrated probability, not the raw softmax score.
struct GuessPanel: View {
    let session: SketchSession
    let table: ConfidenceTable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("guess.headline")
                Spacer()
                Text(session.timeline.isEmpty ? "" : "\(percent(session.probability)) sure")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .monospacedDigit()
                    .accessibilityIdentifier("guess.probability")
            }
            ConfidenceBar(probability: session.probability, threshold: table.stickerThreshold)
            detail
                // The panel keeps one height, because the canvas above it takes the remaining space
                // and must not change size between strokes.
                .frame(height: 118, alignment: .top)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var detail: some View {
        if let last = session.timeline.last {
            VStack(alignment: .leading, spacing: 4) {
                ChartLegend()
                ConfidenceChart(points: session.timeline)
                    .frame(height: 56)
                Text(footnote(for: last))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                    .accessibilityIdentifier("guess.footnote")
            }
        } else {
            Text("Confidence appears here, one stroke at a time.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headline: String {
        switch session.verdict {
        case .blank: "Waiting for a stroke"
        case .scribbling: "Hmm, keep going"
        case .leaning(let label): "Could be \(Naming.withArticle(label))"
        case .sure(let label): "That's \(Naming.withArticle(label))!"
        }
    }

    private func footnote(for point: TimelinePoint) -> String {
        let strokes = point.strokes == 1 ? "1 stroke" : "\(point.strokes) strokes"
        var note = "Sketches at \(strokes) are right \(percent(point.typicalAccuracy)) of the time."
        if let latency = session.latestLatencyMilliseconds {
            note += " \(latency.formatted(.number.precision(.fractionLength(1)))) ms \(RuntimeLabel.environment)."
        }
        return note
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

struct ConfidenceBar: View {
    let probability: Double
    let threshold: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.1))
                Capsule()
                    .fill(probability >= threshold ? Palette.leaf : Palette.mustard)
                    .frame(width: max(proxy.size.width * probability, probability > 0 ? 10 : 0))
                    .animation(.spring(duration: 0.35), value: probability)
                Rectangle()
                    .fill(Palette.ink.opacity(0.55))
                    .frame(width: 2)
                    .offset(x: proxy.size.width * threshold)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel("Confidence")
        .accessibilityValue(probability.formatted(.percent.precision(.fractionLength(0))))
    }
}

private struct ChartLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text("this drawing")
            } icon: {
                Capsule().fill(Palette.tomato).frame(width: 12, height: 2.5)
            }
            Label {
                Text("typical sketch")
            } icon: {
                Capsule()
                    .stroke(Palette.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 12, height: 0.5)
            }
        }
        .labelStyle(CompactLabelStyle())
        .font(.system(size: 10, design: .rounded))
        .foregroundStyle(Palette.ink.opacity(0.6))
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

private struct ConfidenceChart: View {
    let points: [TimelinePoint]

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Strokes", point.strokes),
                    y: .value("Typical", point.typicalAccuracy),
                    series: .value("Series", "typical")
                )
                .foregroundStyle(Palette.ink.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Strokes", point.strokes),
                    y: .value("Confidence", point.probability),
                    series: .value("Series", "this drawing")
                )
                .foregroundStyle(Palette.tomato)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Strokes", point.strokes), y: .value("Confidence", point.probability))
                    .foregroundStyle(Palette.tomato)
                    .symbolSize(28)
            }
        }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 1...max(points.count + 1, 4))
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 1]) { value in
                AxisGridLine().foregroundStyle(Palette.ink.opacity(0.08))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 9, design: .rounded))
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .accessibilityIdentifier("guess.chart")
    }
}

enum RuntimeLabel {
    /// Latency measured here must not be read as phone latency.
    static var environment: String {
        #if targetEnvironment(simulator)
            "in the simulator"
        #else
            "on this device"
        #endif
    }
}
