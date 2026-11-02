import Foundation

/// What the guess panel says, decided by the calibrated probability alone so that the wording and
/// the sticker offer can never disagree with the number on screen.
public enum Verdict: Equatable, Sendable {
    case blank
    case scribbling
    case leaning(String)
    case sure(String)

    public static let leaningFloor = 0.35

    public init(label: String?, probability: Double, stickerThreshold: Double) {
        guard let label else {
            self = .blank
            return
        }
        if probability >= stickerThreshold {
            self = .sure(label)
        } else if probability >= Self.leaningFloor {
            self = .leaning(label)
        } else {
            self = .scribbling
        }
    }

    public var canCollect: Bool {
        if case .sure = self { return true }
        return false
    }
}
