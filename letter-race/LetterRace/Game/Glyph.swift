import Foundation

enum GlyphKind: Equatable {
    case letter
    case number
}

struct FinishGate: Equatable {
    var center: LetterPoint
    var radius: Double
}

struct LetterStroke: Equatable, Identifiable {
    var id: Int
    var centerline: [LetterPoint]
    var gate: FinishGate

    var start: LetterPoint { centerline[0] }
}

struct LetterTrack: Equatable {
    var strokes: [LetterStroke]
    var roadHalfWidth: Double
}

struct Glyph: Equatable, Identifiable {
    var id: String
    var symbol: String
    var kind: GlyphKind
    var track: LetterTrack?

    var isPlayable: Bool { track != nil }
}
