import Foundation

/// Shared curves for the handwriting-chart letters.
/// Each stroke array is one numbered pen-down on the chart. A bend stays in that stroke.
enum Manuscript {
    /// 0° is the top. Positive degrees run counterclockwise on the page.
    /// A wider `radiusX` makes a bowl that is easier to sweep than a compass circle.
    static func oval(
        center: LetterPoint,
        radiusX: Double,
        radiusY: Double,
        fromDeg: Double,
        toDeg: Double,
        steps: Int = 18
    ) -> [LetterPoint] {
        let count = max(steps, 2)
        return (0...count).map { step in
            let t = Double(step) / Double(count)
            let degrees = fromDeg + (toDeg - fromDeg) * t
            let radians = degrees * Double.pi / 180
            return LetterPoint(
                x: center.x - radiusX * sin(radians),
                y: center.y - radiusY * cos(radians)
            )
        }
    }

    static func arc(
        center: LetterPoint,
        radius: Double,
        fromDeg: Double,
        toDeg: Double,
        steps: Int = 18
    ) -> [LetterPoint] {
        oval(center: center, radiusX: radius, radiusY: radius, fromDeg: fromDeg, toDeg: toDeg, steps: steps)
    }

    /// Right-hand bowl: a wide semi-oval from `top` around to `bottom`, bulging right.
    static func rightBowl(
        top: LetterPoint,
        bottom: LetterPoint,
        reach: Double,
        steps: Int = 16
    ) -> [LetterPoint] {
        let center = LetterPoint(x: (top.x + bottom.x) / 2, y: (top.y + bottom.y) / 2)
        var line = oval(
            center: center,
            radiusX: max(reach, 0.001),
            radiusY: max(abs(bottom.y - top.y) / 2, 0.001),
            fromDeg: 0,
            toDeg: -180,
            steps: steps
        )
        line[0] = top
        line[line.count - 1] = bottom
        return line
    }

    /// Replaces each sharp corner with a short arc so the stroke is easier to trace.
    static func softened(_ corners: [LetterPoint], radius: Double, steps: Int = 6) -> [LetterPoint] {
        guard corners.count >= 3, radius > 0.5 else { return corners }
        var path: [LetterPoint] = [corners[0]]
        for index in 1..<(corners.count - 1) {
            appendFillet(
                prev: corners[index - 1],
                corner: corners[index],
                next: corners[index + 1],
                radius: radius,
                steps: steps,
                to: &path
            )
        }
        appendDistinct(corners[corners.count - 1], to: &path)
        return path
    }

    /// Gentle curve through one control point, for tails and hooks.
    static func bend(
        from start: LetterPoint,
        through control: LetterPoint,
        to end: LetterPoint,
        steps: Int = 8
    ) -> [LetterPoint] {
        let count = max(steps, 2)
        return (0...count).map { step in
            let t = Double(step) / Double(count)
            let stay = 1 - t
            return LetterPoint(
                x: stay * stay * start.x + 2 * stay * t * control.x + t * t * end.x,
                y: stay * stay * start.y + 2 * stay * t * control.y + t * t * end.y
            )
        }
    }

    private static func appendFillet(
        prev: LetterPoint,
        corner: LetterPoint,
        next: LetterPoint,
        radius: Double,
        steps: Int,
        to path: inout [LetterPoint]
    ) {
        let backX = prev.x - corner.x
        let backY = prev.y - corner.y
        let fwdX = next.x - corner.x
        let fwdY = next.y - corner.y
        let backLen = hypot(backX, backY)
        let fwdLen = hypot(fwdX, fwdY)
        guard backLen > 0.001, fwdLen > 0.001 else {
            appendDistinct(corner, to: &path)
            return
        }
        let uBackX = backX / backLen
        let uBackY = backY / backLen
        let uFwdX = fwdX / fwdLen
        let uFwdY = fwdY / fwdLen
        let dot = min(1, max(-1, uBackX * uFwdX + uBackY * uFwdY))
        let alpha = acos(dot)
        // A straight run, or a fold that has to stay a turn, keeps its corner.
        guard alpha > 0.35, alpha < Double.pi - 0.2 else {
            appendDistinct(corner, to: &path)
            return
        }
        let tanHalf = tan(alpha / 2)
        let setback = min(radius / tanHalf, backLen * 0.45, fwdLen * 0.45)
        let used = setback * tanHalf
        let start = LetterPoint(x: corner.x + uBackX * setback, y: corner.y + uBackY * setback)
        let end = LetterPoint(x: corner.x + uFwdX * setback, y: corner.y + uFwdY * setback)
        let bisX = uBackX + uFwdX
        let bisY = uBackY + uFwdY
        let bisLen = hypot(bisX, bisY)
        guard bisLen > 0.001, used > 0.2 else {
            appendDistinct(corner, to: &path)
            return
        }
        let centerDist = used / sin(alpha / 2)
        let center = LetterPoint(
            x: corner.x + bisX / bisLen * centerDist,
            y: corner.y + bisY / bisLen * centerDist
        )
        appendDistinct(start, to: &path)
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var sweep = endAngle - startAngle
        if sweep > Double.pi { sweep -= 2 * Double.pi }
        if sweep < -Double.pi { sweep += 2 * Double.pi }
        let count = max(steps, 2)
        for step in 1..<count {
            let angle = startAngle + sweep * Double(step) / Double(count)
            appendDistinct(
                LetterPoint(x: center.x + used * cos(angle), y: center.y + used * sin(angle)),
                to: &path
            )
        }
        appendDistinct(end, to: &path)
    }

    private static func appendDistinct(_ point: LetterPoint, to path: inout [LetterPoint]) {
        if let last = path.last, last.distance(to: point) < 0.05 { return }
        path.append(point)
    }

    /// Grows a small letter until its longer side is `span` letter units, about 15% under a capital.
    static func enlarged(_ strokes: [[LetterPoint]], span: Double) -> [[LetterPoint]] {
        var minX = Double.greatestFiniteMagnitude
        var minY = minX
        var maxX = -minX
        var maxY = -minX
        for line in strokes {
            for point in line {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        let scale = span / max(width, height)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        return strokes.map { line in
            line.map { point in
                LetterPoint(
                    x: 50 + (point.x - centerX) * scale,
                    y: 50 + (point.y - centerY) * scale
                )
            }
        }
    }

    static func span(of strokes: [[LetterPoint]]) -> Double {
        var minX = Double.greatestFiniteMagnitude
        var minY = minX
        var maxX = -minX
        var maxY = -minX
        for line in strokes {
            for point in line {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }
        guard minX.isFinite else { return 1 }
        return max(maxX - minX, maxY - minY, 1)
    }

    static func track(strokes: [[LetterPoint]], half: Double, fitSpan: Double? = nil) -> LetterTrack {
        let fitted = fitSpan.map { enlarged(strokes, span: $0) } ?? strokes
        return LetterTrack(
            strokes: fitted.enumerated().map { index, line in
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

/// Lowercase a: a wide oval from the top, counterclockwise, then the stem down.
enum LetterSmallA {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.oval(
                center: LetterPoint(x: 38, y: 62),
                radiusX: 24,
                radiusY: 16,
                fromDeg: -25,
                toDeg: 335,
                steps: 24
            ),
            [LetterPoint(x: 62, y: 48), LetterPoint(x: 62, y: 86)],
        ],
        half: 12,
        fitSpan: Manuscript.span(of: LetterA.track.strokes.map(\.centerline)) * 0.85
    )
}

/// Capital B: the stem down, then both bowls in one curve from the top.
/// Each bowl is a wide oval, so the right side is round and the waist can fold back.
enum LetterB {
    private static let stemTop = LetterPoint(x: 30, y: 14)
    private static let waist = LetterPoint(x: 30, y: 50)
    private static let stemBottom = LetterPoint(x: 30, y: 88)

    static let track = Manuscript.track(
        strokes: [
            [stemTop, stemBottom],
            Manuscript.rightBowl(top: stemTop, bottom: waist, reach: 30)
                + Manuscript.rightBowl(top: waist, bottom: stemBottom, reach: 36).dropFirst(),
        ],
        half: 12
    )
}

/// Lowercase b: the tall stem down, then a round bowl out to the right.
enum LetterSmallB {
    private static let bowlTop = LetterPoint(x: 34, y: 46)
    private static let bowlBottom = LetterPoint(x: 34, y: 84)

    static let track = Manuscript.track(
        strokes: [
            [LetterPoint(x: 34, y: 12), bowlBottom],
            Manuscript.rightBowl(top: bowlTop, bottom: bowlBottom, reach: 28),
        ],
        half: 11,
        fitSpan: Manuscript.span(of: LetterB.track.strokes.map(\.centerline)) * 0.85
    )
}

/// Capital Q: a wide oval counterclockwise from the upper right, then a short curved tail.
enum LetterQ {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.oval(
                center: LetterPoint(x: 48, y: 46),
                radiusX: 34,
                radiusY: 24,
                fromDeg: -40,
                toDeg: 320,
                steps: 28
            ),
            Manuscript.bend(
                from: LetterPoint(x: 60, y: 62),
                through: LetterPoint(x: 72, y: 76),
                to: LetterPoint(x: 82, y: 90)
            ),
        ],
        half: 12
    )
}

/// Lowercase q: a wide oval, then a curved descender with a small hook.
enum LetterSmallQ {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.oval(
                center: LetterPoint(x: 38, y: 56),
                radiusX: 20,
                radiusY: 14,
                fromDeg: -20,
                toDeg: 340,
                steps: 22
            ),
            Manuscript.bend(
                from: LetterPoint(x: 58, y: 46),
                through: LetterPoint(x: 52, y: 90),
                to: LetterPoint(x: 74, y: 92)
            ),
        ],
        half: 11,
        fitSpan: Manuscript.span(of: LetterQ.track.strokes.map(\.centerline)) * 0.85
    )
}

/// Capital W: one continuous zigzag, down, up, down, up, with rounded turns.
enum LetterW {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.softened(
                [
                    LetterPoint(x: 14, y: 16),
                    LetterPoint(x: 32, y: 88),
                    LetterPoint(x: 50, y: 34),
                    LetterPoint(x: 68, y: 88),
                    LetterPoint(x: 86, y: 16),
                ],
                radius: 6
            ),
        ],
        half: 9
    )
}

/// Lowercase w: the same zigzag, between the midline and the baseline.
enum LetterSmallW {
    static let track = Manuscript.track(
        strokes: [
            Manuscript.softened(
                [
                    LetterPoint(x: 16, y: 48),
                    LetterPoint(x: 32, y: 84),
                    LetterPoint(x: 50, y: 58),
                    LetterPoint(x: 68, y: 84),
                    LetterPoint(x: 84, y: 48),
                ],
                radius: 5
            ),
        ],
        half: 8,
        fitSpan: Manuscript.span(of: LetterW.track.strokes.map(\.centerline)) * 0.85
    )
}
