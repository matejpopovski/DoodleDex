import PencilKit
import SwiftUI

struct SketchCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let onStrokeFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        // Fingers must draw too: most phones have no stylus.
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor(Palette.ink), width: 6)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.accessibilityIdentifier = "sketch.canvas"
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = "Drawing area"
        canvas.accessibilityTraits = .allowsDirectInteraction
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SketchCanvas

        init(_ parent: SketchCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard parent.drawing != canvas.drawing else { return }
            parent.drawing = canvas.drawing
            parent.onStrokeFinished()
        }
    }
}
