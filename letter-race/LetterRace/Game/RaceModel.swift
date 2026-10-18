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
    static let carReach = 12.0
    static let minimumTravel = 0.62
    static let finishProgress = 0.8
    /// How far the finger must travel before a backward start counts.
    static let directionSample = 6.0
    /// Opening the stroke this far against its heading ends the attempt.
    static let openingProgress = 0.22
    /// Going back along the road by this much stops the stroke.
    static let backwardDistance = 4.0

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

        let projection = RoadGeometry.project(point, onto: stroke.centerline)
        phase = .tracing
        wallHits = 0
        currentTrace = [point]
        traceStartedAt = time
        onRoad = projection.distance <= track.roadHalfWidth
        maxProgress = onRoad ? projection.progress : 0
    }

    mutating func move(to point: LetterPoint, time: TimeInterval = 0) {
        guard phase == .tracing, let stroke = activeStroke, let track else { return }
        let projection = RoadGeometry.project(point, onto: stroke.centerline)
        let inside = projection.distance <= track.roadHalfWidth
        let inGate = point.distance(to: stroke.gate.center) <= stroke.gate.radius

        if reachedFinish(progress: projection.progress, inside: inside, inGate: inGate) {
            currentTrace.append(point)
            finishStroke(at: time)
            return
        }

        currentTrace.append(point)
        if openedBackward(point, on: stroke) || (inside && wentBackward(projection, along: stroke)) {
            currentTrace = []
            shownStars = 0
            phase = .failed
            return
        }

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

    private func reachedFinish(progress: Double, inside: Bool, inGate: Bool) -> Bool {
        let atEnd = inGate || (inside && progress >= Self.finishProgress)
        return atEnd && maxProgress >= Self.minimumTravel
    }

    private func wentBackward(_ projection: RoadProjection, along stroke: LetterStroke) -> Bool {
        let length = RoadGeometry.length(of: stroke.centerline)
        return (maxProgress - projection.progress) * length > Self.backwardDistance
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
