import Foundation

/// Every letter and digit the app knows about.
/// A glyph becomes a race when its `track` is set. Home and the race screen
/// both read this list, so a new letter is a track plus one line here.
enum GlyphCatalog {
    static let letters: [Glyph] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { character in
        let symbol = String(character)
        return Glyph(
            id: symbol,
            symbol: symbol,
            kind: .letter,
            track: symbol == "A" ? LetterA.track : nil
        )
    }

    static let numbers: [Glyph] = (0...9).map { value in
        let symbol = String(value)
        return Glyph(id: symbol, symbol: symbol, kind: .number, track: nil)
    }

    static var all: [Glyph] { letters + numbers }

    static func glyph(id: String) -> Glyph? {
        all.first { $0.id == id }
    }
}
