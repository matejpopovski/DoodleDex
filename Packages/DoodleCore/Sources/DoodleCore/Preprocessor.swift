import Foundation

/// A point in whatever coordinate system the strokes arrive in.
public struct StrokePoint: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public typealias Stroke = [StrokePoint]

/// Constants of the Quick, Draw! rendering. `ml/doodledex_ml/pipeline.py` holds the same values,
/// and `results/dataset_parity.json` records how they were confirmed against published bitmaps.
public struct PipelineConfig: Equatable, Sendable {
    public var scaledExtent = 255.0
    public var resampleSpacing = 1.0
    public var rdpEpsilon = 2.0
    public var canvas = 256.0
    public var side = 28
    public var lineDiameter = 16.0
    public var padding = 16.0
    public var supersample = 8

    public init() {}

    public static let standard = PipelineConfig()
}

/// A port of `ml/doodledex_ml/pipeline.py`, written as the same IEEE double operations in the same
/// order so that it reproduces the Python bytes exactly. Reordering an expression here can change
/// a rounding and fail the parity tests, which is the point of them.
public enum Preprocessor {
    /// The whole pipeline: strokes in any coordinate system to 28x28 row-major pixels. Ink is high.
    public static func preprocess(_ strokes: [Stroke], config: PipelineConfig = .standard) -> [UInt8] {
        rasterize(simplify(strokes, config: config), config: config)
    }

    public static func normalize(_ strokes: [Stroke], config: PipelineConfig = .standard) -> [Stroke] {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for point in strokes.joined() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        let extent = Swift.max(maxX - minX, maxY - minY)
        // A lone tap has no extent, and dividing by it would turn the dot into NaNs.
        let scale = extent > 0 ? config.scaledExtent / extent : 1.0
        return strokes.map { stroke in
            stroke.map { StrokePoint(x: ($0.x - minX) * scale, y: ($0.y - minY) * scale) }
        }
    }

    /// Walks the polyline and emits a point every `spacing` units, keeping both endpoints.
    public static func resample(_ stroke: Stroke, spacing: Double) -> Stroke {
        guard let first = stroke.first, let last = stroke.last else { return [] }
        var output = [first]
        var travelled = 0.0
        for index in stroke.indices.dropLast() {
            let a = stroke[index]
            let b = stroke[index + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            if length == 0 { continue }
            var position = spacing - travelled
            while position <= length {
                let t = position / length
                output.append(StrokePoint(x: a.x + t * dx, y: a.y + t * dy))
                position += spacing
            }
            travelled = length - (position - spacing)
        }
        if output[output.count - 1] != last {
            output.append(last)
        }
        return output
    }

    /// Ramer-Douglas-Peucker with an explicit stack, because a slow stroke can be very long.
    /// Distance is to the infinite line through the endpoints, which is what reproduces Google's
    /// published strokes. `results/dataset_parity.json` has the comparison against segment distance.
    public static func rdp(_ stroke: Stroke, epsilon: Double) -> Stroke {
        let count = stroke.count
        guard count >= 3 else { return stroke }
        var keep = [Bool](repeating: false, count: count)
        keep[0] = true
        keep[count - 1] = true
        let limit = epsilon * epsilon
        var stack = [(first: 0, last: count - 1)]
        while let (first, last) = stack.popLast() {
            var farthest = -1
            var largest = limit
            var index = first + 1
            while index < last {
                let distance = squaredDistance(stroke[index], stroke[first], stroke[last])
                if distance > largest {
                    largest = distance
                    farthest = index
                }
                index += 1
            }
            if farthest >= 0 {
                keep[farthest] = true
                stack.append((first, farthest))
                stack.append((farthest, last))
            }
        }
        return zip(stroke, keep).compactMap { $1 ? $0 : nil }
    }

    /// Input strokes to the integer strokes of the simplified dataset.
    public static func simplify(_ strokes: [Stroke], config: PipelineConfig = .standard) -> [Stroke] {
        let occupied = strokes.filter { !$0.isEmpty }
        return normalize(occupied, config: config).map { stroke in
            rdp(resample(stroke, spacing: config.resampleSpacing), epsilon: config.rdpEpsilon).map {
                StrokePoint(x: roundHalfUp($0.x), y: roundHalfUp($0.y))
            }
        }
    }

    /// Renders simplified strokes. Each stroke is a capsule union on a supersampled grid, and
    /// strokes composite over each other, matching how the published bitmaps treat overlaps.
    public static func rasterize(_ strokes: [Stroke], config: PipelineConfig = .standard) -> [UInt8] {
        let side = config.side
        let supersample = config.supersample
        guard strokes.contains(where: { !$0.isEmpty }) else {
            return [UInt8](repeating: 0, count: side * side)
        }
        let grid = side * supersample
        let totalPadding = config.padding * 2.0 + config.lineDiameter
        let scale = Double(side) / (config.canvas + totalPadding)
        let radius = config.lineDiameter / 2.0 * scale
        let radiusSquared = radius * radius
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for point in strokes.joined() {
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        let offsetX = (config.canvas - maxX) / 2.0
        let offsetY = (config.canvas - maxY) / 2.0
        let centers = (0..<grid).map { (Double($0) + 0.5) / Double(supersample) }
        let scaleFactor = Double(supersample)
        let subpixels = Double(supersample * supersample)

        var image = [Double](repeating: 0, count: side * side)
        var mask = [Bool](repeating: false, count: grid * grid)
        var counts = [Int](repeating: 0, count: side * side)
        for stroke in strokes where !stroke.isEmpty {
            var scaled = stroke.map {
                StrokePoint(
                    x: ($0.x + offsetX + totalPadding / 2.0) * scale,
                    y: ($0.y + offsetY + totalPadding / 2.0) * scale
                )
            }
            if scaled.count == 1 {
                scaled.append(scaled[0])
            }
            mask.withUnsafeMutableBufferPointer { $0.update(repeating: false) }
            for index in scaled.indices.dropLast() {
                let a = scaled[index]
                let b = scaled[index + 1]
                let lowX = Swift.max(Int(((Swift.min(a.x, b.x) - radius) * scaleFactor).rounded(.down)), 0)
                let highX = Swift.min(Int(((Swift.max(a.x, b.x) + radius) * scaleFactor).rounded(.up)) + 1, grid)
                let lowY = Swift.max(Int(((Swift.min(a.y, b.y) - radius) * scaleFactor).rounded(.down)), 0)
                let highY = Swift.min(Int(((Swift.max(a.y, b.y) + radius) * scaleFactor).rounded(.up)) + 1, grid)
                if lowX >= highX || lowY >= highY { continue }
                let dx = b.x - a.x
                let dy = b.y - a.y
                let lengthSquared = dx * dx + dy * dy
                for gridY in lowY..<highY {
                    let py = centers[gridY]
                    for gridX in lowX..<highX where !mask[gridY * grid + gridX] {
                        let px = centers[gridX]
                        var t = 0.0
                        if lengthSquared != 0 {
                            t = ((px - a.x) * dx + (py - a.y) * dy) / lengthSquared
                            t = Swift.max(0.0, Swift.min(1.0, t))
                        }
                        let ex = px - a.x - t * dx
                        let ey = py - a.y - t * dy
                        if ex * ex + ey * ey <= radiusSquared {
                            mask[gridY * grid + gridX] = true
                        }
                    }
                }
            }
            counts.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            for gridY in 0..<grid {
                for gridX in 0..<grid where mask[gridY * grid + gridX] {
                    counts[(gridY / supersample) * side + gridX / supersample] += 1
                }
            }
            for pixel in image.indices {
                image[pixel] = 1.0 - (1.0 - image[pixel]) * (1.0 - Double(counts[pixel]) / subpixels)
            }
        }
        return image.map { UInt8((($0 * 255.0) + 0.5).rounded(.down)) }
    }

    private static func squaredDistance(_ p: StrokePoint, _ a: StrokePoint, _ b: StrokePoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            let ex = p.x - a.x
            let ey = p.y - a.y
            return ex * ex + ey * ey
        }
        let cross = (p.x - a.x) * dy - (p.y - a.y) * dx
        return cross * cross / lengthSquared
    }

    private static func roundHalfUp(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }
}
