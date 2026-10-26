import Foundation

/// A capital and its lowercase. The next pair opens after both letters
/// have been raced successfully seven times.
struct LetterLevel: Equatable, Identifiable {
    var id: String
    var capital: Glyph
    var small: Glyph

    var isPlayable: Bool { capital.isPlayable && small.isPlayable }
}

/// Every starter shape, letter, and digit the app knows about.
/// A glyph becomes a race when its `track` is set.
enum GlyphCatalog {
    /// Three pre-letter single-stroke warm-up shapes: Line, Curve, and Circle.
    static let starters: [Glyph] = [
        Glyph(id: "shape-line", symbol: "∣", kind: .shape, track: StarterLine.track),
        Glyph(id: "shape-curve", symbol: "⌒", kind: .shape, track: StarterCurve.track),
        Glyph(id: "shape-circle", symbol: "◯", kind: .shape, track: StarterCircle.track),
    ]

    static let levels: [LetterLevel] = makeLevels()

    private static func makeLevels() -> [LetterLevel] {
        let capitals = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let smalls = Array("abcdefghijklmnopqrstuvwxyz")
        return zip(capitals, smalls).map { capital, small in
            let capitalSymbol = String(capital)
            let smallSymbol = String(small)
            return LetterLevel(
                id: capitalSymbol,
                capital: glyph(symbol: capitalSymbol, track: track(for: capitalSymbol)),
                small: glyph(symbol: smallSymbol, track: track(for: smallSymbol))
            )
        }
    }

    static let letters: [Glyph] = levels.map(\.capital)
    static let smallLetters: [Glyph] = levels.map(\.small)

    static let numbers: [Glyph] = (0...9).map { value in
        let symbol = String(value)
        return Glyph(id: symbol, symbol: symbol, kind: .number, track: nil)
    }

    static var all: [Glyph] { letters + smallLetters + numbers }

    static var playableLevels: [LetterLevel] { levels.filter(\.isPlayable) }

    static func glyph(id: String) -> Glyph? {
        (starters + all).first { $0.id == id }
    }

    static func isStarterUnlocked(_ glyph: Glyph, progress: LevelProgress) -> Bool {
        glyph.kind == .shape && glyph.isPlayable
    }

    /// The first playable pair is open. Each later pair waits until the
    /// previous capital and lowercase both have seven passes.
    static func isUnlocked(_ level: LetterLevel, progress: LevelProgress) -> Bool {
        guard level.isPlayable else { return false }
        let playable = playableLevels
        guard let index = playable.firstIndex(where: { $0.id == level.id }) else { return false }
        if index == 0 { return true }
        let previous = playable[index - 1]
        return progress.isComplete(previous.capital.id) && progress.isComplete(previous.small.id)
    }

    private static func glyph(symbol: String, track: LetterTrack?) -> Glyph {
        Glyph(id: symbol, symbol: symbol, kind: .letter, track: track)
    }

    private static func track(for symbol: String) -> LetterTrack? {
        switch symbol {
        case "A": return LetterA.track
        case "a": return LetterSmallA.track
        case "B": return LetterB.track
        case "b": return LetterSmallB.track
        case "Q": return LetterQ.track
        case "q": return LetterSmallQ.track
        case "W": return LetterW.track
        case "w": return LetterSmallW.track
        default: return nil
        }
    }
}
