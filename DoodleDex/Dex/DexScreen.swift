import DoodleCore
import SwiftData
import SwiftUI

struct DexScreen: View {
    let resources: BundledResources
    let session: SketchSession

    @Query(sort: \DexEntry.firstCollectedAt, order: .reverse) private var entries: [DexEntry]
    @State private var selected: DexEntry?
    @State private var showingAbout = false

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 6)]

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !entries.isEmpty {
                        latestShelf
                    }
                    ForEach(resources.catalog.chapters) { chapter in
                        chapterSection(chapter)
                    }
                }
                .padding(16)
            }
        }
        .sheet(item: $selected) { entry in
            StickerDetail(entry: entry, chapter: resources.catalog.chapter(of: entry.category)?.name)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAbout) {
            AboutSheet(card: resources.modelCard, latency: session.latestLatencyMilliseconds)
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Your Dex")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                Spacer()
                Button("About this model", systemImage: "info.circle") { showingAbout = true }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .tint(Palette.ink)
                    .accessibilityIdentifier("dex.about")
            }
            Text("\(entries.count) of \(resources.catalog.total) stickers")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.7))
                .accessibilityIdentifier("dex.count")
            ProgressView(value: Double(entries.count), total: Double(resources.catalog.total))
                .tint(Palette.tomato)
        }
        .foregroundStyle(Palette.ink)
    }

    private var latestShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries) { entry in
                    Button {
                        selected = entry
                    } label: {
                        FilledSlot(entry: entry, chapter: resources.catalog.chapter(of: entry.category)?.name)
                            .frame(width: 104)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dex.latest.\(entry.category)")
                }
            }
        }
    }

    private func chapterSection(_ chapter: Catalog.Chapter) -> some View {
        let found = entries.filter { chapter.categories.contains($0.category) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(chapter.name)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(Palette.ink(forChapter: chapter.name))
                Text("\(found)/\(chapter.categories.count)")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(chapter.categories.enumerated()), id: \.element) { index, category in
                    slot(category, number: index + 1, chapter: chapter.name)
                }
            }
        }
    }

    @ViewBuilder
    private func slot(_ category: String, number: Int, chapter: String) -> some View {
        if let entry = entries.first(where: { $0.category == category }) {
            Button {
                selected = entry
            } label: {
                FilledSlot(entry: entry, chapter: chapter)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dex.slot.\(category)")
        } else {
            EmptySlot(number: number)
        }
    }
}

private struct FilledSlot: View {
    let entry: DexEntry
    let chapter: String?

    var body: some View {
        VStack(spacing: 3) {
            StickerArt(
                strokes: entry.latestSticker?.strokes ?? [],
                ink: Palette.ink(forChapter: chapter)
            )
            .aspectRatio(1, contentMode: .fit)
            .rotationEffect(.degrees(entry.category.stickerTilt))
            Text(entry.category.capitalized)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(6)
    }
}

private struct EmptySlot: View {
    let number: Int

    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Palette.ink.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                .overlay {
                    Text("?")
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .foregroundStyle(Palette.ink.opacity(0.2))
                }
                .aspectRatio(1, contentMode: .fit)
            Text("No. \(number)")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.35))
        }
        .padding(6)
        .accessibilityElement()
        .accessibilityLabel("Undiscovered sticker")
    }
}

private struct StickerDetail: View {
    let entry: DexEntry
    let chapter: String?

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 12) {
                StickerArt(
                    strokes: entry.latestSticker?.strokes ?? [],
                    ink: Palette.ink(forChapter: chapter),
                    inkWidth: 4,
                    haloWidth: 20
                )
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(entry.category.stickerTilt))
                Text(entry.category.capitalized)
                    .font(.system(.title, design: .rounded, weight: .black))
                Grid(alignment: .leading, verticalSpacing: 6) {
                    row("First stuck in", entry.firstCollectedAt.formatted(date: .abbreviated, time: .omitted))
                    row("Copies", "\(entry.stickers.count)")
                    row("Best confidence", entry.bestProbability.formatted(.percent.precision(.fractionLength(0))))
                    row("Fewest strokes", "\(entry.fewestStrokes)")
                }
                .font(.system(.body, design: .rounded))
            }
            .foregroundStyle(Palette.ink)
            .padding(20)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(Palette.ink.opacity(0.6))
            Text(value).fontWeight(.semibold)
        }
    }
}
