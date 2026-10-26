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
    /// Margin on each edge, as a fraction of that edge. One scale keeps the letter's
    /// own height, leaving room around the road for curbs, start arrows, and roll-in.
    var margin: Double = 0.08
    var track: LetterTrack? = nil

    var scaleX: Double { scale }
    var scaleY: Double { scale }

    private var fittedBounds: TrackBounds {
        track?.cachedBounds ?? TrackBounds(minX: 0, maxX: 100, minY: 0, maxY: 100)
    }

    /// Points per letter unit. The same on both axes so aspect ratio is never distorted.
    var scale: Double {
        if track != nil {
            let edgeMarginX = 0.025
            let edgeMarginY = 0.055
            let availableWidth = max(0, width * (1 - edgeMarginX * 2))
            let availableHeight = max(0, height * (1 - edgeMarginY * 2))
            guard availableWidth > 0, availableHeight > 0 else { return 0 }
            let bounds = fittedBounds
            let spanX = max(bounds.maxX - bounds.minX, 60.0)
            let spanY = max(bounds.maxY - bounds.minY, 60.0)
            return min(availableWidth / spanX, availableHeight / spanY)
        }
        let availableWidth = max(0, width * (1 - margin * 2))
        let availableHeight = max(0, height * (1 - margin * 2))
        guard availableWidth > 0, availableHeight > 0 else { return 0 }
        return min(availableWidth, availableHeight) / 100
    }

    var originX: Double {
        let bounds = fittedBounds
        let centerX = (bounds.minX + bounds.maxX) / 2
        return width / 2 - centerX * scaleX
    }

    var originY: Double {
        let bounds = fittedBounds
        let centerY = (bounds.minY + bounds.maxY) / 2
        return height / 2 - centerY * scaleY
    }

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
    static func cumulativeLengths(_ polyline: [LetterPoint]) -> [Double] {
        guard polyline.count >= 2 else { return [0] }
        var cum = Array(repeating: 0.0, count: polyline.count)
        for index in 0..<(polyline.count - 1) {
            cum[index + 1] = cum[index] + polyline[index].distance(to: polyline[index + 1])
        }
        return cum
    }

    static func point(atDistance target: Double, along polyline: [LetterPoint], cumulative: [Double]) -> LetterPoint {
        guard let first = polyline.first else { return LetterPoint(x: 0, y: 0) }
        guard polyline.count >= 2, let total = cumulative.last, total > 0 else { return first }
        if target <= 0 { return first }
        if target >= total { return polyline[polyline.count - 1] }

        var low = 0
        var high = cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= target {
                low = mid
            } else {
                high = mid
            }
        }
        let segLen = cumulative[high] - cumulative[low]
        let t = segLen > 0 ? (target - cumulative[low]) / segLen : 0
        let start = polyline[low]
        let end = polyline[high]
        return LetterPoint(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t
        )
    }

    static func heading(
        atDistance target: Double,
        along polyline: [LetterPoint],
        cumulative: [Double]
    ) -> LetterPoint? {
        guard polyline.count >= 2, let total = cumulative.last, total > 0 else { return nil }
        let clamped = min(total, max(0, target))
        let halfWindow = min(total * 0.025, 1.25)
        let d0 = max(0, clamped - halfWindow)
        let d1 = min(total, clamped + halfWindow)
        let start = point(atDistance: d0, along: polyline, cumulative: cumulative)
        let end = point(atDistance: d1, along: polyline, cumulative: cumulative)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let span = (dx * dx + dy * dy).squareRoot()
        guard span > 0.000_001 else {
            for index in 0..<(polyline.count - 1) {
                let segDx = polyline[index + 1].x - polyline[index].x
                let segDy = polyline[index + 1].y - polyline[index].y
                let segSpan = (segDx * segDx + segDy * segDy).squareRoot()
                if segSpan > 0 {
                    return LetterPoint(x: segDx / segSpan, y: segDy / segSpan)
                }
            }
            return nil
        }
        return LetterPoint(x: dx / span, y: dy / span)
    }

    static func project(
        _ point: LetterPoint,
        onto polyline: [LetterPoint],
        near progress: Double? = nil
    ) -> RoadProjection {
        project(point, onto: polyline, cumulative: cumulativeLengths(polyline), near: progress)
    }

    static func project(
        _ point: LetterPoint,
        onto polyline: [LetterPoint],
        cumulative: [Double],
        near progress: Double? = nil
    ) -> RoadProjection {
        guard let first = polyline.first else {
            return RoadProjection(distance: 0, progress: 0, closest: point)
        }
        guard polyline.count >= 2 else {
            return RoadProjection(distance: point.distance(to: first), progress: 0, closest: first)
        }

        let total = cumulative.last ?? 0
        var bestDistance = Double.greatestFiniteMagnitude
        var bestProgress = 0.0
        var bestPoint = first
        var nearDistance = Double.greatestFiniteMagnitude
        var nearProgress = 0.0
        var nearPoint = first
        let continuity = progress.map { near -> (low: Double, high: Double) in
            let anchor = min(1, max(0, near)) * total
            // Stay with the part of the stroke under the finger. A loop's end can sit on
            // its start, and A/B fold back, so cap the forward window to prevent jumping across bends.
            var forwardWindow = min(28.0, max(18.0, total * 0.22))
            if let cuspDist = firstSharpTurnDistance(in: polyline, cumulative: cumulative, after: anchor, within: forwardWindow),
               anchor < cuspDist - 7.0 {
                forwardWindow = min(forwardWindow, (cuspDist - anchor) + 3.5)
            }
            return (anchor - 12.0, anchor + forwardWindow)
        }

        for index in 0..<(polyline.count - 1) {
            let segmentStart = cumulative[index]
            let segment = cumulative[index + 1] - segmentStart
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

    static func isStraightPolyline(_ line: [LetterPoint]) -> Bool {
        guard line.count >= 3, let first = heading(of: line) else { return true }
        for index in 1..<(line.count - 1) {
            let dx = line[index + 1].x - line[index].x
            let dy = line[index + 1].y - line[index].y
            let span = (dx * dx + dy * dy).squareRoot()
            guard span > 0 else { continue }
            let aligned = first.x * (dx / span) + first.y * (dy / span)
            if aligned < 0.92 { return false }
        }
        return true
    }

    static func computeTrackBounds(strokes: [LetterStroke], roadHalfWidth: Double) -> TrackBounds {
        guard !strokes.isEmpty else {
            return TrackBounds(minX: 0, maxX: 100, minY: 0, maxY: 100)
        }
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        let roadPad = roadHalfWidth + 2.2

        for stroke in strokes {
            for point in stroke.middleGuide {
                minX = min(minX, point.x - roadPad)
                maxX = max(maxX, point.x + roadPad)
                minY = min(minY, point.y - roadPad)
                maxY = max(maxY, point.y + roadPad)
            }
            if let heading = heading(of: stroke.centerline, at: 0) {
                let arrowBack = LetterPoint(
                    x: stroke.start.x - heading.x * 14.0,
                    y: stroke.start.y - heading.y * 14.0
                )
                let arrowPad = 4.0
                minX = min(minX, arrowBack.x - arrowPad)
                maxX = max(maxX, arrowBack.x + arrowPad)
                minY = min(minY, arrowBack.y - arrowPad)
                maxY = max(maxY, arrowBack.y + arrowPad)
            }
        }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return TrackBounds(minX: 0, maxX: 100, minY: 0, maxY: 100)
        }
        return TrackBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    static func computeRoadPieces(strokes: [LetterStroke], half: Double) -> [RoadPiece] {
        strokes.enumerated().map { index, stroke in
            let line = stroke.centerline
            guard line.count >= 2 else { return RoadPiece(asphalt: line, curb: line) }
            let startJoined = joins(line[0], besides: index, strokes: strokes, half: half)
            let endJoined = joins(line[line.count - 1], besides: index, strokes: strokes, half: half)
            var asphalt = line
            if !endJoined {
                asphalt = stroke.endPaved
            }
            var curb = asphalt
            if startJoined {
                curb = trim(curb, fromEnd: false, besides: index, strokes: strokes, half: half)
            }
            if endJoined {
                curb = trim(curb, fromEnd: true, besides: index, strokes: strokes, half: half)
            }
            if curb.count < 2 { curb = asphalt }
            return RoadPiece(asphalt: asphalt, curb: curb)
        }
    }

    static func computeCheckeredGate(
        for stroke: LetterStroke,
        roads: [[LetterPoint]],
        half: Double
    ) -> CheckeredGateCache {
        let end = stroke.centerline.last ?? stroke.gate.center
        let heading = Self.heading(of: stroke.centerline, at: 1) ?? LetterPoint(x: 1, y: 0)
        let bandStart = FinishZone.offsets.first ?? 0
        let bandEnd = FinishZone.endOffset
        let rows = 6
        let cellAcross = (half * 2) / Double(rows)
        let columns = max(2, Int(((bandEnd - bandStart) / cellAcross).rounded()))
        let cellAlong = (bandEnd - bandStart) / Double(columns)
        var cells: [GateCell] = []

        for row in 0..<rows {
            for column in 0..<columns {
                let along0 = bandStart + Double(column) * cellAlong
                let across0 = -half + Double(row) * cellAcross
                let center = LetterPoint(
                    x: end.x + heading.x * (along0 + cellAlong / 2) - heading.y * (across0 + cellAcross / 2),
                    y: end.y + heading.y * (along0 + cellAlong / 2) + heading.x * (across0 + cellAcross / 2)
                )
                let onRoad = roads.contains { road in
                    project(center, onto: road).distance <= half * 0.98
                }
                if onRoad {
                    cells.append(GateCell(
                        along0: along0,
                        across0: across0,
                        cellAlong: cellAlong,
                        cellAcross: cellAcross,
                        isBlack: (row + column).isMultiple(of: 2)
                    ))
                }
            }
        }
        let shared = roads.filter { project(end, onto: $0).distance <= half * 0.5 }.count
        return CheckeredGateCache(
            end: end,
            heading: heading,
            half: half,
            bandStart: bandStart,
            bandEnd: bandEnd,
            drawsBorder: shared < 2,
            cells: cells
        )
    }

    private static func joins(_ point: LetterPoint, besides index: Int, strokes: [LetterStroke], half: Double) -> Bool {
        for (other, stroke) in strokes.enumerated() where other != index {
            if project(point, onto: stroke.centerline).distance <= half * 1.25 {
                return true
            }
        }
        return false
    }

    private static func covered(_ point: LetterPoint, besides index: Int, strokes: [LetterStroke], half: Double) -> Bool {
        for (other, stroke) in strokes.enumerated() where other != index {
            if project(point, onto: stroke.centerline).distance <= half * 0.94 {
                return true
            }
        }
        return false
    }

    private static func trim(
        _ line: [LetterPoint],
        fromEnd: Bool,
        besides index: Int,
        strokes: [LetterStroke],
        half: Double
    ) -> [LetterPoint] {
        let total = length(of: line)
        guard line.count >= 2, total > 1 else { return line }
        let startPoint = fromEnd ? line[line.count - 1] : line[0]
        guard covered(startPoint, besides: index, strokes: strokes, half: half) else { return line }

        let step = 1.0
        var dist = step
        while dist < total {
            let progress = fromEnd ? max(0, 1 - dist / total) : min(1, dist / total)
            let sample = point(at: progress, along: line)
            if !covered(sample, besides: index, strokes: strokes, half: half) {
                let cut = max(0, dist - step * 0.45)
                let trimmed = fromEnd ? drop(cut, fromEndOf: line) : drop(cut, fromStartOf: line)
                return trimmed.count >= 2 ? trimmed : line
            }
            dist += step
        }
        return line
    }

    private static func drop(_ distance: Double, fromStartOf line: [LetterPoint]) -> [LetterPoint] {
        guard line.count >= 2, distance > 0 else { return line }
        var left = distance
        var index = 0
        while index < line.count - 1 {
            let step = line[index].distance(to: line[index + 1])
            if left <= step {
                let t = step > 0 ? left / step : 0
                let mid = LetterPoint(
                    x: line[index].x + (line[index + 1].x - line[index].x) * t,
                    y: line[index].y + (line[index + 1].y - line[index].y) * t
                )
                return [mid] + Array(line[(index + 1)...])
            }
            left -= step
            index += 1
        }
        return [line[line.count - 1]]
    }

    private static func drop(_ distance: Double, fromEndOf line: [LetterPoint]) -> [LetterPoint] {
        let trimmed = drop(distance, fromStartOf: Array(line.reversed()))
        return Array(trimmed.reversed())
    }

    /// Strictly monotonic forward projection along `polyline` starting from `progress`.
    /// Prevents cars from snapping backward or jumping across overlapping/returning bowls (like on B).
    static func projectForward(
        _ point: LetterPoint,
        onto polyline: [LetterPoint],
        from progress: Double,
        maxAdvance: Double = 14.0
    ) -> RoadProjection {
        guard let first = polyline.first else {
            return RoadProjection(distance: 0, progress: 0, closest: point)
        }
        guard polyline.count >= 2 else {
            return RoadProjection(distance: point.distance(to: first), progress: 0, closest: first)
        }
        let cumulative = cumulativeLengths(polyline)
        let total = cumulative.last ?? 0
        guard total > 0 else {
            return RoadProjection(distance: point.distance(to: first), progress: 0, closest: first)
        }

        let startAlong = min(1, max(0, progress)) * total
        var maxAlong = min(total, startAlong + max(2.0, maxAdvance))
        if let cuspDist = firstSharpTurnDistance(in: polyline, cumulative: cumulative, after: startAlong, within: maxAdvance),
           startAlong < cuspDist - 2.2 {
            maxAlong = min(maxAlong, cuspDist)
        }

        var bestDistance = Double.greatestFiniteMagnitude
        var bestProgress = min(1, max(0, progress))
        var bestPoint = Self.point(atDistance: startAlong, along: polyline, cumulative: cumulative)

        for index in 0..<(polyline.count - 1) {
            let segStart = cumulative[index]
            let segEnd = cumulative[index + 1]
            let segment = segEnd - segStart

            if segEnd < startAlong - 0.5 { continue }
            if segStart > maxAlong + 0.5 { break }
            guard segment > 0 else { continue }

            let tLow = max(0, min(1, (startAlong - segStart) / segment))
            let tHigh = max(tLow, min(1, (maxAlong - segStart) / segment))
            let start = polyline[index]
            let end = polyline[index + 1]
            let (_, rawT) = closestPoint(point, start, end)
            let clampedT = min(tHigh, max(tLow, rawT))
            let candidate = LetterPoint(
                x: start.x + (end.x - start.x) * clampedT,
                y: start.y + (end.y - start.y) * clampedT
            )
            let distance = point.distance(to: candidate)
            let along = segStart + clampedT * segment
            if distance < bestDistance {
                bestDistance = distance
                bestPoint = candidate
                bestProgress = max(bestProgress, min(1, along / total))
            }
        }
        return RoadProjection(distance: bestDistance, progress: bestProgress, closest: bestPoint)
    }

    struct CuspInfo: Equatable {
        var progress: Double
        var distanceAhead: Double
        var point: LetterPoint
        var incomingHeading: LetterPoint
        var outgoingHeading: LetterPoint
        var turnAngle: Double
    }

    /// Detects an upcoming sharp cusp or reversal (such as the waist of B) within `lookDistance` ahead.
    static func upcomingCusp(
        along polyline: [LetterPoint],
        from progress: Double,
        within lookDistance: Double = 24.0
    ) -> CuspInfo? {
        upcomingCusp(along: polyline, cumulative: cumulativeLengths(polyline), from: progress, within: lookDistance)
    }

    static func upcomingCusp(
        along polyline: [LetterPoint],
        cumulative: [Double],
        from progress: Double,
        within lookDistance: Double = 24.0
    ) -> CuspInfo? {
        guard polyline.count >= 3, let total = cumulative.last, total > 1 else { return nil }

        let startAlong = min(1, max(0, progress)) * total
        let limitAlong = min(total, startAlong + lookDistance)

        for index in 1..<(polyline.count - 1) {
            let traveled = cumulative[index]
            if traveled < startAlong - 1.0 { continue }
            if traveled > limitAlong { break }

            var backIdx = index - 1
            while backIdx > 0, traveled - cumulative[backIdx] < 4.0 {
                backIdx -= 1
            }
            var fwdIdx = index + 1
            while fwdIdx < polyline.count - 1, cumulative[fwdIdx] - traveled < 4.0 {
                fwdIdx += 1
            }

            let inPoint = polyline[backIdx]
            let vertex = polyline[index]
            let outPoint = polyline[fwdIdx]

            let inDx = vertex.x - inPoint.x
            let inDy = vertex.y - inPoint.y
            let inLen = hypot(inDx, inDy)
            let outDx = outPoint.x - vertex.x
            let outDy = outPoint.y - vertex.y
            let outLen = hypot(outDx, outDy)
            guard inLen > 0.4, outLen > 0.4 else { continue }

            let inHeading = LetterPoint(x: inDx / inLen, y: inDy / inLen)
            let outHeading = LetterPoint(x: outDx / outLen, y: outDy / outLen)
            let dot = max(-1, min(1, inHeading.x * outHeading.x + inHeading.y * outHeading.y))
            let turn = acos(dot)
            if turn >= 1.80 {
                return CuspInfo(
                    progress: traveled / total,
                    distanceAhead: max(0, traveled - startAlong),
                    point: vertex,
                    incomingHeading: inHeading,
                    outgoingHeading: outHeading,
                    turnAngle: turn
                )
            }
        }
        return nil
    }

    private static func firstSharpTurnDistance(
        in polyline: [LetterPoint],
        cumulative: [Double],
        after startAlong: Double,
        within window: Double
    ) -> Double? {
        guard polyline.count >= 3 else { return nil }
        let limit = startAlong + window

        for index in 1..<(polyline.count - 1) {
            let traveled = cumulative[index]
            if traveled <= startAlong + 0.5 { continue }
            if traveled > limit { break }

            var backIdx = index - 1
            while backIdx > 0, traveled - cumulative[backIdx] < 3.5 {
                backIdx -= 1
            }
            var fwdIdx = index + 1
            while fwdIdx < polyline.count - 1, cumulative[fwdIdx] - traveled < 3.5 {
                fwdIdx += 1
            }

            let pIn = polyline[backIdx]
            let pMid = polyline[index]
            let pOut = polyline[fwdIdx]
            let inDx = pMid.x - pIn.x
            let inDy = pMid.y - pIn.y
            let outDx = pOut.x - pMid.x
            let outDy = pOut.y - pMid.y
            let inLen = hypot(inDx, inDy)
            let outLen = hypot(outDx, outDy)
            guard inLen > 0.3, outLen > 0.3 else { continue }
            let dot = (inDx * outDx + inDy * outDy) / (inLen * outLen)
            if dot < -0.15 {
                return traveled
            }
        }
        return nil
    }

    static func length(of polyline: [LetterPoint]) -> Double {
        guard polyline.count >= 2 else { return 0 }
        var sum = 0.0
        for index in 0..<(polyline.count - 1) {
            sum += polyline[index].distance(to: polyline[index + 1])
        }
        return sum
    }

    static func point(at progress: Double, along polyline: [LetterPoint]) -> LetterPoint {
        let cumulative = cumulativeLengths(polyline)
        let total = cumulative.last ?? 0
        return point(atDistance: min(1, max(0, progress)) * total, along: polyline, cumulative: cumulative)
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

    static func suffix(
        _ polyline: [LetterPoint],
        cumulative: [Double]? = nil,
        from progress: Double
    ) -> [LetterPoint] {
        guard let last = polyline.last else { return [] }
        guard polyline.count >= 2 else { return polyline }
        let clamped = min(1, max(0, progress))
        if clamped <= 0 { return polyline }
        if clamped >= 1 { return [last] }

        let cum = cumulative ?? cumulativeLengths(polyline)
        let total = cum.last ?? 0
        guard total > 0 else { return [last] }
        let target = clamped * total
        var low = 0
        var high = cum.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cum[mid] <= target {
                low = mid
            } else {
                high = mid
            }
        }
        let startPoint = point(atDistance: target, along: polyline, cumulative: cum)
        var result = [startPoint]
        result.append(contentsOf: polyline[high...])
        return result
    }

    /// Two-pass Chaikin corner-cutting that preserves start and end points.
    static func smoothed(_ points: [LetterPoint], iterations: Int = 2) -> [LetterPoint] {
        guard points.count >= 3, iterations > 0 else { return points }
        var current = points
        for _ in 0..<iterations {
            guard current.count >= 3 else { break }
            var next: [LetterPoint] = [current[0]]
            for index in 0..<(current.count - 1) {
                let p0 = current[index]
                let p1 = current[index + 1]
                next.append(LetterPoint(
                    x: 0.75 * p0.x + 0.25 * p1.x,
                    y: 0.75 * p0.y + 0.25 * p1.y
                ))
                next.append(LetterPoint(
                    x: 0.25 * p0.x + 0.75 * p1.x,
                    y: 0.25 * p0.y + 0.75 * p1.y
                ))
            }
            next.append(current[current.count - 1])
            current = next
        }
        return current
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

    /// Direction of the road at `progress`, smoothed over a ±1.25-unit central difference window
    /// so heading angles vary continuously across polyline vertices.
    static func heading(of polyline: [LetterPoint], at progress: Double) -> LetterPoint? {
        let cumulative = cumulativeLengths(polyline)
        guard let total = cumulative.last, total > 0 else { return nil }
        return heading(atDistance: min(1, max(0, progress)) * total, along: polyline, cumulative: cumulative)
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
        cumulative: [Double]? = nil,
        halfWidth: Double,
        wallHits: Int
    ) -> StrokeAccuracy {
        guard halfWidth > 0, !path.isEmpty else {
            return StrokeAccuracy(closeness: 0, stars: 1)
        }
        let cum = cumulative ?? RoadGeometry.cumulativeLengths(centerline)
        let distances = path.map { RoadGeometry.project($0, onto: centerline, cumulative: cum).distance }
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
