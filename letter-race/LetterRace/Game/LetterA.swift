import Foundation

/// Print capital A, the way beginners are taught to write it.
/// Handwriting Without Tears: start at the top, big line down to the left,
/// big line down to the right, little line across the middle.
/// Three pen-downs, so the track has three cars.
enum LetterA {
    static let roadHalfWidth = 9.0

    static let apex = LetterPoint(x: 50, y: 14)
    static let leftFoot = LetterPoint(x: 16, y: 90)
    static let rightFoot = LetterPoint(x: 84, y: 90)

    static let track: LetterTrack = {
        let barY = (apex.y + leftFoot.y) / 2
        let leftJoin = point(from: apex, to: leftFoot, y: barY)
        let rightJoin = point(from: apex, to: rightFoot, y: barY)
        let gateRadius = roadHalfWidth + 4
        return LetterTrack(
            strokes: [
                LetterStroke(
                    id: 1,
                    centerline: [apex, leftFoot],
                    gate: FinishGate(center: leftFoot, radius: gateRadius)
                ),
                LetterStroke(
                    id: 2,
                    centerline: [apex, rightFoot],
                    gate: FinishGate(center: rightFoot, radius: gateRadius)
                ),
                LetterStroke(
                    id: 3,
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
