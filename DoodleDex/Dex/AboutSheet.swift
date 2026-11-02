import SwiftUI

/// The dataset's licence requires attribution, and the figures here are the held-out test results.
struct AboutSheet: View {
    let card: ModelCard
    let latency: Double?

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: 12) {
                Text("About this model")
                    .font(.system(.title2, design: .rounded, weight: .black))
                Text("Runs entirely on this phone. Nothing you draw leaves it.")
                Text(
                    """
                    \(card.classes) classes, \(card.modelMegabytes.formatted(.number.precision(.fractionLength(1)))) MB. \
                    On \(card.testImages.formatted()) held-out drawings it scored \
                    \(percent(card.testTop1)) top-1 and \(percent(card.testTop5)) top-5.
                    """
                )
                if let latency {
                    Text(
                        "Last guess: \(latency.formatted(.number.precision(.fractionLength(1)))) ms \(RuntimeLabel.environment)."
                    )
                    .accessibilityIdentifier("about.latency")
                }
                Text(card.attribution + ".")
                    .accessibilityIdentifier("about.attribution")
                if let url = URL(string: card.datasetUrl) {
                    Link("Quick, Draw! dataset", destination: url)
                        .foregroundStyle(Palette.tomato)
                        .fontWeight(.semibold)
                }
                Spacer()
            }
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Palette.ink)
            .padding(24)
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }
}
