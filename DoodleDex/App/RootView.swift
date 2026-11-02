import SwiftUI

struct RootView: View {
    let session: SketchSession
    let resources: BundledResources

    var body: some View {
        TabView {
            SketchScreen(session: session, table: resources.confidenceTable)
                .tabItem { Label("Sketch", systemImage: "scribble.variable") }
            DexScreen(resources: resources, session: session)
                .tabItem { Label("Dex", systemImage: "book.closed") }
        }
        .tint(Palette.tomato)
    }
}
