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
    var recordedPaths: [[LetterPoint]] = []
    var maxProgress = 0.0
    var onRoad = false
    var replayIndex = 0
    var earnedStars: [Int] = []
    var shownStars = 0
    var traceStartedAt: TimeInterval?
    var recordedDurations: [TimeInterval] = []

    /// A fourth wall hit fails the attempt. Three are still allowed.
    static let maxWallHits = 3
    static let carReach = 16.0
    static let minimumTravel = 0.62
    /// How far the finger must travel before a backward start counts.
    static let directionSample = 6.0
    /// Opening the stroke this far against its heading ends the attempt.
    static let openingProgress = 0.22
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

        let projection = RoadGeometry.project(point, onto: stroke.centerline, near: 0)
        phase = .tracing
        wallHits = 0
        currentTrace = [point]
        traceStartedAt = time
        onRoad = projection.distance <= track.roadHalfWidth
        maxProgress = onRoad ? projection.progress : 0
    }

    mutating func move(to point: LetterPoint, time: TimeInterval = 0) {
        guard phase == .tracing, let stroke = activeStroke, let track else { return }
        let projection = RoadGeometry.project(point, onto: stroke.centerline, near: maxProgress)
        let inside = projection.distance <= track.roadHalfWidth

        if reachedFinish(point, projection: projection, halfWidth: track.roadHalfWidth, on: stroke) {
            currentTrace.append(FinishZone.middle(on: stroke))
            finishStroke(at: time)
            return
        }

        if turnedSharply(point, projection: projection, inside: inside, on: stroke) {
            currentTrace = []
            shownStars = 0
            phase = .failed
            return
        }

        currentTrace.append(point)

        if inside {
            if projection.progress >= maxProgress {
                maxProgress = projection.progress
            }
            onRoad = true
        } else if onRoad {
            onRoad = false
            registerHit()
        }
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
    /// Folding back is allowed when that fold is the letter itself: the finger is still
    /// moving forward along the road, as in the middle of B or around Q.
    private func turnedSharply(
        _ point: LetterPoint,
        projection: RoadProjection,
        inside: Bool,
        on stroke: LetterStroke
    ) -> Bool {
        if openedBackward(point, on: stroke) { return true }
        // A bend that stays on the road is the letter, as in W or the bowls of B.
        if inside && projection.progress + 0.02 >= maxProgress && !roadIsStraight(stroke) {
            return false
        }
        let samples = currentTrace + [point]
        guard let recent = course(span: Self.cornerSpan, skip: 0, in: samples) else { return false }
        if let heading = RoadGeometry.heading(of: stroke.centerline, at: maxProgress) {
            let aligned = recent.x * heading.x + recent.y * heading.y
            if aligned < Self.cornerDot { return true }
        }
        if roadIsStraight(stroke), let earlier = course(span: Self.cornerSpan, skip: Self.cornerSpan, in: samples) {
            let turn = recent.x * earlier.x + recent.y * earlier.y
            if turn < Self.cornerDot { return true }
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

    /// Unit direction of one stretch of the ink, walking backward from the finger.
    /// Nil when that stretch folds back on itself, so a small correction is not a corner.
    private func course(span: Double, skip: Double, in samples: [LetterPoint]) -> LetterPoint? {
        guard let near = point(back: skip, in: samples),
              let far = point(back: skip + span, in: samples) else { return nil }
        let dx = near.x - far.x
        let dy = near.y - far.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length >= span * 0.72 else { return nil }
        return LetterPoint(x: dx / length, y: dy / length)
    }

    private func point(back distance: Double, in samples: [LetterPoint]) -> LetterPoint? {
        guard var cursor = samples.last else { return nil }
        if distance <= 0 { return cursor }
        var remaining = distance
        var index = samples.count - 1
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
            halfWidth: track.roadHalfWidth,
            wallHits: wallHits
        )
        shownStars = accuracy.stars
        if accuracy.isGoodEnough {
            let elapsed = time - (traceStartedAt ?? time)
            recordedPaths.append(currentTrace)
            recordedDurations.append(max(0.05, elapsed))
            earnedStars.append(accuracy.stars)
            clearAttempt()
            phase = .driving
        } else {
            phase = .almost
        }
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
        wallHits = 0
        maxProgress = 0
        onRoad = false
        traceStartedAt = nil
    }
}
