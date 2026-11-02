import DoodleCore
import SwiftData
import SwiftUI

struct SketchScreen: View {
    @Bindable var session: SketchSession
    let table: ConfidenceTable

    @Environment(\.modelContext) private var context
    @State private var celebration: Celebration?
    @State private var saveError: String?

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 12) {
                header
                canvasCard
                GuessPanel(session: session, table: table)
                collectButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if let celebration {
                CelebrationOverlay(celebration: celebration)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: celebration)
        .sensoryFeedback(.success, trigger: celebration)
        .alert("Could not save the sticker", isPresented: savingFailed) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var savingFailed: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    }

    private var header: some View {
        HStack {
            Text("DoodleDex")
                .font(.system(.title, design: .rounded, weight: .black))
                .foregroundStyle(Palette.ink)
            Spacer()
            Button("Undo", systemImage: "arrow.uturn.backward") { undo() }
                .accessibilityIdentifier("sketch.undo")
                .disabled(session.strokeCount == 0)
            Button("Clear", systemImage: "trash") { clear() }
                .accessibilityIdentifier("sketch.clear")
                .disabled(session.strokeCount == 0)
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .tint(Palette.ink)
        .padding(.top, 8)
    }

    private var canvasCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: Palette.ink.opacity(0.12), radius: 6, y: 3)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Palette.ink.opacity(0.14), style: StrokeStyle(lineWidth: 2, dash: [6, 7]))
                .padding(8)
            if session.strokeCount == 0 {
                Text("Draw something.\nI'll guess after every stroke.")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink.opacity(0.35))
                    .rotationEffect(.degrees(-2))
                    .allowsHitTesting(false)
            }
            SketchCanvas(drawing: $session.drawing) {
                Task { await session.drawingDidChange() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private var collectButton: some View {
        Button {
            collect()
        } label: {
            Label(collectTitle, systemImage: "star.square.on.square")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Palette.tomato)
        .disabled(!session.verdict.canCollect)
        .accessibilityIdentifier("sketch.collect")
    }

    private var collectTitle: String {
        if case .sure(let label) = session.verdict {
            return "Stick \(label.capitalized) in the Dex"
        }
        return "Keep drawing to earn a sticker"
    }

    private func undo() {
        session.undo()
        Task { await session.drawingDidChange() }
    }

    private func clear() {
        session.clear()
        Task { await session.drawingDidChange() }
    }

    private func collect() {
        guard case .sure(let label) = session.verdict else { return }
        do {
            let outcome = try DexBook(context: context).collect(
                category: label,
                probability: session.probability,
                strokes: session.simplifiedStrokes
            )
            celebration = Celebration(label: label, outcome: outcome)
            clear()
            Task {
                try? await Task.sleep(for: .seconds(2.4))
                celebration = nil
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct Celebration: Equatable {
    let label: String
    let outcome: DexBook.Outcome
}

private struct CelebrationOverlay: View {
    let celebration: Celebration

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .black))
            Text(celebration.label.capitalized)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.tomato)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Palette.ink.opacity(0.25), radius: 10, y: 4)
        .rotationEffect(.degrees(-3))
        .accessibilityIdentifier("sketch.celebration")
    }

    private var title: String {
        switch celebration.outcome {
        case .discovered: "New sticker!"
        case .repeated(let copies): "Copy number \(copies)"
        }
    }
}
