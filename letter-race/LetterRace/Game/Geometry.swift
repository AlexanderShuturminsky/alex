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

struct LetterViewport: Equatable {
    var width: Double
    var height: Double
    var inset: Double = 36

    var scale: Double {
        let availableWidth = max(0, width - inset * 2)
        let availableHeight = max(0, height - inset * 2)
        guard availableWidth > 0, availableHeight > 0 else { return 0 }
        return min(availableWidth / 100, availableHeight / 100)
    }

    var originX: Double { (width - 100 * scale) / 2 }
    var originY: Double { (height - 100 * scale) / 2 }

    func letter(x: Double, y: Double) -> LetterPoint {
        guard scale > 0 else { return LetterPoint(x: 0, y: 0) }
        return LetterPoint(x: (x - originX) / scale, y: (y - originY) / scale)
    }

    func viewX(_ point: LetterPoint) -> Double { originX + point.x * scale }
    func viewY(_ point: LetterPoint) -> Double { originY + point.y * scale }
}

enum RoadGeometry {
    static func project(_ point: LetterPoint, onto polyline: [LetterPoint]) -> RoadProjection {
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
        var traveled = 0.0

        for index in 0..<(polyline.count - 1) {
            let start = polyline[index]
            let end = polyline[index + 1]
            let (closest, t) = closestPoint(point, start, end)
            let distance = point.distance(to: closest)
            if distance < bestDistance {
                bestDistance = distance
                bestPoint = closest
                let along = traveled + t * lengths[index]
                bestProgress = total > 0 ? along / total : 0
            }
            traveled += lengths[index]
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
