import SwiftUI

enum Palette {
    static let paper = Color(red: 0.984, green: 0.957, blue: 0.902)
    static let card = Color(red: 1.0, green: 0.984, blue: 0.945)
    static let ink = Color(red: 0.145, green: 0.165, blue: 0.2)
    static let tomato = Color(red: 0.827, green: 0.263, blue: 0.161)
    static let mustard = Color(red: 0.91, green: 0.651, blue: 0.11)
    static let leaf = Color(red: 0.204, green: 0.588, blue: 0.341)

    /// Each chapter of the book inks its stickers in its own colour.
    static func ink(forChapter name: String?) -> Color {
        switch name {
        case "Critters": Color(red: 0.039, green: 0.463, blue: 0.431)
        case "Snacks": tomato
        case "Outdoors": leaf
        case "Rides": Color(red: 0.227, green: 0.325, blue: 0.733)
        case "Places": Color(red: 0.525, green: 0.18, blue: 0.612)
        default: ink
        }
    }
}

/// Cream paper with a faint dot grid, drawn rather than shipped as an image.
struct PaperBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            var row: CGFloat = 8
            while row < size.height {
                var column: CGFloat = 8
                while column < size.width {
                    let dot = Path(ellipseIn: CGRect(x: column, y: row, width: 2.4, height: 2.4))
                    context.fill(dot, with: .color(Palette.ink.opacity(0.08)))
                    column += spacing
                }
                row += spacing
            }
        }
        .background(Palette.paper)
        .ignoresSafeArea()
    }
}
