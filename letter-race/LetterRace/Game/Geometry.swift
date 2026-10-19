import Foundation

struct LetterPoint: Equatable, Hashable {
    var x: Double
    var y: Double

    func distance(to other: LetterPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

struct RoadProjection: Equatable {
    var distance: Double
    var progress: Double
    var closest: LetterPoint
}

struct DirectionMark: Equatable {
    var point: LetterPoint
    var heading: LetterPoint
    var progress: Double
}

struct LetterViewport: Equatable {
    var width: Double
    var height: Double
    /// Margin on each edge, as a fraction of that edge. The letter fills the rest, so a
    /// margin of 0.05 uses 90% of the screen in both directions and stretches it taller.
    var margin: Double = 0.05

    var scaleX: Double {
        let available = max(0, width * (1 - margin * 2))
        guard available > 0, width > 0 else { return 0 }
        return available / 100
    }

    var scaleY: Double {
        let available = max(0, height * (1 - margin * 2))
        guard available > 0, height > 0 else { return 0 }
        return available / 100
    }

    /// Points per letter unit for round marks. The narrower axis, so a car stays on the road.
    var scale: Double { min(scaleX, scaleY) }

    var originX: Double { (width - 100 * scaleX) / 2 }
    var originY: Double { (height - 100 * scaleY) / 2 }

    func letter(x: Double, y: Double) -> LetterPoint {
        guard scaleX > 0, scaleY > 0 else { return LetterPoint(x: 0, y: 0) }
        return LetterPoint(x: (x - originX) / scaleX, y: (y - originY) / scaleY)
    }

    func viewX(_ point: LetterPoint) -> Double { originX + point.x * scaleX }
    func viewY(_ point: LetterPoint) -> Double { originY + point.y * scaleY }

    /// Screen points for one letter unit in `heading`'s direction.
    func viewScale(along heading: LetterPoint) -> Double {
        hypot(heading.x * scaleX, heading.y * scaleY)
    }

    /// Screen points for one letter unit perpendicular to `heading`.
    func viewScale(across heading: LetterPoint) -> Double {
        hypot(-heading.y * scaleX, heading.x * scaleY)
    }
}

enum RoadGeometry {
    static func project(
        _ point: LetterPoint,
        onto polyline: [LetterPoint],
        near progress: Double? = nil
    ) -> RoadProjection {
        guard let first = polyline.first else {
            return RoadProjection(distance: 0, progress: 0, closest: point)
        }
        guard polyline.count >= 2 else {
            return RoadProjection(distance: point.distance(to: first), progress: 0, closest: first)
        }

        let lengths = segmentLengths(polyline)
        let total = lengths.reduce(0, +)
        var bestDistance = Double.greatestFiniteMagnitude
        var bestProgress = 0.0
        var bestPoint = first
        var nearDistance = Double.greatestFiniteMagnitude
        var nearProgress = 0.0
        var nearPoint = first
        let continuity = progress.map { near -> (low: Double, high: Double) in
            let anchor = min(1, max(0, near)) * total
            // Stay with the part of the stroke under the finger. A loop's end can sit on
            // its start, and B folds back, so the globally nearest point can be the wrong lap.
            return (anchor - 14, anchor + max(64, total * 0.45))
        }
        var traveled = 0.0

        for index in 0..<(polyline.count - 1) {
            let segment = lengths[index]
            let segmentStart = traveled
            traveled += segment
            let start = polyline[index]
            let end = polyline[index + 1]
            let (closest, t) = closestPoint(point, start, end)
            let distance = point.distance(to: closest)
            let along = segmentStart + t * segment
            if distance < bestDistance {
                bestDistance = distance
                bestPoint = closest
                bestProgress = total > 0 ? along / total : 0
            }
            if let continuity, along >= continuity.low, along <= continuity.high, distance < nearDistance {
                nearDistance = distance
                nearPoint = closest
                nearProgress = total > 0 ? along / total : 0
            }
        }

        // Prefer the continuation when the finger is still near it. A big jump ahead,
        // or a real reverse, falls through to the globally nearest point.
        if let _ = continuity, nearDistance <= 18 || nearDistance <= bestDistance + 6 {
            return RoadProjection(distance: nearDistance, progress: nearProgress, closest: nearPoint)
        }
        return RoadProjection(distance: bestDistance, progress: bestProgress, closest: bestPoint)
    }

    static func length(of polyline: [LetterPoint]) -> Double {
        segmentLengths(polyline).reduce(0, +)
    }

    static func point(at progress: Double, along polyline: [LetterPoint]) -> LetterPoint {
        guard let first = polyline.first else { return LetterPoint(x: 0, y: 0) }
        guard polyline.count >= 2 else { return first }
        let total = length(of: polyline)
        guard total > 0 else { return first }

        let clamped = min(1, max(0, progress))
        var remaining = clamped * total
        let lengths = segmentLengths(polyline)
        for index in 0..<(polyline.count - 1) {
            let segment = lengths[index]
            if remaining <= segment || index == polyline.count - 2 {
                let t = segment == 0 ? 0 : remaining / segment
                let start = polyline[index]
                let end = polyline[index + 1]
                return LetterPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                )
            }
            remaining -= segment
        }
        return polyline[polyline.count - 1]
    }

    static func prefix(_ polyline: [LetterPoint], through progress: Double) -> [LetterPoint] {
        guard let first = polyline.first else { return [] }
        guard polyline.count >= 2 else { return polyline }
        let clamped = min(1, max(0, progress))
        if clamped == 0 { return [first] }
        if clamped >= 1 { return polyline }

        let total = length(of: polyline)
        let target = clamped * total
        var traveled = 0.0
        var result = [first]
        let lengths = segmentLengths(polyline)
        for index in 0..<(polyline.count - 1) {
            let segment = lengths[index]
            if traveled + segment >= target - 0.000_001 {
                result.append(point(at: clamped, along: polyline))
                return result
            }
            traveled += segment
            result.append(polyline[index + 1])
        }
        return polyline
    }

    static func isOnRoad(_ point: LetterPoint, polyline: [LetterPoint], halfWidth: Double) -> Bool {
        project(point, onto: polyline).distance <= halfWidth
    }

    static func heading(of polyline: [LetterPoint]) -> LetterPoint? {
        heading(of: polyline, at: 0)
    }

    /// Chevrons along a stroke. They start clear of the car and stop before the finish.
    static func directionMarks(
        along polyline: [LetterPoint],
        spacing: Double = 16,
        leadingInset: Double = 13,
        trailingInset: Double = 9
    ) -> [DirectionMark] {
        let total = length(of: polyline)
        guard total > 1, polyline.count >= 2 else { return [] }
        let gap = max(spacing, 1)
        let lead = min(max(0, leadingInset), total * 0.45)
        let trail = min(max(0, trailingInset), total * 0.4)
        var distances: [Double] = []
        var cursor = lead
        let limit = total - trail
        if cursor <= limit {
            while cursor <= limit + 0.001 {
                distances.append(min(cursor, total))
                cursor += gap
            }
        }
        if distances.isEmpty {
            distances = [total * 0.55]
        }
        return distances.compactMap { distance in
            let progress = min(1, max(0, distance / total))
            guard let heading = heading(of: polyline, at: progress) else { return nil }
            return DirectionMark(
                point: point(at: progress, along: polyline),
                heading: heading,
                progress: progress
            )
        }
    }

    /// Direction of the road at `progress`, so a curve's backward check follows the local stroke.
    static func heading(of polyline: [LetterPoint], at progress: Double) -> LetterPoint? {
        guard polyline.count >= 2 else { return nil }
        let lengths = segmentLengths(polyline)
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }

        let target = min(1, max(0, progress)) * total
        var traveled = 0.0
        for index in 0..<(polyline.count - 1) {
            let segment = lengths[index]
            if traveled + segment >= target - 0.000_001 || index == polyline.count - 2 {
                let start = polyline[index]
                let end = polyline[index + 1]
                let dx = end.x - start.x
                let dy = end.y - start.y
                let span = (dx * dx + dy * dy).squareRoot()
                guard span > 0 else { return nil }
                return LetterPoint(x: dx / span, y: dy / span)
            }
            traveled += segment
        }
        return nil
    }

    static func shifted(
        _ point: LetterPoint,
        from start: LetterPoint,
        toward end: LetterPoint,
        sideways: Double
    ) -> LetterPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let span = (dx * dx + dy * dy).squareRoot()
        guard span > 0 else { return point }
        return LetterPoint(x: point.x + (-dy / span) * sideways, y: point.y + (dx / span) * sideways)
    }

    private static func segmentLengths(_ polyline: [LetterPoint]) -> [Double] {
        guard polyline.count >= 2 else { return [] }
        return (0..<(polyline.count - 1)).map { polyline[$0].distance(to: polyline[$0 + 1]) }
    }

    private static func closestPoint(
        _ point: LetterPoint,
        _ start: LetterPoint,
        _ end: LetterPoint
    ) -> (LetterPoint, Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        let t: Double
        if lengthSquared == 0 {
            t = 0
        } else {
            let raw = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
            t = min(1, max(0, raw))
        }
        return (LetterPoint(x: start.x + dx * t, y: start.y + dy * t), t)
    }
}

/// The hatched band at the end of a stroke. Offsets are letter units along the road
/// heading: negative is before the gate, positive is past it.
enum FinishZone {
    static let spacing = 2.0
    static let firstTick = -1.2
    static let count = 6

    static var offsets: [Double] {
        (0..<count).map { (Double($0) + firstTick) * spacing }
    }

    static var middleOffset: Double {
        let marks = offsets
        return ((marks.first ?? 0) + (marks.last ?? 0)) / 2
    }

    static var endOffset: Double {
        offsets.last ?? 0
    }

    static func point(on stroke: LetterStroke, offset: Double) -> LetterPoint {
        let gate = stroke.gate.center
        guard let heading = RoadGeometry.heading(of: stroke.centerline, at: 1) else { return gate }
        return LetterPoint(x: gate.x + heading.x * offset, y: gate.y + heading.y * offset)
    }

    static func middle(on stroke: LetterStroke) -> LetterPoint {
        point(on: stroke, offset: middleOffset)
    }

    static func extended(_ centerline: [LetterPoint], on stroke: LetterStroke, through offset: Double) -> [LetterPoint] {
        var line = centerline
        line.append(point(on: stroke, offset: offset))
        return line
    }
}

struct StrokeAccuracy: Equatable {
    var closeness: Double
    var stars: Int

    var isGoodEnough: Bool { stars >= 2 }

    static func measure(
        path: [LetterPoint],
        centerline: [LetterPoint],
        halfWidth: Double,
        wallHits: Int
    ) -> StrokeAccuracy {
        guard halfWidth > 0, !path.isEmpty else {
            return StrokeAccuracy(closeness: 0, stars: 1)
        }
        let distances = path.map { RoadGeometry.project($0, onto: centerline).distance }
        let onRoad = distances.filter { $0 <= halfWidth * 1.25 }
        let samples = onRoad.isEmpty ? distances : onRoad
        let mean = samples.reduce(0, +) / Double(samples.count)
        let raw = 1 - min(1, mean / halfWidth)
        let closeness = max(0, raw - Double(wallHits) * 0.16)
        return StrokeAccuracy(closeness: closeness, stars: stars(for: closeness))
    }

    static func stars(for closeness: Double) -> Int {
        if closeness >= 0.80 { return 3 }
        if closeness >= 0.62 { return 2 }
        return 1
    }
}
