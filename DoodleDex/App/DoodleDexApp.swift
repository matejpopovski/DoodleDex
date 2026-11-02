import SwiftData
import SwiftUI

@main
struct DoodleDexApp: App {
    private let container: ModelContainer
    private let bundleResources: BundledResources
    @State private var session: SketchSession

    init() {
        do {
            // SwiftData logs a failed first attempt if this directory does not exist yet.
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            let store = try ModelContainer(for: DexEntry.self, Sticker.self)
            let resources = try BundledResources.load()
            // UI tests start from an empty book so that their counts are deterministic.
            if ProcessInfo.processInfo.arguments.contains("--fresh-collection") {
                try store.mainContext.delete(model: DexEntry.self)
                try store.mainContext.save()
            }
            container = store
            bundleResources = resources
            _session = State(
                initialValue: SketchSession(
                    recognizer: try Recognizer.bundled(),
                    table: resources.confidenceTable
                )
            )
        } catch {
            fatalError("DoodleDex cannot start without its bundled model and store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, resources: bundleResources)
                .preferredColorScheme(.light)
                .modelContainer(container)
        }
    }
}
