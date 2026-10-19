import Foundation

/// Print capital A from the handwriting chart.
/// Stroke 1 is one move: bottom-left, up over the apex, down to the bottom-right.
/// The apex is not a pen lift. Stroke 2 is the crossbar, left to right.
enum LetterA {
    static let roadHalfWidth = 9.0

    static let apex = LetterPoint(x: 50, y: 14)
    static let leftFoot = LetterPoint(x: 16, y: 90)
    static let rightFoot = LetterPoint(x: 84, y: 90)

    static let track: LetterTrack = {
        let barY = (apex.y + leftFoot.y) / 2
        let leftJoin = point(from: leftFoot, to: apex, y: barY)
        let rightJoin = point(from: apex, to: rightFoot, y: barY)
        let gateRadius = roadHalfWidth + 4
        return LetterTrack(
            strokes: [
                LetterStroke(
                    id: 1,
                    centerline: [leftFoot, apex, rightFoot],
                    gate: FinishGate(center: rightFoot, radius: gateRadius)
                ),
                LetterStroke(
                    id: 2,
                    centerline: [leftJoin, rightJoin],
                    gate: FinishGate(center: rightJoin, radius: gateRadius)
                ),
            ],
            roadHalfWidth: roadHalfWidth
        )
    }()

    private static func point(from start: LetterPoint, to end: LetterPoint, y: Double) -> LetterPoint {
        let t = (y - start.y) / (end.y - start.y)
        return LetterPoint(x: start.x + (end.x - start.x) * t, y: y)
    }
}
