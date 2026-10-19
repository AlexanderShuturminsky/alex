import Foundation

/// Shared curves for the handwriting-chart letters.
enum Manuscript {
    static func arc(
        center: LetterPoint,
        radius: Double,
        fromDeg: Double,
        toDeg: Double,
        steps: Int = 18
    ) -> [LetterPoint] {
        let count = max(steps, 2)
        return (0...count).map { step in
            let t = Double(step) / Double(count)
            let degrees = fromDeg + (toDeg - fromDeg) * t
            let radians = degrees * Double.pi / 180
            // 0° is the top of the circle. Positive degrees run counterclockwise on the page.
            return LetterPoint(
                x: center.x - radius * sin(radians),
                y: center.y - radius * cos(radians)
            )
        }
    }

    static func track(strokes: [[LetterPoint]], half: Double) -> LetterTrack {
        LetterTrack(
            strokes: strokes.enumerated().map { index, line in
                let end = line.last ?? LetterPoint(x: 50, y: 50)
                return LetterStroke(
                    id: index + 1,
                    centerline: line,
                    gate: FinishGate(center: end, radius: half + 4)
                )
            },
            roadHalfWidth: half
        )
    }
}

/// Lowercase a: circle from the top, counterclockwise, then the stem down.
enum LetterSmallA {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.arc(
                center: LetterPoint(x: 42, y: 64),
                radius: 16,
                fromDeg: -15,
                toDeg: 330,
                steps: 20
            ),
            [LetterPoint(x: 58, y: 48), LetterPoint(x: 58, y: 80)],
        ],
        half: 8
    )
}

/// Capital B: the stem down, then both bowls in one curve from the top.
enum LetterB {
    static let track = Manuscript.track(
        strokes: [
            [LetterPoint(x: 30, y: 14), LetterPoint(x: 30, y: 88)],
            [
                LetterPoint(x: 30, y: 14),
                LetterPoint(x: 48, y: 14),
                LetterPoint(x: 64, y: 26),
                LetterPoint(x: 58, y: 40),
                LetterPoint(x: 40, y: 50),
                LetterPoint(x: 30, y: 50),
                LetterPoint(x: 50, y: 54),
                LetterPoint(x: 72, y: 68),
                LetterPoint(x: 66, y: 84),
                LetterPoint(x: 44, y: 90),
                LetterPoint(x: 30, y: 88),
            ],
        ],
        half: 8
    )
}

/// Lowercase b: the tall stem down, then the bowl out to the right.
enum LetterSmallB {
    static let track = Manuscript.track(
        strokes: [
            [LetterPoint(x: 34, y: 12), LetterPoint(x: 34, y: 82)],
            [
                LetterPoint(x: 34, y: 48),
                LetterPoint(x: 50, y: 46),
                LetterPoint(x: 66, y: 56),
                LetterPoint(x: 66, y: 70),
                LetterPoint(x: 52, y: 82),
                LetterPoint(x: 34, y: 82),
            ],
        ],
        half: 8
    )
}

/// Capital Q: the circle counterclockwise from the top, then the short tail.
enum LetterQ {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.arc(
                center: LetterPoint(x: 48, y: 48),
                radius: 30,
                fromDeg: -40,
                toDeg: 320,
                steps: 24
            ),
            [LetterPoint(x: 56, y: 62), LetterPoint(x: 76, y: 88)],
        ],
        half: 8
    )
}

/// Lowercase q: the circle, then the descender with a small hook.
enum LetterSmallQ {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.arc(
                center: LetterPoint(x: 40, y: 60),
                radius: 15,
                fromDeg: -15,
                toDeg: 330,
                steps: 20
            ),
            [
                LetterPoint(x: 55, y: 46),
                LetterPoint(x: 55, y: 90),
                LetterPoint(x: 64, y: 98),
            ],
        ],
        half: 8
    )
}

/// Capital W: one continuous zigzag, down, up, down, up.
enum LetterW {
    static let track = Manuscript.track(
        strokes: [[
            LetterPoint(x: 14, y: 16),
            LetterPoint(x: 32, y: 88),
            LetterPoint(x: 50, y: 34),
            LetterPoint(x: 68, y: 88),
            LetterPoint(x: 86, y: 16),
        ]],
        half: 7
    )
}

/// Lowercase w: the same zigzag, between the midline and the baseline.
enum LetterSmallW {
    static let track = Manuscript.track(
        strokes: [[
            LetterPoint(x: 16, y: 48),
            LetterPoint(x: 32, y: 84),
            LetterPoint(x: 50, y: 58),
            LetterPoint(x: 68, y: 84),
            LetterPoint(x: 84, y: 48),
        ]],
        half: 7
    )
}
