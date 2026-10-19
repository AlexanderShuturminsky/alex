import Foundation

/// Print capital A, matched to the painted racing track.
/// Stroke 1 follows the gray road from the lower left, over the round crown, to the lower right.
/// Stroke 2 is the crossbar, left to right. The picture fills the 0–100 letter square.
enum LetterA {
    static let roadHalfWidth = 7.0

    static let apex = LetterPoint(x: 49.90, y: 13.18)
    static let leftFoot = LetterPoint(x: 18.07, y: 79.10)
    static let rightFoot = LetterPoint(x: 81.74, y: 79.10)

    static let track = LetterTrack(
        strokes: [
            LetterStroke(
                id: 1,
                centerline: [
                    LetterPoint(x: 18.07, y: 79.10),
                    LetterPoint(x: 20.51, y: 73.05),
                    LetterPoint(x: 21.88, y: 69.92),
                    LetterPoint(x: 23.24, y: 66.80),
                    LetterPoint(x: 25.39, y: 61.52),
                    LetterPoint(x: 30.27, y: 49.61),
                    LetterPoint(x: 32.03, y: 43.36),
                    LetterPoint(x: 34.38, y: 37.11),
                    LetterPoint(x: 36.33, y: 32.42),
                    LetterPoint(x: 38.09, y: 27.73),
                    LetterPoint(x: 39.84, y: 23.05),
                    LetterPoint(x: 41.41, y: 21.48),
                    LetterPoint(x: 43.53, y: 17.85),
                    LetterPoint(x: 45.65, y: 15.26),
                    LetterPoint(x: 47.78, y: 13.70),
                    LetterPoint(x: 49.90, y: 13.18),
                    LetterPoint(x: 52.03, y: 13.70),
                    LetterPoint(x: 54.15, y: 15.26),
                    LetterPoint(x: 56.27, y: 17.85),
                    LetterPoint(x: 58.40, y: 21.48),
                    LetterPoint(x: 59.96, y: 23.05),
                    LetterPoint(x: 61.72, y: 27.73),
                    LetterPoint(x: 63.48, y: 32.42),
                    LetterPoint(x: 65.43, y: 37.11),
                    LetterPoint(x: 67.77, y: 43.36),
                    LetterPoint(x: 69.53, y: 49.61),
                    LetterPoint(x: 74.41, y: 61.52),
                    LetterPoint(x: 76.56, y: 66.80),
                    LetterPoint(x: 77.93, y: 69.92),
                    LetterPoint(x: 79.30, y: 73.05),
                    LetterPoint(x: 81.74, y: 79.10),
                ],
                gate: FinishGate(center: rightFoot, radius: roadHalfWidth + 4)
            ),
            LetterStroke(
                id: 2,
                centerline: [
                    LetterPoint(x: 37.40, y: 57.42),
                    LetterPoint(x: 70.80, y: 57.62),
                ],
                gate: FinishGate(center: LetterPoint(x: 70.80, y: 57.62), radius: roadHalfWidth + 4)
            ),
        ],
        roadHalfWidth: roadHalfWidth
    )
}
