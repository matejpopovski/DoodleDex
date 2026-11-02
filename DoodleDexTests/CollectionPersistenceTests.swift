import DoodleCore
import SwiftData
import XCTest

@testable import DoodleDex

/// Uses an on-disk store and reopens it, because an in-memory container would pass these tests
/// even if nothing were ever written.
@MainActor
final class CollectionPersistenceTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "dex.store")
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    private func openContainer() throws -> ModelContainer {
        try ModelContainer(for: DexEntry.self, Sticker.self, configurations: ModelConfiguration(url: storeURL))
    }

    private let doodle: [Stroke] = [
        [StrokePoint(x: 0, y: 0), StrokePoint(x: 255, y: 120)],
        [StrokePoint(x: 10, y: 200)],
    ]

    func testStickerSurvivesReopeningTheStore() throws {
        do {
            let container = try openContainer()
            let outcome = try DexBook(context: container.mainContext).collect(
                category: "house",
                probability: 0.91,
                strokes: doodle
            )
            XCTAssertEqual(outcome, .discovered)
        }

        let reopened = try openContainer()
        let entries = try reopened.mainContext.fetch(FetchDescriptor<DexEntry>())
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.category, "house")
        XCTAssertEqual(entry.bestProbability, 0.91)
        XCTAssertEqual(entry.fewestStrokes, 2)
        XCTAssertEqual(entry.stickers.count, 1)
        XCTAssertEqual(entry.latestSticker?.strokes, doodle)
    }

    func testRepeatDrawingUpdatesStatsWithoutDuplicatingTheEntry() throws {
        let container = try openContainer()
        let book = DexBook(context: container.mainContext)
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)

        try book.collect(category: "star", probability: 0.8, strokes: doodle, at: early)
        let outcome = try book.collect(
            category: "star",
            probability: 0.7,
            strokes: Array(doodle.prefix(1)),
            at: late
        )

        XCTAssertEqual(outcome, .repeated(copies: 2))
        let entries = try container.mainContext.fetch(FetchDescriptor<DexEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].bestProbability, 0.8)
        XCTAssertEqual(entries[0].fewestStrokes, 1)
        XCTAssertEqual(entries[0].firstCollectedAt, early)
        XCTAssertEqual(entries[0].latestSticker?.strokeCount, 1)
    }

    func testDeletingAnEntryRemovesItsStickers() throws {
        let container = try openContainer()
        let context = container.mainContext
        try DexBook(context: context).collect(category: "cat", probability: 0.9, strokes: doodle)
        try context.delete(model: DexEntry.self)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Sticker>()), 0)
    }
}
