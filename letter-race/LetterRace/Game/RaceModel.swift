import Foundation

enum RacePhase: Equatable {
    case awaiting
    case tracing
    case driving
    case replaying
    case failed
    case almost
    case success
}

struct RaceModel: Equatable {
    var glyph: Glyph
    var phase: RacePhase = .awaiting
    var activeStrokeIndex = 0
    var wallHits = 0
    var currentTrace: [LetterPoint] = []
    var currentTraceLength = 0.0
    var cachedLivePath: [LetterPoint] = []
    var cachedLiveCumulative: [Double] = [0]
    var recordedPaths: [[LetterPoint]] = []
    var maxProgress = 0.0
    var onRoad = false
    var replayIndex = 0
    var earnedStars: [Int] = []
    var shownStars = 0
    var traceStartedAt: TimeInterval?
    var lastTouchTime: TimeInterval?
    var recordedDurations: [TimeInterval] = []
    var liveCar = CarSimulation.LiveFollower()
    var completedLiveCar: CarSimulation.LiveFollower?

    /// A fourth wall hit fails the attempt. Three are still allowed.
    static let maxWallHits = 3
    static let carReach = 16.0
    static let minimumTravel = 0.62
    /// Drawn trajectory length required before the car starts chasing the finger live.
    static let liveLaunchDistance = 15.0
    /// How far the finger must travel before a backward start counts.
    static let directionSample = 6.0
    /// Opening the stroke this far against its heading ends the attempt.
    static let openingProgress = 0.22
    /// Minimum distance between recorded touch samples to filter out finger micro-jitter.
    static let minSampleStep = 0.8
    /// A bend counts only after the finger has held the new direction this far.
    static let cornerSpan = 8.0
    /// Cosine of the sharpest turn still allowed. About 70 degrees.
    static let cornerDot = 0.34

    var track: LetterTrack? { glyph.track }

    var activeStroke: LetterStroke? {
        guard let strokes = track?.strokes, strokes.indices.contains(activeStrokeIndex) else { return nil }
        return strokes[activeStrokeIndex]
    }

    var showsPointer: Bool {
        switch phase {
        case .awaiting, .failed, .almost:
            return true
        default:
            return false
        }
    }

    var isAcceptingTouch: Bool {
        phase == .awaiting || phase == .tracing || phase == .failed
    }

    /// How long the car should take to redraw the stroke now on screen.
    var playbackDuration: TimeInterval {
        let index = phase == .replaying ? replayIndex : activeStrokeIndex
        guard recordedDurations.indices.contains(index) else { return 0.8 }
        return recordedDurations[index]
    }

    mutating func press(at point: LetterPoint, time: TimeInterval = 0) {
        if phase == .failed || phase == .almost {
            clearAttempt()
            shownStars = 0
            phase = .awaiting
        }
        guard phase == .awaiting, let stroke = activeStroke, let track else { return }
        guard point.distance(to: stroke.start) <= Self.carReach else { return }

        let projection = RoadGeometry.project(
            point,
            onto: stroke.centerline,
            cumulative: stroke.cumulativeLengths,
            near: 0
        )
        phase = .tracing
        wallHits = 0
        currentTrace = [point]
        currentTraceLength = 0
        let initialHeading = RoadGeometry.heading(
            atDistance: 0,
            along: stroke.centerline,
            cumulative: stroke.cumulativeLengths
        ) ?? LetterPoint(x: 1, y: 0)
        cachedLivePath = Self.buildLeadIn(from: stroke.start, heading: initialHeading, to: point)
        cachedLiveCumulative = RoadGeometry.cumulativeLengths(cachedLivePath)
        traceStartedAt = time
        lastTouchTime = time
        liveCar = CarSimulation.LiveFollower(start: stroke.start, heading: initialHeading)
        completedLiveCar = nil
        onRoad = projection.distance <= track.roadHalfWidth
        maxProgress = onRoad ? projection.progress : 0
    }

    mutating func move(to point: LetterPoint, time: TimeInterval = 0) {
        guard phase == .tracing, let stroke = activeStroke, let track else { return }
        if let last = currentTrace.last, last.distance(to: point) < Self.minSampleStep {
            let nearGate = point.distance(to: stroke.gate.center) <= track.roadHalfWidth + 6
            if !nearGate { return }
        }
        lastTouchTime = time

        let projection = RoadGeometry.project(
            point,
            onto: stroke.centerline,
            cumulative: stroke.cumulativeLengths,
            near: maxProgress
        )
        let inside = projection.distance <= track.roadHalfWidth

        if reachedFinish(point, projection: projection, halfWidth: track.roadHalfWidth, on: stroke) {
            let finishPoint = FinishZone.middle(on: stroke)
            if let last = currentTrace.last {
                currentTraceLength += last.distance(to: finishPoint)
            }
            currentTrace.append(finishPoint)
            appendLivePoint(finishPoint)
            finishStroke(at: time)
            return
        }

        if turnedSharply(point, projection: projection, inside: inside, halfWidth: track.roadHalfWidth, on: stroke) {
            currentTrace = []
            currentTraceLength = 0
            cachedLivePath = []
            cachedLiveCumulative = [0]
            shownStars = 0
            liveCar = CarSimulation.LiveFollower()
            phase = .failed
            return
        }

        if let last = currentTrace.last {
            let stepDist = last.distance(to: point)
            if stepDist >= Self.minSampleStep {
                currentTrace.append(point)
                currentTraceLength += stepDist
                appendLivePoint(point)
            }
        } else {
            currentTrace.append(point)
            appendLivePoint(point)
        }

        if inside {
            if projection.progress >= maxProgress {
                maxProgress = projection.progress
            }
            onRoad = true
        } else if onRoad {
            onRoad = false
            registerHit()
            if phase == .failed { return }
        }
    }

    mutating func advanceLiveCar(dt: Double, at now: TimeInterval? = nil) {
        // Cars remain parked on the start line until the entire letter is drawn.
    }

    private mutating func appendLivePoint(_ point: LetterPoint) {
        guard let last = cachedLivePath.last else {
            cachedLivePath = [point]
            cachedLiveCumulative = [0]
            return
        }
        let dist = last.distance(to: point)
        guard dist > 0.001 else { return }
        if cachedLivePath.count >= 2 {
            // Incremental corner-softening of the previous vertex so the live path stays smooth in O(1) time.
            let prev = cachedLivePath[cachedLivePath.count - 2]
            let softened = LetterPoint(
                x: 0.2 * prev.x + 0.6 * last.x + 0.2 * point.x,
                y: 0.2 * prev.y + 0.6 * last.y + 0.2 * point.y
            )
            cachedLivePath[cachedLivePath.count - 1] = softened
            cachedLiveCumulative[cachedLiveCumulative.count - 1] =
                cachedLiveCumulative[cachedLiveCumulative.count - 2] + prev.distance(to: softened)
        }
        let updatedLast = cachedLivePath[cachedLivePath.count - 1]
        cachedLivePath.append(point)
        cachedLiveCumulative.append(cachedLiveCumulative[cachedLiveCumulative.count - 1] + updatedLast.distance(to: point))
    }

    private static func buildLeadIn(from start: LetterPoint, heading: LetterPoint, to first: LetterPoint) -> [LetterPoint] {
        let startDist = start.distance(to: first)
        if startDist > 0.5 {
            let control = LetterPoint(
                x: start.x + heading.x * min(startDist * 0.45, 5.0),
                y: start.y + heading.y * min(startDist * 0.45, 5.0)
            )
            return Manuscript.bend(from: start, through: control, to: first, steps: 4)
        } else if startDist > 0.001 {
            return [start, first]
        }
        return [first]
    }

    mutating func release(at point: LetterPoint, time: TimeInterval = 0) {
        guard phase == .tracing else { return }
        move(to: point, time: time)
        guard phase == .tracing else { return }
        clearAttempt()
        shownStars = 0
        phase = .awaiting
    }

    mutating func dismissAlmost() {
        guard phase == .almost else { return }
        clearAttempt()
        shownStars = 0
        phase = .awaiting
    }

    mutating func cancel() {
        guard phase == .tracing else { return }
        clearAttempt()
        phase = .awaiting
    }

    mutating func tryAgain() {
        guard phase == .failed else { return }
        clearAttempt()
        phase = .awaiting
    }

    mutating func motionFinished() {
        guard let count = track?.strokes.count else { return }
        switch phase {
        case .driving:
            if activeStrokeIndex + 1 < count {
                activeStrokeIndex += 1
                clearAttempt()
                phase = .awaiting
            } else {
                replayIndex = 0
                phase = .replaying
            }
        case .replaying:
            if replayIndex + 1 < count {
                replayIndex += 1
            } else {
                phase = .success
            }
        default:
            break
        }
    }

    mutating func replay() {
        guard !recordedPaths.isEmpty else { return }
        replayIndex = 0
        phase = .replaying
    }

    mutating func reset() {
        phase = .awaiting
        activeStrokeIndex = 0
        recordedPaths = []
        recordedDurations = []
        replayIndex = 0
        earnedStars = []
        shownStars = 0
        traceStartedAt = nil
        clearAttempt()
    }

    /// The ink stops at the middle stripe, not at the near edge of the hatches.
    /// A loop's start can sit on its own finish, so the finger also has to be near the
    /// end of the stroke, not merely standing where the circle began.
    private func reachedFinish(
        _ point: LetterPoint,
        projection: RoadProjection,
        halfWidth: Double,
        on stroke: LetterStroke
    ) -> Bool {
        guard maxProgress >= Self.minimumTravel, projection.progress >= 0.90 else { return false }
        guard let heading = RoadGeometry.heading(of: stroke.centerline, at: 1) else { return false }
        let gate = stroke.gate.center
        let along = (point.x - gate.x) * heading.x + (point.y - gate.y) * heading.y
        let lateral = abs((point.x - gate.x) * -heading.y + (point.y - gate.y) * heading.x)
        // A hair of slack so the exact middle stripe is not missed by rounding.
        return lateral <= halfWidth && along >= FinishZone.middleOffset - 0.05
    }

    /// A sharp corner, or a sustained move back along the stroke, ends the ink.
    /// On a bent letter the road itself turns around, as in the middle of B, so that
    /// opposite direction is allowed while the finger is following the road ahead.
    private func turnedSharply(
        _ point: LetterPoint,
        projection: RoadProjection,
        inside: Bool,
        halfWidth: Double,
        on stroke: LetterStroke
    ) -> Bool {
        if openedBackward(point, on: stroke) { return true }
        guard let recent = courseWithCurrent(point, span: Self.cornerSpan, skip: 0, in: currentTrace) else { return false }

        if !stroke.isStraight {
            if inside && projection.progress + 0.05 >= maxProgress { return false }
            if followsUpcomingBend(point, course: recent, halfWidth: halfWidth, on: stroke) { return false }
            guard projection.progress + 0.04 < maxProgress,
                  let heading = RoadGeometry.heading(
                      atDistance: projection.progress * stroke.totalLength,
                      along: stroke.centerline,
                      cumulative: stroke.cumulativeLengths
                  ) else {
                return false
            }
            let aligned = recent.x * heading.x + recent.y * heading.y
            return aligned < Self.cornerDot
        }

        if let heading = RoadGeometry.heading(
            atDistance: maxProgress * stroke.totalLength,
            along: stroke.centerline,
            cumulative: stroke.cumulativeLengths
        ) {
            let aligned = recent.x * heading.x + recent.y * heading.y
            if aligned < Self.cornerDot { return true }
        }
        if let earlier = courseWithCurrent(point, span: Self.cornerSpan, skip: Self.cornerSpan, in: currentTrace) {
            let turn = recent.x * earlier.x + recent.y * earlier.y
            if turn < Self.cornerDot { return true }
        }
        return false
    }

    /// The finger is heading along a later part of this stroke, so the letter is folding back.
    private func followsUpcomingBend(
        _ point: LetterPoint,
        course recent: LetterPoint,
        halfWidth: Double,
        on stroke: LetterStroke
    ) -> Bool {
        let line = stroke.centerline
        let cumulative = stroke.cumulativeLengths
        let total = stroke.totalLength
        guard total > 0 else { return false }
        let reach = halfWidth * 1.25
        var dist = max(0, (maxProgress - 0.03) * total)
        let step = max(total * 0.015, 5.0)
        while dist <= total + 0.001 {
            let clampedDist = min(total, dist)
            let sample = RoadGeometry.point(atDistance: clampedDist, along: line, cumulative: cumulative)
            if sample.distance(to: point) <= reach,
               let heading = RoadGeometry.heading(atDistance: clampedDist, along: line, cumulative: cumulative) {
                let aligned = recent.x * heading.x + recent.y * heading.y
                if aligned >= Self.cornerDot { return true }
            }
            dist += step
        }
        return false
    }

    private func roadIsStraight(_ stroke: LetterStroke) -> Bool {
        let line = stroke.centerline
        guard line.count >= 3, let first = RoadGeometry.heading(of: line) else { return true }
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

    /// Unit direction of one stretch of the ink, walking backward from the finger without copying `samples`.
    private func courseWithCurrent(_ current: LetterPoint, span: Double, skip: Double, in samples: [LetterPoint]) -> LetterPoint? {
        guard let near = pointWithCurrent(current, back: skip, in: samples),
              let far = pointWithCurrent(current, back: skip + span, in: samples) else { return nil }
        let dx = near.x - far.x
        let dy = near.y - far.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length >= span * 0.72 else { return nil }
        return LetterPoint(x: dx / length, y: dy / length)
    }

    private func pointWithCurrent(_ current: LetterPoint, back distance: Double, in samples: [LetterPoint]) -> LetterPoint? {
        if distance <= 0 { return current }
        var remaining = distance
        var cursor = current
        var index = samples.count
        while index > 0 {
            let previous = samples[index - 1]
            let leg = cursor.distance(to: previous)
            if leg >= remaining {
                let t = leg == 0 ? 0 : remaining / leg
                return LetterPoint(
                    x: cursor.x + (previous.x - cursor.x) * t,
                    y: cursor.y + (previous.y - cursor.y) * t
                )
            }
            remaining -= leg
            cursor = previous
            index -= 1
        }
        return nil
    }

    private mutating func finishStroke(at time: TimeInterval) {
        guard let stroke = activeStroke, let track else { return }
        let accuracy = StrokeAccuracy.measure(
            path: currentTrace,
            centerline: stroke.centerline,
            cumulative: stroke.cumulativeLengths,
            halfWidth: track.roadHalfWidth,
            wallHits: wallHits
        )
        shownStars = accuracy.stars
        if accuracy.isGoodEnough {
            let elapsed = time - (traceStartedAt ?? time)
            recordedPaths.append(Self.smoothedDrivePath(from: currentTrace, on: stroke))
            recordedDurations.append(max(0.05, elapsed))
            earnedStars.append(accuracy.stars)
            if activeStrokeIndex + 1 < track.strokes.count {
                activeStrokeIndex += 1
                completedLiveCar = nil
                clearAttempt()
                phase = .awaiting
            } else {
                completedLiveCar = nil
                replayIndex = 0
                clearAttempt()
                phase = .replaying
            }
        } else {
            phase = .almost
        }
    }

    /// Smoothed path from `stroke.start` through the user's current finger trace, used while
    /// the car actively chases the finger during `.tracing`.
    static func liveTracePath(from trace: [LetterPoint], on stroke: LetterStroke) -> [LetterPoint] {
        guard !trace.isEmpty else { return [stroke.start] }
        var path: [LetterPoint] = []
        if let first = trace.first {
            let startDist = stroke.start.distance(to: first)
            if startDist > 0.5 {
                let heading = RoadGeometry.heading(of: stroke.centerline, at: 0) ?? LetterPoint(x: 1, y: 0)
                let control = LetterPoint(
                    x: stroke.start.x + heading.x * min(startDist * 0.45, 5.0),
                    y: stroke.start.y + heading.y * min(startDist * 0.45, 5.0)
                )
                let leadIn = Manuscript.bend(from: stroke.start, through: control, to: first, steps: 4)
                path.append(contentsOf: leadIn.dropLast())
            } else if startDist > 0.001 {
                path.append(stroke.start)
            }
        }
        path.append(contentsOf: trace)
        return RoadGeometry.smoothed(path, iterations: 1)
    }

    /// Prepends a smooth lead-in from `stroke.start`, extends the finish smoothly along the
    /// stroke heading to `FinishZone.middle(on: stroke)`, and applies 2-pass Chaikin smoothing.
    static func smoothedDrivePath(from trace: [LetterPoint], on stroke: LetterStroke) -> [LetterPoint] {
        guard !trace.isEmpty else { return trace }
        let finish = FinishZone.middle(on: stroke)
        var core = trace
        if core.count >= 2, let last = core.last, last.distance(to: finish) < 0.001 {
            core.removeLast()
        }

        var path: [LetterPoint] = []
        if let first = core.first {
            let startDist = stroke.start.distance(to: first)
            if startDist > 0.5 {
                let heading = RoadGeometry.heading(of: stroke.centerline, at: 0) ?? LetterPoint(x: 1, y: 0)
                let control = LetterPoint(
                    x: stroke.start.x + heading.x * min(startDist * 0.45, 5.0),
                    y: stroke.start.y + heading.y * min(startDist * 0.45, 5.0)
                )
                let leadIn = Manuscript.bend(from: stroke.start, through: control, to: first, steps: 4)
                path.append(contentsOf: leadIn.dropLast())
            } else if startDist > 0.001 {
                path.append(stroke.start)
            }
        }
        path.append(contentsOf: core)

        if let last = path.last {
            let endDist = last.distance(to: finish)
            if endDist > 0.5, let heading = RoadGeometry.heading(of: stroke.centerline, at: 1) {
                let control = LetterPoint(
                    x: finish.x - heading.x * min(endDist * 0.45, 5.0),
                    y: finish.y - heading.y * min(endDist * 0.45, 5.0)
                )
                let runout = Manuscript.bend(from: last, through: control, to: finish, steps: 4)
                path.append(contentsOf: runout.dropFirst())
            } else if endDist > 0.0001 {
                path.append(finish)
            }
        } else {
            path.append(finish)
        }

        return RoadGeometry.smoothed(path, iterations: 2)
    }

    private func openedBackward(_ point: LetterPoint, on stroke: LetterStroke) -> Bool {
        guard maxProgress < Self.openingProgress, let heading = RoadGeometry.heading(of: stroke.centerline) else {
            return false
        }
        let dx = point.x - stroke.start.x
        let dy = point.y - stroke.start.y
        let travel = (dx * dx + dy * dy).squareRoot()
        guard travel >= Self.directionSample else { return false }
        let dot = (dx * heading.x + dy * heading.y) / travel
        return dot < 0
    }

    private mutating func registerHit() {
        wallHits += 1
        if wallHits > Self.maxWallHits {
            currentTrace = []
            phase = .failed
        }
    }

    private mutating func clearAttempt() {
        currentTrace = []
        currentTraceLength = 0
        cachedLivePath = []
        cachedLiveCumulative = [0]
        wallHits = 0
        maxProgress = 0
        onRoad = false
        traceStartedAt = nil
        lastTouchTime = nil
        if let stroke = activeStroke,
           let heading = RoadGeometry.heading(atDistance: 0, along: stroke.centerline, cumulative: stroke.cumulativeLengths) {
            liveCar = CarSimulation.LiveFollower(start: stroke.start, heading: heading)
        } else {
            liveCar = CarSimulation.LiveFollower()
        }
    }
}
