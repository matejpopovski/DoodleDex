import DoodleCore
import SwiftUI

/// A player's drawing as a die-cut vinyl sticker: a thick white halo around the line art, then a
/// soft shadow, so the shape of the sticker is the shape of the doodle.
struct StickerArt: View {
    let strokes: [Stroke]
    let ink: Color
    var inkWidth: CGFloat = 2.5
    var haloWidth: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            let path = Self.path(for: strokes, in: size, inset: haloWidth / 2 + 2)
            let cap = StrokeStyle(lineWidth: haloWidth, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(.white), style: cap)
            let line = StrokeStyle(lineWidth: inkWidth, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(ink), style: line)
        }
        .shadow(color: Palette.ink.opacity(0.3), radius: 2.5, x: 0.5, y: 1.5)
    }

    /// Fits simplified strokes (0-255 space) into the view, centred, keeping their aspect ratio.
    static func path(for strokes: [Stroke], in size: CGSize, inset: CGFloat) -> Path {
        let points = strokes.joined()
        guard
            let maxX = points.map(\.x).max(),
            let maxY = points.map(\.y).max()
        else { return Path() }
        let extent = max(maxX, maxY, 1)
        let scale = (min(size.width, size.height) - inset * 2) / extent
        let originX = (size.width - maxX * scale) / 2
        let originY = (size.height - maxY * scale) / 2
        var path = Path()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            let start = CGPoint(x: originX + first.x * scale, y: originY + first.y * scale)
            path.move(to: start)
            path.addLine(to: start)
            for point in stroke.dropFirst() {
                path.addLine(to: CGPoint(x: originX + point.x * scale, y: originY + point.y * scale))
            }
        }
        return path
    }
}

extension String {
    /// A small tilt that stays the same across launches. `hashValue` is reseeded on every launch.
    var stickerTilt: Double {
        let sum = unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }
        return Double(sum % 13) - 6
    }
}
